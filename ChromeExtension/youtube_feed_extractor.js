(() => {
  "use strict";

  const MAXIMUM_ITEM_COUNT = 20;
  const MAXIMUM_SCANNED_CARD_COUNT = 60;
  const MAXIMUM_TITLE_UTF8_BYTES = 512;
  const MAXIMUM_CHANNEL_UTF8_BYTES = 256;
  const CARD_SELECTOR = "ytd-rich-item-renderer, ytd-video-renderer";
  const TITLE_SELECTORS = [
    "a#video-title-link[href]",
    "a#video-title[href]",
    "h3 a[href^='/watch']",
  ];
  const CHANNEL_SELECTORS = [
    "ytd-channel-name a",
    "#channel-name a",
    "#channel-name",
  ];
  const VIDEO_ID_PATTERN = /^[A-Za-z0-9_-]{11}$/;
  const UTF8_ENCODER = new TextEncoder();

  function boundedNormalizedText(value, maximumUTF8Bytes) {
    if (typeof value !== "string") return "";
    // Reject large raw strings before normalization so page-authored whitespace
    // cannot force an unbounded cross-context result or normalization pass.
    if (value.length > maximumUTF8Bytes) return "";
    const normalized = value.replace(/\s+/gu, " ").trim();
    if (UTF8_ENCODER.encode(normalized).byteLength > maximumUTF8Bytes) return "";
    return normalized;
  }

  function firstMatch(root, selectors) {
    for (const selector of selectors) {
      const match = root.querySelector(selector);
      if (match !== null) return match;
    }
    return null;
  }

  function videoIDFromAnchor(anchor) {
    const rawHref = anchor?.getAttribute?.("href");
    if (typeof rawHref !== "string") return null;
    try {
      const url = new URL(rawHref, "https://www.youtube.com/");
      if (
        url.protocol !== "https:"
        || url.hostname !== "www.youtube.com"
        || url.port !== ""
        || url.username !== ""
        || url.password !== ""
        || url.pathname !== "/watch"
        || url.searchParams.getAll("v").length !== 1
      ) {
        return null;
      }
      const videoID = url.searchParams.get("v");
      return VIDEO_ID_PATTERN.test(videoID ?? "") ? videoID : null;
    } catch {
      return null;
    }
  }

  function isRelevantCard(card, viewportHeight) {
    if (
      card.hidden === true
      || (typeof card.closest === "function" && card.closest("[hidden]") !== null)
    ) {
      return false;
    }
    if (typeof card.getBoundingClientRect !== "function") return true;
    const rect = card.getBoundingClientRect();
    if (!Number.isFinite(rect?.top) || !Number.isFinite(rect?.bottom)) return false;
    if (rect.width <= 0 || rect.height <= 0) return false;
    if (!Number.isFinite(viewportHeight) || viewportHeight <= 0) return true;
    return rect.bottom >= -viewportHeight && rect.top <= viewportHeight * 3;
  }

  function extract(documentLike, environment = globalThis) {
    const allCards = documentLike.querySelectorAll(CARD_SELECTOR);
    const scannedCardCount = Math.min(allCards.length, MAXIMUM_SCANNED_CARD_COUNT);
    const items = [];
    const seenVideoIDs = new Set();
    let eligibleItemCount = 0;
    let incompleteItemCount = 0;
    const viewportHeight = Number(environment.innerHeight);

    for (let index = 0; index < scannedCardCount; index += 1) {
      const card = allCards[index];
      if (!isRelevantCard(card, viewportHeight)) continue;
      const titleAnchor = firstMatch(card, TITLE_SELECTORS);
      const videoID = videoIDFromAnchor(titleAnchor);
      if (videoID === null) continue;
      eligibleItemCount += 1;

      const title = boundedNormalizedText(
        titleAnchor.getAttribute?.("title") || titleAnchor.textContent,
        MAXIMUM_TITLE_UTF8_BYTES,
      );
      const channelNode = firstMatch(card, CHANNEL_SELECTORS);
      const channel = boundedNormalizedText(
        channelNode?.textContent,
        MAXIMUM_CHANNEL_UTF8_BYTES,
      );
      if (title.length === 0 || channel.length === 0) {
        incompleteItemCount += 1;
        continue;
      }
      if (seenVideoIDs.has(videoID)) continue;
      seenVideoIDs.add(videoID);
      if (items.length < MAXIMUM_ITEM_COUNT) {
        items.push({videoID, title, channel});
      }
    }

    return {
      items,
      eligibleItemCount,
      incompleteItemCount,
      candidateScanWasTruncated: allCards.length > scannedCardCount,
    };
  }

  globalThis.TopherYouTubeFeedExtractor = Object.freeze({extract});
})();

typeof document === "undefined"
  ? null
  : globalThis.TopherYouTubeFeedExtractor.extract(document, globalThis);
