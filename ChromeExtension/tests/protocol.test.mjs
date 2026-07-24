import assert from "node:assert/strict";
import {createHash, webcrypto} from "node:crypto";
import {readFile} from "node:fs/promises";
import test from "node:test";

if (globalThis.crypto === undefined) {
  globalThis.crypto = webcrypto;
}

const {
  boundedNativeResponse,
  canonicalYouTubeFeedFromExtraction,
  createRequestHandler,
  fingerprintForTab,
  normalizedYouTubeTitle,
  snapshotYouTubeFeed,
  snapshotTab,
  validateRequest,
  validatedTabURL,
  validatedYouTubeFeedPageURL,
} = await import("../protocol.js");

test("YouTube title normalization matches the shared cross-language corpus", async () => {
  const cases = JSON.parse(
    await readFile(
      new URL(
        "../../Fixtures/ChromeNativeMessaging/youtube-title-normalization.json",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  for (const entry of cases) {
    assert.equal(normalizedYouTubeTitle(entry.input), entry.normalized, entry.input);
  }
});

const requestIDs = {
  active: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  activate: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  cancel: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  feed: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
  list: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
  openVideo: "ffffffff-ffff-4fff-8fff-ffffffffffff",
};

function tab(overrides = {}) {
  return {
    id: 7,
    windowId: 3,
    index: 1,
    active: true,
    incognito: false,
    title: "Topher",
    url: "https://example.com/private/path",
    ...overrides,
  };
}

function youtubeTab(overrides = {}) {
  return tab({
    title: "YouTube",
    url: "https://www.youtube.com/",
    ...overrides,
  });
}

function extractedFeed(overrides = {}) {
  const items = overrides.items ?? [
    {
      videoID: "abcDEF123_-",
      title: "Local-first Mac assistants",
      channel: "Example Channel",
    },
    {
      videoID: "ZYX987abc_-",
      title: "Swift concurrency, carefully",
      channel: "Sample Engineering",
    },
  ];
  return {
    items,
    selectionCandidates: overrides.selectionCandidates
      ?? items.map(({videoID, title}) => ({videoID, title})),
    eligibleItemCount: overrides.eligibleItemCount ?? items.length,
    incompleteTitleItemCount: 0,
    incompletePresentationItemCount: 0,
    candidateScanWasTruncated: false,
    ...overrides,
  };
}

function openTarget(snapshot, item = snapshot.items[0], selectionKind = "ordinal") {
  return {
    sourceTabID: snapshot.sourceTabID,
    sourceWindowID: snapshot.sourceWindowID,
    sourceURL: snapshot.sourceURL,
    sourceFingerprint: {value: snapshot.sourceFingerprint},
    feedObservationID: {value: snapshot.feedObservationID},
    capturedAtMilliseconds: snapshot.capturedAtMilliseconds,
    expiresAtMilliseconds: snapshot.expiresAtMilliseconds,
    position: item.position,
    videoID: {value: item.videoID},
    itemObservationID: {value: item.observationID},
    selectionKind,
  };
}

function chromeStub(tabs, {youtubeAccess = true, extractedFeed = null} = {}) {
  const state = {youtubeAccess};
  const calls = {
    get: 0,
    query: 0,
    scripting: 0,
    tabUpdate: 0,
    windowUpdate: 0,
    lastScriptInjection: null,
    lastTabUpdate: null,
  };
  return {
    calls,
    state,
    api: {
      tabs: {
        query: async () => {
          calls.query += 1;
          return tabs;
        },
        get: async (tabID) => {
          calls.get += 1;
          const match = tabs.find((candidate) => candidate.id === tabID);
          if (match === undefined) throw new Error("not found");
          return match;
        },
        update: async (tabID, update) => {
          calls.tabUpdate += 1;
          calls.lastTabUpdate = {tabID, update};
        },
      },
      permissions: {
        contains: async () => state.youtubeAccess,
      },
      scripting: {
        executeScript: async (options) => {
          calls.scripting += 1;
          calls.lastScriptInjection = options;
          return [{frameId: 0, result: extractedFeed}];
        },
      },
      windows: {
        update: async () => {
          calls.windowUpdate += 1;
        },
      },
    },
  };
}

test("manifest keeps YouTube host access optional and requests only the required APIs", async () => {
  const manifest = JSON.parse(await readFile(new URL("../manifest.json", import.meta.url)));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions, ["tabs", "nativeMessaging", "scripting"]);
  assert.equal(manifest.incognito, "not_allowed");
  assert.equal(manifest.minimum_chrome_version, "105");
  assert.equal("host_permissions" in manifest, false);
  assert.deepEqual(manifest.optional_host_permissions, ["https://www.youtube.com/*"]);
  assert.equal("content_scripts" in manifest, false);
  assert.equal("externally_connectable" in manifest, false);
  const publicKey = Buffer.from(manifest.key, "base64");
  const identifier = Array.from(createHash("sha256").update(publicKey).digest().subarray(0, 16))
    .flatMap((byte) => ["abcdefghijklmnop"[byte >> 4], "abcdefghijklmnop"[byte & 15]])
    .join("");
  assert.equal(identifier, "mhbppdheppcibhhcnhnfockmfpcfhndj");
  assert.equal(manifest.action.default_popup, "popup.html");
});

test("shared version-three fixtures match the extension request schema", async () => {
  const listRequest = JSON.parse(
    await readFile(new URL("../../Fixtures/ChromeNativeMessaging/list-request-v3.json", import.meta.url)),
  );
  const activationRequest = JSON.parse(
    await readFile(new URL("../../Fixtures/ChromeNativeMessaging/activate-request-v3.json", import.meta.url)),
  );
  const openRequest = JSON.parse(
    await readFile(new URL("../../Fixtures/ChromeNativeMessaging/open-youtube-request-v3.json", import.meta.url)),
  );
  assert.equal(validateRequest(listRequest).ok, true);
  assert.equal(validateRequest(activationRequest).ok, true);
  assert.equal(validateRequest(openRequest).ok, true);

  const versionTwoRequest = JSON.parse(
    await readFile(new URL("../../Fixtures/ChromeNativeMessaging/list-request-v2.json", import.meta.url)),
  );
  assert.equal(validateRequest(versionTwoRequest).failureCode, "unsupportedVersion");

  const oldRequest = JSON.parse(
    await readFile(new URL("../../Fixtures/ChromeNativeMessaging/list-request-v1.json", import.meta.url)),
  );
  assert.equal(validateRequest(oldRequest).failureCode, "unsupportedVersion");
});

test("URL validation rejects credentials, local files, script data, and oversized input", () => {
  assert.equal(validatedTabURL("https://example.com/path"), "https://example.com/path");
  assert.equal(validatedTabURL("chrome://extensions/"), "chrome://extensions/");
  assert.equal(validatedTabURL("file:///Users/person/secret"), null);
  assert.equal(validatedTabURL("javascript:alert(1)"), null);
  assert.equal(validatedTabURL("data:text/plain,secret"), null);
  assert.equal(validatedTabURL("https://user:password@example.com/"), null);
  assert.equal(validatedTabURL(`https://example.com/${"a".repeat(2048)}`), null);
});

test("composed responses above the transport cap become a fixed typed failure", () => {
  const oversized = {
    version: 3,
    requestID: requestIDs.list,
    status: "success",
    tabs: [{title: "a".repeat(65536)}],
  };
  assert.deepEqual(boundedNativeResponse(oversized, requestIDs.list), {
    version: 3,
    requestID: requestIDs.list,
    status: "failure",
    failureCode: "messageTooLarge",
  });
});

test("request validation rejects malformed, oversized, and mismatched operations", () => {
  assert.deepEqual(validateRequest({version: 99}), {
    ok: false,
    failureCode: "unsupportedVersion",
  });
  assert.equal(
    validateRequest({
      version: 3,
      requestID: requestIDs.list,
      operation: "listTabs",
      maximumTabCount: 51,
    }).failureCode,
    "malformedRequest",
  );
  assert.equal(
    validateRequest({
      version: 3,
      requestID: requestIDs.activate,
      operation: "activateTab",
      target: {tabID: "7"},
    }).failureCode,
    "invalidTarget",
  );
  assert.equal(
    validateRequest({
      version: 3,
      requestID: requestIDs.active,
      operation: "getActiveTab",
      maximumTabCount: 1,
    }).failureCode,
    "malformedRequest",
  );
  assert.equal(
    validateRequest({
      version: 3,
      requestID: requestIDs.activate,
      operation: "activateTab",
      target: {
        tabID: 7,
        windowID: 3,
        fingerprint: {value: "a".repeat(64)},
        capturedAtMilliseconds: 1000,
      },
      cancellationRequestID: requestIDs.cancel,
    }).failureCode,
    "invalidTarget",
  );
  assert.equal(
    validateRequest({
      version: 3,
      requestID: requestIDs.cancel,
      operation: "cancel",
      cancellationRequestID: requestIDs.active,
      target: {},
    }).failureCode,
    "malformedRequest",
  );
});

test("active tab reads one supported non-incognito snapshot", async () => {
  const stub = chromeStub([tab()]);
  const handle = createRequestHandler(stub.api, () => 1000);
  const response = await handle({
    version: 3,
    requestID: requestIDs.active,
    operation: "getActiveTab",
  });

  assert.equal(response.status, "success");
  assert.equal(response.tab.title, "Topher");
  assert.match(response.tab.fingerprint, /^[0-9a-f]{64}$/);
  assert.equal(stub.calls.query, 1);
});

test("tab list excludes incognito and disallowed schemes and enforces the requested count", async () => {
  const stub = chromeStub([
    tab({id: 1, title: "One"}),
    tab({id: 2, title: "Private", incognito: true}),
    tab({id: 3, title: "File", url: "file:///tmp/private"}),
    tab({id: 4, title: "Four"}),
  ]);
  const handle = createRequestHandler(stub.api, () => 1000);
  const response = await handle({
    version: 3,
    requestID: requestIDs.list,
    operation: "listTabs",
    maximumTabCount: 1,
  });

  assert.equal(response.status, "success");
  assert.equal(response.tabs.length, 1);
  assert.equal(response.tabs[0].title, "One");
  assert.equal(response.excludedTabCount, 3);
  assert.equal(response.observationWasTruncated, true);
});

test("unsupported tabs beyond the return bound do not make observation incomplete", async () => {
  const stub = chromeStub([
    tab({id: 1, title: "One"}),
    tab({id: 2, title: "Private", incognito: true}),
    tab({id: 3, title: "File", url: "file:///tmp/private"}),
  ]);
  const handle = createRequestHandler(stub.api, () => 1000);
  const response = await handle({
    version: 3,
    requestID: requestIDs.list,
    operation: "listTabs",
    maximumTabCount: 1,
  });

  assert.equal(response.tabs.length, 1);
  assert.equal(response.excludedTabCount, 2);
  assert.equal(response.observationWasTruncated, false);
});

test("activation revalidates fingerprint and invokes each mutation exactly once", async () => {
  const now = 1000;
  const current = tab();
  const fingerprint = await fingerprintForTab(current);
  const stub = chromeStub([current]);
  const handle = createRequestHandler(stub.api, () => now);
  const request = {
    version: 3,
    requestID: requestIDs.activate,
    operation: "activateTab",
    target: {
      tabID: current.id,
      windowID: current.windowId,
      fingerprint: {value: fingerprint},
      capturedAtMilliseconds: now,
    },
  };

  const first = await handle(request);
  const duplicate = await handle(request);

  assert.equal(first.status, "success");
  assert.equal(duplicate.failureCode, "duplicateRequest");
  assert.equal(stub.calls.get, 1);
  assert.equal(stub.calls.tabUpdate, 1);
  assert.equal(stub.calls.windowUpdate, 1);
});

test("activation refuses stale and changed targets before mutation", async () => {
  const now = 10000;
  const current = tab();
  const fingerprint = await fingerprintForTab(current);
  const stub = chromeStub([current]);
  const handle = createRequestHandler(stub.api, () => now);
  const stale = await handle({
    version: 3,
    requestID: requestIDs.activate,
    operation: "activateTab",
    target: {
      tabID: current.id,
      windowID: current.windowId,
      fingerprint: {value: fingerprint},
      capturedAtMilliseconds: now - 5001,
    },
  });

  assert.equal(stale.failureCode, "staleTab");
  assert.equal(stub.calls.tabUpdate, 0);

  const changedStub = chromeStub([current]);
  const changedHandle = createRequestHandler(changedStub.api, () => now);
  const changed = await changedHandle({
    version: 3,
    requestID: "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee",
    operation: "activateTab",
    target: {
      tabID: current.id,
      windowID: current.windowId,
      fingerprint: {value: "f".repeat(64)},
      capturedAtMilliseconds: now,
    },
  });
  assert.equal(changed.failureCode, "staleTab");
  assert.equal(changedStub.calls.tabUpdate, 0);
});

test("activation rechecks age immediately before mutation", async () => {
  const current = tab();
  const fingerprint = await fingerprintForTab(current);
  const stub = chromeStub([current]);
  const times = [1000, 7001, 7001];
  const handle = createRequestHandler(stub.api, () => times.shift() ?? 7001);
  const response = await handle({
    version: 3,
    requestID: requestIDs.activate,
    operation: "activateTab",
    target: {
      tabID: current.id,
      windowID: current.windowId,
      fingerprint: {value: fingerprint},
      capturedAtMilliseconds: 1000,
    },
  });

  assert.equal(response.failureCode, "staleTab");
  assert.equal(stub.calls.tabUpdate, 0);
  assert.equal(stub.calls.windowUpdate, 0);
});

test("activation API failures after dispatch report unknown outcome without retry", async () => {
  const now = 1000;
  const current = tab();
  const fingerprint = await fingerprintForTab(current);
  const stub = chromeStub([current]);
  stub.api.tabs.update = async () => {
    stub.calls.tabUpdate += 1;
    throw new Error("unknown outcome");
  };
  const handle = createRequestHandler(stub.api, () => now);
  const response = await handle({
    version: 3,
    requestID: requestIDs.activate,
    operation: "activateTab",
    target: {
      tabID: current.id,
      windowID: current.windowId,
      fingerprint: {value: fingerprint},
      capturedAtMilliseconds: now,
    },
  });

  assert.equal(response.failureCode, "activationOutcomeUnknown");
  assert.equal(stub.calls.tabUpdate, 1);
  assert.equal(stub.calls.windowUpdate, 0);
});

test("snapshot rejects title controls and does not expose unsupported URLs", async () => {
  assert.equal(await snapshotTab(tab({title: "bad\u0000title"}), 1000), null);
  assert.equal(await snapshotTab(tab({url: "file:///tmp/private"}), 1000), null);
});

test("YouTube route and extractor-result validation fail closed on untrusted data", async () => {
  assert.equal(
    validatedYouTubeFeedPageURL("https://www.youtube.com/?app=desktop"),
    "https://www.youtube.com/?app=desktop",
  );
  assert.equal(validatedYouTubeFeedPageURL("https://www.youtube.com/feed/subscriptions"), null);
  assert.equal(validatedYouTubeFeedPageURL("https://youtube.com/"), null);
  assert.equal(validatedYouTubeFeedPageURL("https://www.youtube.com.evil.test/"), null);

  const valid = await canonicalYouTubeFeedFromExtraction(extractedFeed());
  assert.equal(valid.items.length, 2);
  assert.match(valid.items[0].observationID, /^[0-9a-f]{64}$/);
  assert.equal(valid.presentationWasTruncated, false);
  assert.equal(valid.titleObservationWasComplete, true);
  assert.equal(valid.items[0].titleMatchIsUnique, true);

  assert.equal(
    await canonicalYouTubeFeedFromExtraction(
      extractedFeed({items: [{videoID: "not-valid", title: "Title", channel: "Channel"}]}),
    ),
    null,
  );
  assert.equal(
    await canonicalYouTubeFeedFromExtraction(
      extractedFeed({
        items: [{videoID: "abcDEF123_-", title: "bad\u0000title", channel: "Channel"}],
      }),
    ),
    null,
  );
  assert.equal(
    await canonicalYouTubeFeedFromExtraction(
      extractedFeed({
        items: [{videoID: "abcDEF123_-", title: "a".repeat(513), channel: "Channel"}],
      }),
    ),
    null,
  );
});

test("YouTube feed read requires optional permission and the exact active Home route", async () => {
  const denied = chromeStub([youtubeTab()], {
    youtubeAccess: false,
    extractedFeed: extractedFeed(),
  });
  const deniedResponse = await createRequestHandler(denied.api, () => 1000)({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });
  assert.equal(deniedResponse.failureCode, "youTubePermissionRequired");
  assert.equal(denied.calls.scripting, 0);

  const unsupported = chromeStub([
    youtubeTab({url: "https://www.youtube.com/watch?v=abcDEF123_-"}),
  ], {extractedFeed: extractedFeed()});
  const unsupportedResponse = await createRequestHandler(unsupported.api, () => 1000)({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });
  assert.equal(unsupportedResponse.failureCode, "unsupportedYouTubePage");
  assert.equal(unsupported.calls.scripting, 0);
});

test("integration status is content-free and reports only optional YouTube access", async () => {
  const granted = chromeStub([youtubeTab()], {youtubeAccess: true});
  const grantedResponse = await createRequestHandler(granted.api, () => 1000)({
    version: 3,
    requestID: "33333333-3333-4333-8333-333333333333",
    operation: "getIntegrationStatus",
  });
  assert.deepEqual(grantedResponse, {
    version: 3,
    requestID: "33333333-3333-4333-8333-333333333333",
    status: "success",
    youTubePermissionGranted: true,
  });
  assert.equal(granted.calls.query, 0);
  assert.equal(granted.calls.scripting, 0);

  const denied = chromeStub([youtubeTab()], {youtubeAccess: false});
  const deniedResponse = await createRequestHandler(denied.api, () => 1000)({
    version: 3,
    requestID: "44444444-4444-4444-8444-444444444444",
    operation: "getIntegrationStatus",
  });
  assert.equal(deniedResponse.youTubePermissionGranted, false);
  assert.equal(denied.calls.query, 0);
  assert.equal(denied.calls.scripting, 0);
});

test("YouTube feed read returns only bounded typed items and explicit completeness", async () => {
  const stub = chromeStub([youtubeTab()], {
    extractedFeed: extractedFeed({
      eligibleItemCount: 3,
      incompleteTitleItemCount: 1,
    }),
  });
  const response = await createRequestHandler(stub.api, () => 1000)({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });

  assert.equal(response.status, "success");
  assert.equal(response.youTubeFeed.items.length, 2);
  assert.equal(response.youTubeFeed.items[0].position, 1);
  assert.equal(response.youTubeFeed.presentationWasTruncated, true);
  assert.equal(response.youTubeFeed.titleObservationWasComplete, false);
  assert.equal(response.youTubeFeed.expiresAtMilliseconds, 91000);
  assert.equal("url" in response.youTubeFeed.items[0], false);
  assert.equal(stub.calls.scripting, 1);
  assert.equal(stub.calls.get, 1);
  assert.deepEqual(stub.calls.lastScriptInjection, {
    target: {tabId: 7, frameIds: [0]},
    files: ["youtube_feed_extractor.js"],
    world: "ISOLATED",
  });
});

test("title uniqueness includes candidates whose channel is still loading", async () => {
  const partial = extractedFeed({
    items: [
      {
        videoID: "abcDEF123_-",
        title: "Duplicate title",
        channel: "Example Channel",
      },
    ],
    selectionCandidates: [
      {videoID: "abcDEF123_-", title: "Duplicate title"},
      {videoID: "ZYX987abc_-", title: "ＤＵＰＬＩＣＡＴＥ　ＴＩＴＬＥ"},
    ],
    eligibleItemCount: 2,
    incompletePresentationItemCount: 1,
  });
  const canonical = await canonicalYouTubeFeedFromExtraction(partial);
  assert.equal(canonical.presentationWasTruncated, true);
  assert.equal(canonical.titleObservationWasComplete, true);
  assert.equal(canonical.items[0].titleMatchIsUnique, false);

  const titleStub = chromeStub([youtubeTab()], {extractedFeed: partial});
  const titleHandle = createRequestHandler(titleStub.api, () => 1000);
  const titleRead = await titleHandle({
    version: 3,
    requestID: "55555555-5555-4555-8555-555555555555",
    operation: "getYouTubeFeed",
  });
  const titleOpen = await titleHandle({
    version: 3,
    requestID: "66666666-6666-4666-8666-666666666666",
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(titleRead.youTubeFeed, titleRead.youTubeFeed.items[0], "title"),
  });
  assert.equal(titleOpen.failureCode, "youTubeFeedChanged");
  assert.equal(titleStub.calls.tabUpdate, 0);

  const ordinalStub = chromeStub([youtubeTab()], {extractedFeed: partial});
  const ordinalHandle = createRequestHandler(ordinalStub.api, () => 1000);
  const ordinalRead = await ordinalHandle({
    version: 3,
    requestID: "77777777-7777-4777-8777-777777777777",
    operation: "getYouTubeFeed",
  });
  const ordinalOpen = await ordinalHandle({
    version: 3,
    requestID: "88888888-8888-4888-8888-888888888888",
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(ordinalRead.youTubeFeed),
  });
  assert.equal(ordinalOpen.status, "success");
  assert.equal(ordinalStub.calls.tabUpdate, 1);
});

test("YouTube feed read refuses active-page drift during extraction", async () => {
  const activeTab = youtubeTab();
  const stub = chromeStub([activeTab], {extractedFeed: extractedFeed()});
  stub.api.scripting.executeScript = async () => {
    stub.calls.scripting += 1;
    activeTab.url = "https://www.youtube.com/watch?v=abcDEF123_-";
    return [{frameId: 0, result: extractedFeed()}];
  };
  const response = await createRequestHandler(stub.api, () => 1000)({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });

  assert.equal(response.failureCode, "youTubeFeedUnavailable");
  assert.equal(stub.calls.get, 1);
  assert.equal(stub.calls.tabUpdate, 0);
});

test("YouTube feed read reports permission revoked during extraction", async () => {
  const stub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  stub.api.scripting.executeScript = async () => {
    stub.calls.scripting += 1;
    stub.state.youtubeAccess = false;
    return [{frameId: 0, result: extractedFeed()}];
  };
  const response = await createRequestHandler(stub.api, () => 1000)({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });

  assert.equal(response.failureCode, "youTubePermissionRequired");
  assert.equal(stub.calls.tabUpdate, 0);
});

test("YouTube open revalidates the active feed and constructs one strict watch URL", async () => {
  const now = 1000;
  const stub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  const handle = createRequestHandler(stub.api, () => now);
  const read = await handle({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });
  const request = {
    version: 3,
    requestID: requestIDs.openVideo,
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(read.youTubeFeed, read.youTubeFeed.items[1]),
  };

  const first = await handle(request);
  const duplicate = await handle(request);
  assert.equal(first.status, "success");
  assert.equal(duplicate.failureCode, "duplicateRequest");
  assert.equal(stub.calls.get, 3);
  assert.equal(stub.calls.scripting, 2);
  assert.equal(stub.calls.tabUpdate, 1);
  assert.deepEqual(stub.calls.lastTabUpdate, {
    tabID: 7,
    update: {url: "https://www.youtube.com/watch?v=ZYX987abc_-"},
  });
  assert.equal(stub.calls.windowUpdate, 0);
});

test("YouTube source identity tolerates tab reordering and page-title churn", async () => {
  const sourceTab = youtubeTab();
  const stub = chromeStub([sourceTab], {extractedFeed: extractedFeed()});
  const handle = createRequestHandler(stub.api, () => 1000);
  const read = await handle({
    version: 3,
    requestID: "99999999-9999-4999-8999-999999999999",
    operation: "getYouTubeFeed",
  });
  sourceTab.index = 8;
  sourceTab.title = "YouTube (updated)";
  const opened = await handle({
    version: 3,
    requestID: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(read.youTubeFeed),
  });
  assert.equal(opened.status, "success");
  assert.equal(stub.calls.tabUpdate, 1);
});

test("YouTube open tolerates unrelated DOM drift but refuses target drift", async () => {
  const now = 1000;
  const driftStub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  const driftHandle = createRequestHandler(driftStub.api, () => now);
  const read = await driftHandle({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });
  driftStub.api.scripting.executeScript = async () => [{
    frameId: 0,
    result: extractedFeed({
      items: [
        {
          videoID: "ZYX987abc_-",
          title: "An unselected recommendation changed",
          channel: "Sample Engineering",
        },
      ],
      selectionCandidates: [
        {
          videoID: "abcDEF123_-",
          title: "Local-first Mac assistants",
        },
        {
          videoID: "ZYX987abc_-",
          title: "An unselected recommendation changed",
        },
      ],
      eligibleItemCount: 2,
      incompletePresentationItemCount: 1,
    }),
  }];
  const unchangedTarget = await driftHandle({
    version: 3,
    requestID: requestIDs.openVideo,
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(read.youTubeFeed),
  });
  assert.equal(unchangedTarget.status, "success");
  assert.equal(driftStub.calls.tabUpdate, 1);

  const selectedDriftStub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  const selectedDriftHandle = createRequestHandler(selectedDriftStub.api, () => now);
  const selectedDriftRead = await selectedDriftHandle({
    version: 3,
    requestID: "11111111-1111-4111-8111-111111111111",
    operation: "getYouTubeFeed",
  });
  selectedDriftStub.api.scripting.executeScript = async () => [{
    frameId: 0,
    result: extractedFeed({
      items: [
        {
          videoID: "abcDEF123_-",
          title: "Selected recommendation changed",
          channel: "Example Channel",
        },
        {
          videoID: "ZYX987abc_-",
          title: "Swift concurrency, carefully",
          channel: "Sample Engineering",
        },
      ],
    }),
  }];
  const changedTarget = await selectedDriftHandle({
    version: 3,
    requestID: "22222222-2222-4222-8222-222222222222",
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(selectedDriftRead.youTubeFeed),
  });
  assert.equal(changedTarget.failureCode, "youTubeFeedChanged");
  assert.equal(selectedDriftStub.calls.tabUpdate, 0);
});

test("YouTube open refuses expiry and permission revocation before mutation", async () => {
  const now = 1000;

  const revokedStub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  const revokedHandle = createRequestHandler(revokedStub.api, () => now);
  const revokedRead = await revokedHandle({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });
  revokedStub.state.youtubeAccess = false;
  const revoked = await revokedHandle({
    version: 3,
    requestID: requestIDs.openVideo,
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(revokedRead.youTubeFeed),
  });
  assert.equal(revoked.failureCode, "youTubePermissionRequired");
  assert.equal(revokedStub.calls.tabUpdate, 0);

  const expiredStub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  const expiredSnapshot = await snapshotYouTubeFeed(youtubeTab(), extractedFeed(), 1000);
  const expired = await createRequestHandler(expiredStub.api, () => 91001)({
    version: 3,
    requestID: requestIDs.openVideo,
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(expiredSnapshot),
  });
  assert.equal(expired.failureCode, "staleYouTubeFeed");
  assert.equal(expiredStub.calls.tabUpdate, 0);
});

test("YouTube open refuses a last-focused Chrome window change during extraction", async () => {
  const sourceTab = youtubeTab();
  const otherWindowTab = youtubeTab({id: 8, windowId: 4, index: 0});
  const stub = chromeStub([sourceTab], {extractedFeed: extractedFeed()});
  const handle = createRequestHandler(stub.api, () => 1000);
  const read = await handle({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });

  let focusMoved = false;
  stub.api.tabs.query = async () => {
    stub.calls.query += 1;
    return focusMoved ? [otherWindowTab] : [sourceTab];
  };
  stub.api.scripting.executeScript = async () => {
    stub.calls.scripting += 1;
    focusMoved = true;
    return [{frameId: 0, result: extractedFeed()}];
  };

  const response = await handle({
    version: 3,
    requestID: requestIDs.openVideo,
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(read.youTubeFeed),
  });

  assert.equal(response.failureCode, "youTubeFeedChanged");
  assert.equal(stub.calls.tabUpdate, 0);
});

test("YouTube navigation API failure is an unknown outcome and is not retried", async () => {
  const stub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  stub.api.tabs.update = async () => {
    stub.calls.tabUpdate += 1;
    throw new Error("acknowledgement lost");
  };
  const handle = createRequestHandler(stub.api, () => 1000);
  const read = await handle({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });
  const response = await handle({
    version: 3,
    requestID: requestIDs.openVideo,
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(read.youTubeFeed),
  });

  assert.equal(response.failureCode, "navigationOutcomeUnknown");
  assert.equal(stub.calls.tabUpdate, 1);
});

test("YouTube open cancellation is observed before navigation", async () => {
  const stub = chromeStub([youtubeTab()], {extractedFeed: extractedFeed()});
  const handle = createRequestHandler(stub.api, () => 1000);
  const read = await handle({
    version: 3,
    requestID: requestIDs.feed,
    operation: "getYouTubeFeed",
  });

  let extractionStarted;
  const started = new Promise((resolve) => {
    extractionStarted = resolve;
  });
  let releaseExtraction;
  const release = new Promise((resolve) => {
    releaseExtraction = resolve;
  });
  stub.api.scripting.executeScript = async () => {
    extractionStarted();
    await release;
    return [{frameId: 0, result: extractedFeed()}];
  };

  const open = handle({
    version: 3,
    requestID: requestIDs.openVideo,
    operation: "openYouTubeVideo",
    youTubeTarget: openTarget(read.youTubeFeed),
  });
  await started;
  const canceled = await handle({
    version: 3,
    requestID: requestIDs.cancel,
    operation: "cancel",
    cancellationRequestID: requestIDs.openVideo,
  });
  releaseExtraction();
  const response = await open;

  assert.equal(canceled.status, "success");
  assert.equal(response.failureCode, "canceled");
  assert.equal(stub.calls.tabUpdate, 0);
});
