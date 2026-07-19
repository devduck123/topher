export const PROTOCOL_VERSION = 1;
export const MAXIMUM_TAB_COUNT = 50;
export const MAXIMUM_OBSERVED_TAB_COUNT = 500;
export const MAXIMUM_TITLE_UTF8_BYTES = 2048;
export const MAXIMUM_URL_UTF8_BYTES = 2048;
export const MAXIMUM_SNAPSHOT_AGE_MILLISECONDS = 5000;
export const MAXIMUM_FUTURE_CLOCK_SKEW_MILLISECONDS = 1000;
export const MAXIMUM_REMEMBERED_REQUEST_IDS = 128;
export const MAXIMUM_MESSAGE_UTF8_BYTES = 65536;

const ALLOWED_SCHEMES = new Set([
  "about:",
  "chrome:",
  "chrome-extension:",
  "http:",
  "https:",
]);
const OPERATIONS = new Set(["activateTab", "cancel", "getActiveTab", "listTabs"]);
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const FINGERPRINT_PATTERN = /^[0-9a-f]{64}$/;

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
      || value.cancellationRequestID !== undefined
    ) {
      return {ok: false, failureCode: "malformedRequest"};
    }
  } else if (value.operation === "activateTab") {
    if (
      !validateActivationTarget(value.target)
      || value.maximumTabCount !== undefined
      || value.cancellationRequestID !== undefined
    ) {
      return {ok: false, failureCode: "invalidTarget"};
    }
  } else if (value.operation === "cancel") {
    if (
      !UUID_PATTERN.test(value.cancellationRequestID ?? "")
      || value.maximumTabCount !== undefined
      || value.target !== undefined
    ) {
      return {ok: false, failureCode: "malformedRequest"};
    }
  } else if (
    value.maximumTabCount !== undefined
    || value.target !== undefined
    || value.cancellationRequestID !== undefined
  ) {
    return {ok: false, failureCode: "malformedRequest"};
  }

  return {ok: true, request: value};
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

export async function fingerprintForTab(tab) {
  const canonical = JSON.stringify([tab.id, tab.windowId, tab.index, tab.title, tab.url]);
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
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
