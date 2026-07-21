export const PROTOCOL_VERSION = 2;
export const MAXIMUM_TAB_COUNT = 50;
export const MAXIMUM_OBSERVED_TAB_COUNT = 500;
export const MAXIMUM_TITLE_UTF8_BYTES = 2048;
export const MAXIMUM_URL_UTF8_BYTES = 2048;
export const MAXIMUM_SNAPSHOT_AGE_MILLISECONDS = 5000;
export const MAXIMUM_FUTURE_CLOCK_SKEW_MILLISECONDS = 1000;
export const MAXIMUM_REMEMBERED_REQUEST_IDS = 128;
export const MAXIMUM_MESSAGE_UTF8_BYTES = 65536;
export const MAXIMUM_YOUTUBE_FEED_ITEM_COUNT = 20;
export const MAXIMUM_YOUTUBE_EXTRACTED_ITEM_COUNT = 60;
export const MAXIMUM_YOUTUBE_TITLE_UTF8_BYTES = 512;
export const MAXIMUM_YOUTUBE_CHANNEL_UTF8_BYTES = 256;
export const YOUTUBE_FEED_LIFETIME_MILLISECONDS = 90000;
export const YOUTUBE_ORIGIN_PATTERN = "https://www.youtube.com/*";

const ALLOWED_SCHEMES = new Set([
  "about:",
  "chrome:",
  "chrome-extension:",
  "http:",
  "https:",
]);
const OPERATIONS = new Set([
  "activateTab",
  "cancel",
  "getActiveTab",
  "getYouTubeFeed",
  "listTabs",
  "openYouTubeVideo",
]);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FINGERPRINT_PATTERN = /^[0-9a-f]{64}$/;
const VIDEO_ID_PATTERN = /^[A-Za-z0-9_-]{11}$/;

function utf8ByteCount(value) {
  return new TextEncoder().encode(value).byteLength;
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function validateRequest(value) {
  if (!isPlainObject(value) || value.version !== PROTOCOL_VERSION) {
    return {ok: false, failureCode: "unsupportedVersion"};
  }
  if (!UUID_PATTERN.test(value.requestID ?? "") || !OPERATIONS.has(value.operation)) {
    return {ok: false, failureCode: "malformedRequest"};
  }

  if (value.operation === "listTabs") {
    if (
      !Number.isInteger(value.maximumTabCount)
      || value.maximumTabCount < 1
      || value.maximumTabCount > MAXIMUM_TAB_COUNT
      || value.target !== undefined
      || value.youTubeTarget !== undefined
      || value.cancellationRequestID !== undefined
    ) {
      return {ok: false, failureCode: "malformedRequest"};
    }
  } else if (value.operation === "activateTab") {
    if (
      !validateActivationTarget(value.target)
      || value.maximumTabCount !== undefined
      || value.youTubeTarget !== undefined
      || value.cancellationRequestID !== undefined
    ) {
      return {ok: false, failureCode: "invalidTarget"};
    }
  } else if (value.operation === "cancel") {
    if (
      !UUID_PATTERN.test(value.cancellationRequestID ?? "")
      || value.maximumTabCount !== undefined
      || value.target !== undefined
      || value.youTubeTarget !== undefined
    ) {
      return {ok: false, failureCode: "malformedRequest"};
    }
  } else if (value.operation === "openYouTubeVideo") {
    if (
      !validateYouTubeOpenTarget(value.youTubeTarget)
      || value.maximumTabCount !== undefined
      || value.target !== undefined
      || value.cancellationRequestID !== undefined
    ) {
      return {ok: false, failureCode: "invalidTarget"};
    }
  } else if (
    value.maximumTabCount !== undefined
    || value.target !== undefined
    || value.youTubeTarget !== undefined
    || value.cancellationRequestID !== undefined
  ) {
    return {ok: false, failureCode: "malformedRequest"};
  }

  return {ok: true, request: value};
}

export function validateYouTubeOpenTarget(value) {
  return (
    isPlainObject(value)
    && Number.isInteger(value.sourceTabID)
    && value.sourceTabID >= 0
    && Number.isInteger(value.sourceWindowID)
    && value.sourceWindowID >= 0
    && validatedYouTubeFeedPageURL(value.sourceURL) !== null
    && FINGERPRINT_PATTERN.test(value.sourceFingerprint?.value ?? "")
    && FINGERPRINT_PATTERN.test(value.feedObservationID?.value ?? "")
    && Number.isSafeInteger(value.capturedAtMilliseconds)
    && value.capturedAtMilliseconds > 0
    && Number.isSafeInteger(value.expiresAtMilliseconds)
    && value.expiresAtMilliseconds > value.capturedAtMilliseconds
    && value.expiresAtMilliseconds - value.capturedAtMilliseconds
      <= YOUTUBE_FEED_LIFETIME_MILLISECONDS
    && Number.isInteger(value.position)
    && value.position >= 1
    && value.position <= MAXIMUM_YOUTUBE_FEED_ITEM_COUNT
    && VIDEO_ID_PATTERN.test(value.videoID?.value ?? "")
    && FINGERPRINT_PATTERN.test(value.itemObservationID?.value ?? "")
  );
}

export function validateActivationTarget(value) {
  return (
    isPlainObject(value)
    && Number.isInteger(value.tabID)
    && value.tabID >= 0
    && Number.isInteger(value.windowID)
    && value.windowID >= 0
    && FINGERPRINT_PATTERN.test(value.fingerprint?.value ?? "")
    && Number.isSafeInteger(value.capturedAtMilliseconds)
    && value.capturedAtMilliseconds > 0
  );
}

export function validatedTabURL(value) {
  if (typeof value !== "string" || value.length === 0 || utf8ByteCount(value) > MAXIMUM_URL_UTF8_BYTES) {
    return null;
  }
  try {
    const url = new URL(value);
    if (!ALLOWED_SCHEMES.has(url.protocol) || url.username !== "" || url.password !== "") {
      return null;
    }
    if (url.protocol !== "about:" && url.hostname === "") {
      return null;
    }
    return url.href;
  } catch {
    return null;
  }
}

function validatedTitle(value) {
  if (
    typeof value !== "string"
    || value.trim().length === 0
    || utf8ByteCount(value.trim()) > MAXIMUM_TITLE_UTF8_BYTES
    || /[\u0000-\u001f\u007f]/u.test(value)
  ) {
    return null;
  }
  return value.trim();
}

function validatedBoundedText(value, maximumUTF8Bytes) {
  if (
    typeof value !== "string"
    || value.trim().length === 0
    || utf8ByteCount(value.trim()) > maximumUTF8Bytes
    || /[\u0000-\u001f\u007f]/u.test(value)
  ) {
    return null;
  }
  return value.trim().replace(/\s+/gu, " ");
}

export function validatedYouTubeFeedPageURL(value) {
  if (
    typeof value !== "string"
    || value.length === 0
    || utf8ByteCount(value) > MAXIMUM_URL_UTF8_BYTES
  ) {
    return null;
  }
  try {
    const url = new URL(value);
    if (
      url.protocol !== "https:"
      || url.hostname !== "www.youtube.com"
      || url.port !== ""
      || url.username !== ""
      || url.password !== ""
      || (url.pathname !== "/" && url.pathname !== "")
      || url.hash !== ""
    ) {
      return null;
    }
    return url.href;
  } catch {
    return null;
  }
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

async function feedObservationIDFor(sourceFingerprint, capturedAtMilliseconds, feed) {
  return sha256Hex(
    JSON.stringify([
      sourceFingerprint,
      capturedAtMilliseconds,
      feed.observationWasTruncated,
      feed.items.map((item) => item.observationID),
    ]),
  );
}

export async function fingerprintForTab(tab) {
  const canonical = JSON.stringify([tab.id, tab.windowId, tab.index, tab.title, tab.url]);
  return sha256Hex(canonical);
}

export async function canonicalYouTubeFeedFromExtraction(value) {
  if (
    !isPlainObject(value)
    || !Array.isArray(value.items)
    || value.items.length > MAXIMUM_YOUTUBE_FEED_ITEM_COUNT
    || !Number.isInteger(value.eligibleItemCount)
    || value.eligibleItemCount < 0
    || value.eligibleItemCount > MAXIMUM_YOUTUBE_EXTRACTED_ITEM_COUNT
    || !Number.isInteger(value.incompleteItemCount)
    || value.incompleteItemCount < 0
    || value.incompleteItemCount > value.eligibleItemCount
    || typeof value.candidateScanWasTruncated !== "boolean"
  ) {
    return null;
  }

  const items = [];
  const videoIDs = new Set();
  const observationIDs = new Set();
  for (const candidate of value.items) {
    if (!isPlainObject(candidate) || !VIDEO_ID_PATTERN.test(candidate.videoID ?? "")) {
      return null;
    }
    const title = validatedBoundedText(candidate.title, MAXIMUM_YOUTUBE_TITLE_UTF8_BYTES);
    const channel = validatedBoundedText(candidate.channel, MAXIMUM_YOUTUBE_CHANNEL_UTF8_BYTES);
    if (title === null || channel === null || videoIDs.has(candidate.videoID)) {
      return null;
    }
    videoIDs.add(candidate.videoID);
    const observationID = await sha256Hex(
      JSON.stringify([candidate.videoID, title, channel]),
    );
    if (observationIDs.has(observationID)) return null;
    observationIDs.add(observationID);
    items.push({
      position: items.length + 1,
      videoID: candidate.videoID,
      title,
      channel,
      observationID,
    });
  }

  if (items.length === 0 || value.eligibleItemCount < items.length) return null;
  return {
    items,
    observationWasTruncated:
      value.candidateScanWasTruncated
      || value.incompleteItemCount > 0
      || value.eligibleItemCount > items.length,
  };
}

export async function snapshotYouTubeFeed(tab, extracted, capturedAtMilliseconds) {
  const canonicalTab = validatedCanonicalTab(tab);
  const sourceURL = validatedYouTubeFeedPageURL(canonicalTab?.url);
  const feed = await canonicalYouTubeFeedFromExtraction(extracted);
  if (
    canonicalTab === null
    || canonicalTab.active !== true
    || sourceURL === null
    || feed === null
    || !Number.isSafeInteger(capturedAtMilliseconds)
    || capturedAtMilliseconds <= 0
  ) {
    return null;
  }

  const sourceFingerprint = await fingerprintForTab(canonicalTab);
  const feedObservationID = await feedObservationIDFor(
    sourceFingerprint,
    capturedAtMilliseconds,
    feed,
  );
  return {
    sourceTabID: canonicalTab.id,
    sourceWindowID: canonicalTab.windowId,
    sourceURL,
    sourceFingerprint,
    feedObservationID,
    capturedAtMilliseconds,
    expiresAtMilliseconds: capturedAtMilliseconds + YOUTUBE_FEED_LIFETIME_MILLISECONDS,
    observationWasTruncated: feed.observationWasTruncated,
    items: feed.items,
  };
}

function validatedCanonicalTab(tab) {
  if (
    !isPlainObject(tab)
    || tab.incognito === true
    || !Number.isInteger(tab.id)
    || tab.id < 0
    || !Number.isInteger(tab.windowId)
    || tab.windowId < 0
    || !Number.isInteger(tab.index)
    || tab.index < 0
  ) {
    return null;
  }
  const title = validatedTitle(tab.title);
  const url = validatedTabURL(tab.url);
  if (title === null || url === null) {
    return null;
  }
  return {...tab, title, url};
}

async function snapshotCanonicalTab(canonicalTab, capturedAtMilliseconds) {
  return {
    tabID: canonicalTab.id,
    windowID: canonicalTab.windowId,
    index: canonicalTab.index,
    active: canonicalTab.active === true,
    title: canonicalTab.title,
    url: canonicalTab.url,
    fingerprint: await fingerprintForTab(canonicalTab),
    capturedAtMilliseconds,
  };
}

export async function snapshotTab(tab, capturedAtMilliseconds) {
  const canonicalTab = validatedCanonicalTab(tab);
  return canonicalTab === null
    ? null
    : snapshotCanonicalTab(canonicalTab, capturedAtMilliseconds);
}

export function successResponse(requestID, fields = {}) {
  return {
    version: PROTOCOL_VERSION,
    requestID,
    status: "success",
    ...fields,
  };
}

export function failureResponse(requestID, failureCode) {
  return {
    version: PROTOCOL_VERSION,
    requestID: UUID_PATTERN.test(requestID ?? "")
      ? requestID
      : "00000000-0000-4000-8000-000000000000",
    status: "failure",
    failureCode,
  };
}

export function boundedNativeResponse(response, requestID) {
  try {
    if (utf8ByteCount(JSON.stringify(response)) <= MAXIMUM_MESSAGE_UTF8_BYTES) {
      return response;
    }
  } catch {
    // Fall through to a fixed typed failure without echoing the payload.
  }
  return failureResponse(requestID, "messageTooLarge");
}

export function createRequestHandler(chromeAPI, nowMilliseconds = () => Date.now()) {
  const inFlightRequestIDs = new Set();
  const completedRequestIDs = new Set();
  const completedRequestOrder = [];
  const canceledRequestIDs = new Set();
  const canceledRequestOrder = [];

  function rememberCompleted(requestID) {
    completedRequestIDs.add(requestID);
    completedRequestOrder.push(requestID);
    while (completedRequestOrder.length > MAXIMUM_REMEMBERED_REQUEST_IDS) {
      completedRequestIDs.delete(completedRequestOrder.shift());
    }
  }

  async function listTabs(maximumTabCount) {
    const allTabs = await chromeAPI.tabs.query({});
    if (!Array.isArray(allTabs)) {
      throw new Error("tabs.query returned invalid data");
    }
    const observedTabs = allTabs.slice(0, MAXIMUM_OBSERVED_TAB_COUNT);
    const snapshots = [];
    let excludedTabCount = Math.max(0, allTabs.length - observedTabs.length);
    let observationWasTruncated = allTabs.length > observedTabs.length;
    const capturedAtMilliseconds = nowMilliseconds();

    for (const tab of observedTabs) {
      const canonicalTab = validatedCanonicalTab(tab);
      if (canonicalTab === null) {
        excludedTabCount += 1;
        continue;
      }
      if (snapshots.length >= maximumTabCount) {
        excludedTabCount += 1;
        observationWasTruncated = true;
        continue;
      }
      snapshots.push(await snapshotCanonicalTab(canonicalTab, capturedAtMilliseconds));
    }
    return {tabs: snapshots, excludedTabCount, observationWasTruncated};
  }

  async function hasYouTubePermission() {
    return chromeAPI.permissions.contains({origins: [YOUTUBE_ORIGIN_PATTERN]});
  }

  async function extractYouTubeFeed(tabID) {
    const results = await chromeAPI.scripting.executeScript({
      target: {tabId: tabID, frameIds: [0]},
      files: ["youtube_feed_extractor.js"],
      world: "ISOLATED",
    });
    if (
      !Array.isArray(results)
      || results.length !== 1
      || results[0]?.frameId !== 0
      || !("result" in results[0])
    ) {
      return null;
    }
    return results[0].result;
  }

  async function activeYouTubeFeedTab() {
    const tabs = await chromeAPI.tabs.query({active: true, lastFocusedWindow: true});
    if (!Array.isArray(tabs) || tabs.length === 0) {
      return {failureCode: "noActiveTab"};
    }
    const tab = tabs[0];
    if (tab?.incognito === true) return {failureCode: "incognitoExcluded"};
    if (validatedYouTubeFeedPageURL(tab?.url) === null) {
      return {failureCode: "unsupportedYouTubePage"};
    }
    return {tab};
  }

  async function readYouTubeFeed(requestID) {
    if (!await hasYouTubePermission()) {
      return failureResponse(requestID, "youTubePermissionRequired");
    }
    const active = await activeYouTubeFeedTab();
    if (active.failureCode !== undefined) {
      return failureResponse(requestID, active.failureCode);
    }
    const initialFingerprint = await fingerprintForTab(active.tab);

    let extracted;
    try {
      extracted = await extractYouTubeFeed(active.tab.id);
    } catch {
      if (!await hasYouTubePermission()) {
        return failureResponse(requestID, "youTubePermissionRequired");
      }
      return failureResponse(requestID, "youTubeFeedUnavailable");
    }
    let revalidatedTab;
    try {
      revalidatedTab = await chromeAPI.tabs.get(active.tab.id);
    } catch {
      return failureResponse(requestID, "youTubeFeedUnavailable");
    }
    const revalidatedActive = await activeYouTubeFeedTab();
    if (!await hasYouTubePermission()) {
      return failureResponse(requestID, "youTubePermissionRequired");
    }
    if (
      revalidatedActive.tab?.id !== active.tab.id
      || revalidatedTab.active !== true
      || revalidatedTab.windowId !== active.tab.windowId
      || validatedYouTubeFeedPageURL(revalidatedTab.url) === null
      || await fingerprintForTab(revalidatedTab) !== initialFingerprint
    ) {
      return failureResponse(requestID, "youTubeFeedUnavailable");
    }
    const snapshot = await snapshotYouTubeFeed(
      revalidatedTab,
      extracted,
      nowMilliseconds(),
    );
    return snapshot === null
      ? failureResponse(requestID, "youTubeFeedUnavailable")
      : successResponse(requestID, {youTubeFeed: snapshot});
  }

  async function openYouTubeVideo(request) {
    const target = request.youTubeTarget;
    const initialNow = nowMilliseconds();
    if (
      initialNow < target.capturedAtMilliseconds - MAXIMUM_FUTURE_CLOCK_SKEW_MILLISECONDS
      || initialNow > target.expiresAtMilliseconds
    ) {
      return failureResponse(request.requestID, "staleYouTubeFeed");
    }
    if (!await hasYouTubePermission()) {
      return failureResponse(request.requestID, "youTubePermissionRequired");
    }
    if (canceledRequestIDs.has(request.requestID)) {
      return failureResponse(request.requestID, "canceled");
    }

    let tab;
    try {
      tab = await chromeAPI.tabs.get(target.sourceTabID);
    } catch {
      return failureResponse(request.requestID, "youTubeFeedChanged");
    }
    const active = await activeYouTubeFeedTab();
    const currentURL = validatedYouTubeFeedPageURL(tab?.url);
    const currentFingerprint = tab === undefined ? null : await fingerprintForTab(tab);
    if (
      active.tab?.id !== target.sourceTabID
      || tab?.windowId !== target.sourceWindowID
      || tab?.active !== true
      || currentURL === null
      || currentURL !== validatedYouTubeFeedPageURL(target.sourceURL)
      || currentFingerprint !== target.sourceFingerprint.value
    ) {
      return failureResponse(request.requestID, "youTubeFeedChanged");
    }

    let extracted;
    try {
      extracted = await extractYouTubeFeed(target.sourceTabID);
    } catch {
      if (!await hasYouTubePermission()) {
        return failureResponse(request.requestID, "youTubePermissionRequired");
      }
      return failureResponse(request.requestID, "youTubeFeedChanged");
    }
    const currentFeed = await canonicalYouTubeFeedFromExtraction(extracted);
    const currentFeedObservationID = currentFeed === null
      ? null
      : await feedObservationIDFor(
        target.sourceFingerprint.value,
        target.capturedAtMilliseconds,
        currentFeed,
      );
    const selectedItem = currentFeed?.items.find(
      (item) => item.position === target.position
        && item.videoID === target.videoID.value
        && item.observationID === target.itemObservationID.value,
    );
    if (
      currentFeedObservationID !== target.feedObservationID.value
      || selectedItem === undefined
    ) {
      return failureResponse(request.requestID, "youTubeFeedChanged");
    }

    let revalidatedTab;
    try {
      revalidatedTab = await chromeAPI.tabs.get(target.sourceTabID);
    } catch {
      return failureResponse(request.requestID, "youTubeFeedChanged");
    }
    const revalidatedFingerprint = await fingerprintForTab(revalidatedTab);
    const [revalidatedActive, permissionStillGranted] = await Promise.all([
      activeYouTubeFeedTab(),
      hasYouTubePermission(),
    ]);
    const revalidatedNow = nowMilliseconds();
    if (!permissionStillGranted) {
      return failureResponse(request.requestID, "youTubePermissionRequired");
    }
    if (
      revalidatedActive.tab?.id !== target.sourceTabID
      || revalidatedActive.tab?.windowId !== target.sourceWindowID
      || revalidatedTab.active !== true
      || revalidatedTab.windowId !== target.sourceWindowID
      || validatedYouTubeFeedPageURL(revalidatedTab.url) !== currentURL
      || revalidatedFingerprint !== target.sourceFingerprint.value
      || revalidatedNow < target.capturedAtMilliseconds - MAXIMUM_FUTURE_CLOCK_SKEW_MILLISECONDS
      || revalidatedNow > target.expiresAtMilliseconds
    ) {
      return failureResponse(request.requestID, "youTubeFeedChanged");
    }
    if (canceledRequestIDs.has(request.requestID)) {
      return failureResponse(request.requestID, "canceled");
    }

    const destination = new URL("https://www.youtube.com/watch");
    destination.searchParams.set("v", target.videoID.value);
    try {
      // Exactly one navigation call. The page never supplies this URL and a
      // failed acknowledgement is never retried.
      await chromeAPI.tabs.update(target.sourceTabID, {url: destination.href});
      return successResponse(request.requestID);
    } catch {
      return failureResponse(request.requestID, "navigationOutcomeUnknown");
    }
  }

  async function handleValidated(request) {
    if (request.operation === "cancel") {
      if (!canceledRequestIDs.has(request.cancellationRequestID)) {
        canceledRequestIDs.add(request.cancellationRequestID);
        canceledRequestOrder.push(request.cancellationRequestID);
      }
      while (canceledRequestOrder.length > MAXIMUM_REMEMBERED_REQUEST_IDS) {
        canceledRequestIDs.delete(canceledRequestOrder.shift());
      }
      return successResponse(request.requestID);
    }

    if (request.operation === "getActiveTab") {
      const tabs = await chromeAPI.tabs.query({active: true, lastFocusedWindow: true});
      const snapshot = Array.isArray(tabs) && tabs.length > 0
        ? await snapshotTab(tabs[0], nowMilliseconds())
        : null;
      if (snapshot === null) {
        const excluded = Array.isArray(tabs) && tabs[0]?.incognito === true
          ? "incognitoExcluded"
          : Array.isArray(tabs) && tabs.length > 0
            ? "excludedScheme"
            : "noActiveTab";
        return failureResponse(request.requestID, excluded);
      }
      return successResponse(request.requestID, {tab: snapshot});
    }

    if (request.operation === "listTabs") {
      const result = await listTabs(request.maximumTabCount);
      return successResponse(request.requestID, result);
    }

    if (request.operation === "getYouTubeFeed") {
      return readYouTubeFeed(request.requestID);
    }

    if (request.operation === "openYouTubeVideo") {
      return openYouTubeVideo(request);
    }

    const target = request.target;
    const age = nowMilliseconds() - target.capturedAtMilliseconds;
    if (
      age < -MAXIMUM_FUTURE_CLOCK_SKEW_MILLISECONDS
      || age > MAXIMUM_SNAPSHOT_AGE_MILLISECONDS
    ) {
      return failureResponse(request.requestID, "staleTab");
    }
    if (canceledRequestIDs.has(request.requestID)) {
      return failureResponse(request.requestID, "canceled");
    }

    let tab;
    try {
      tab = await chromeAPI.tabs.get(target.tabID);
    } catch {
      return failureResponse(request.requestID, "targetNotFound");
    }
    const currentSnapshot = await snapshotTab(tab, nowMilliseconds());
    if (
      currentSnapshot === null
      || currentSnapshot.windowID !== target.windowID
      || currentSnapshot.fingerprint !== target.fingerprint.value
    ) {
      return failureResponse(request.requestID, "staleTab");
    }
    const revalidatedAge = nowMilliseconds() - target.capturedAtMilliseconds;
    if (
      revalidatedAge < -MAXIMUM_FUTURE_CLOCK_SKEW_MILLISECONDS
      || revalidatedAge > MAXIMUM_SNAPSHOT_AGE_MILLISECONDS
    ) {
      return failureResponse(request.requestID, "staleTab");
    }
    if (canceledRequestIDs.has(request.requestID)) {
      return failureResponse(request.requestID, "canceled");
    }

    // There is deliberately one call to each mutation API and no retry. If the
    // native connection drops after either call, Topher reports an unknown
    // outcome instead of replaying the request.
    try {
      await chromeAPI.tabs.update(target.tabID, {active: true});
      await chromeAPI.windows.update(target.windowID, {focused: true});
      return successResponse(request.requestID);
    } catch {
      return failureResponse(request.requestID, "activationOutcomeUnknown");
    }
  }

  return async function handleRequest(value) {
    const validation = validateRequest(value);
    if (!validation.ok) {
      return failureResponse(value?.requestID, validation.failureCode);
    }
    const request = validation.request;
    if (inFlightRequestIDs.has(request.requestID) || completedRequestIDs.has(request.requestID)) {
      return failureResponse(request.requestID, "duplicateRequest");
    }

    inFlightRequestIDs.add(request.requestID);
    try {
      return await handleValidated(request);
    } catch {
      return failureResponse(request.requestID, "browserFailure");
    } finally {
      inFlightRequestIDs.delete(request.requestID);
      rememberCompleted(request.requestID);
      canceledRequestIDs.delete(request.requestID);
    }
  };
}
