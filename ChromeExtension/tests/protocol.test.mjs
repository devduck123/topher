import assert from "node:assert/strict";
import {webcrypto} from "node:crypto";
import {readFile} from "node:fs/promises";
import test from "node:test";

if (globalThis.crypto === undefined) {
  globalThis.crypto = webcrypto;
}

const {
  boundedNativeResponse,
  createRequestHandler,
  fingerprintForTab,
  snapshotTab,
  validateRequest,
  validatedTabURL,
} = await import("../protocol.js");

const requestIDs = {
  active: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  activate: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  cancel: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
  list: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
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

function chromeStub(tabs) {
  const calls = {get: 0, query: 0, tabUpdate: 0, windowUpdate: 0};
  return {
    calls,
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
        update: async () => {
          calls.tabUpdate += 1;
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

test("manifest requests exactly the intended permissions and excludes incognito", async () => {
  const manifest = JSON.parse(await readFile(new URL("../manifest.json", import.meta.url)));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions, ["tabs", "nativeMessaging"]);
  assert.equal(manifest.incognito, "not_allowed");
  assert.equal(manifest.minimum_chrome_version, "105");
  assert.equal("host_permissions" in manifest, false);
  assert.equal("optional_host_permissions" in manifest, false);
  assert.equal("content_scripts" in manifest, false);
  assert.equal("externally_connectable" in manifest, false);
  assert.equal("key" in manifest, false);
});

test("shared version-one fixtures match the extension request schema", async () => {
  const listRequest = JSON.parse(
    await readFile(new URL("../../Fixtures/ChromeNativeMessaging/list-request-v1.json", import.meta.url)),
  );
  const activationRequest = JSON.parse(
    await readFile(new URL("../../Fixtures/ChromeNativeMessaging/activate-request-v1.json", import.meta.url)),
  );
  assert.equal(validateRequest(listRequest).ok, true);
  assert.equal(validateRequest(activationRequest).ok, true);
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
    version: 1,
    requestID: requestIDs.list,
    status: "success",
    tabs: [{title: "a".repeat(65536)}],
  };
  assert.deepEqual(boundedNativeResponse(oversized, requestIDs.list), {
    version: 1,
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
      version: 1,
      requestID: requestIDs.list,
      operation: "listTabs",
      maximumTabCount: 51,
    }).failureCode,
    "malformedRequest",
  );
  assert.equal(
    validateRequest({
      version: 1,
      requestID: requestIDs.activate,
      operation: "activateTab",
      target: {tabID: "7"},
    }).failureCode,
    "invalidTarget",
  );
  assert.equal(
    validateRequest({
      version: 1,
      requestID: requestIDs.active,
      operation: "getActiveTab",
      maximumTabCount: 1,
    }).failureCode,
    "malformedRequest",
  );
  assert.equal(
    validateRequest({
      version: 1,
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
      version: 1,
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
    version: 1,
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
    version: 1,
    requestID: requestIDs.list,
    operation: "listTabs",
    maximumTabCount: 1,
  });

  assert.equal(response.status, "success");
  assert.equal(response.tabs.length, 1);
  assert.equal(response.tabs[0].title, "One");
  assert.equal(response.excludedTabCount, 3);
});

test("activation revalidates fingerprint and invokes each mutation exactly once", async () => {
  const now = 1000;
  const current = tab();
  const fingerprint = await fingerprintForTab(current);
  const stub = chromeStub([current]);
  const handle = createRequestHandler(stub.api, () => now);
  const request = {
    version: 1,
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
    version: 1,
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
    version: 1,
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
    version: 1,
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
