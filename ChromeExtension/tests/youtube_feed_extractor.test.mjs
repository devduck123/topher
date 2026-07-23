import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import {TextEncoder} from "node:util";
import vm from "node:vm";

const source = await readFile(
  new URL("../youtube_feed_extractor.js", import.meta.url),
  "utf8",
);

function fakeCard(record) {
  const titleAnchor = {
    textContent: record.title,
    getAttribute: (name) => name === "href"
      ? record.href
      : name === "title"
        ? record.title
        : null,
  };
  const channel = {textContent: record.channel};
  return {
    hidden: record.hidden === true,
    closest: () => null,
    getBoundingClientRect: () => record.rect,
    querySelector: (selector) => {
      if (
        (record.titleMarkup === "lockup" && selector === "h3 a[href^='/watch']")
        || (record.titleMarkup !== "lockup" && selector === "a#video-title-link[href]")
      ) {
        return titleAnchor;
      }
      if (
        record.channelMarkup === "attributed-handle"
        && selector === "yt-content-metadata-view-model a[href^='/@']"
      ) {
        return channel;
      }
      if (record.channelMarkup !== "missing" && record.channelMarkup !== "attributed-handle"
        && selector === "ytd-channel-name a") {
        return channel;
      }
      return null;
    },
  };
}

function loadExtractor() {
  const context = {TextEncoder, URL};
  vm.runInNewContext(source, context, {filename: "youtube_feed_extractor.js"});
  return context.TopherYouTubeFeedExtractor;
}

test("packaged extractor returns only relevant strict watch cards from a sanitized fixture", async () => {
  const fixture = JSON.parse(
    await readFile(new URL("./fixtures/youtube-home.json", import.meta.url), "utf8"),
  );
  const document = {
    querySelectorAll: () => fixture.cards.map(fakeCard),
  };
  const result = loadExtractor().extract(document, {innerHeight: fixture.viewportHeight});

  assert.deepEqual(JSON.parse(JSON.stringify(result.items)), [
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
  ]);
  assert.equal(result.eligibleItemCount, 3);
  assert.equal(result.incompleteTitleItemCount, 0);
  assert.equal(result.incompletePresentationItemCount, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(result.selectionCandidates)), [
    {videoID: "abcDEF123_-", title: "Local-first Mac assistants"},
    {videoID: "ZYX987abc_-", title: "Swift concurrency, carefully"},
    {videoID: "QWE456rty_-", title: "Still loading its channel"},
  ]);
  assert.equal(result.candidateScanWasTruncated, false);
});

test("packaged extractor keeps current lockup and legacy channel seams isolated", () => {
  const records = [
    {
      href: "/watch?v=abcDEF123_-",
      title: "Current structure",
      channel: "Current Channel",
      titleMarkup: "lockup",
      channelMarkup: "attributed-handle",
      rect: {top: 20, bottom: 220, width: 320, height: 200},
    },
    {
      href: "/watch?v=ZYX987abc_-",
      title: "Legacy structure",
      channel: "Legacy Channel",
      titleMarkup: "legacy",
      channelMarkup: "legacy",
      rect: {top: 240, bottom: 440, width: 320, height: 200},
    },
  ];

  const result = loadExtractor().extract(
    {querySelectorAll: () => records.map(fakeCard)},
    {innerHeight: 800},
  );

  assert.deepEqual(JSON.parse(JSON.stringify(result.items.map((item) => item.title))), [
    "Current structure",
    "Legacy structure",
  ]);
});

test("packaged extractor bounds cards and deduplicates video IDs", () => {
  const cards = Array.from({length: 65}, (_, index) => fakeCard({
    href: `/watch?v=${String(index).padStart(11, "0")}`,
    title: `Recommendation ${index}`,
    channel: "Fixture Channel",
    rect: {top: 20, bottom: 220, width: 320, height: 200},
  }));
  cards[1] = cards[0];
  const result = loadExtractor().extract(
    {querySelectorAll: () => cards},
    {innerHeight: 800},
  );

  assert.equal(result.items.length, 20);
  assert.equal(result.eligibleItemCount, 59);
  assert.equal(result.candidateScanWasTruncated, true);
  assert.equal(new Set(result.items.map((item) => item.videoID)).size, 20);
});

test("packaged extractor rejects credentialed and ambiguous watch links", () => {
  const cards = [
    fakeCard({
      href: "https://name@www.youtube.com/watch?v=abcDEF123_-",
      title: "Credentialed",
      channel: "Fixture Channel",
      rect: {top: 20, bottom: 220, width: 320, height: 200},
    }),
    fakeCard({
      href: "/watch?v=abcDEF123_-&v=ZYX987abc_-",
      title: "Ambiguous",
      channel: "Fixture Channel",
      rect: {top: 240, bottom: 440, width: 320, height: 200},
    }),
  ];
  const result = loadExtractor().extract(
    {querySelectorAll: () => cards},
    {innerHeight: 800},
  );

  assert.deepEqual(JSON.parse(JSON.stringify(result.items)), []);
  assert.equal(result.eligibleItemCount, 0);
});

test("packaged extractor rejects oversized DOM strings before returning them", () => {
  const cards = [
    fakeCard({
      href: "/watch?v=abcDEF123_-",
      title: "a".repeat(513),
      channel: "Fixture Channel",
      rect: {top: 20, bottom: 220, width: 320, height: 200},
    }),
    fakeCard({
      href: "/watch?v=ZYX987abc_-",
      title: "Bounded title",
      channel: "b".repeat(257),
      rect: {top: 240, bottom: 440, width: 320, height: 200},
    }),
  ];
  const result = loadExtractor().extract(
    {querySelectorAll: () => cards},
    {innerHeight: 800},
  );

  assert.deepEqual(JSON.parse(JSON.stringify(result.items)), []);
  assert.equal(result.eligibleItemCount, 2);
  assert.equal(result.incompleteTitleItemCount, 1);
  assert.equal(result.incompletePresentationItemCount, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(result.selectionCandidates)), [
    {videoID: "ZYX987abc_-", title: "Bounded title"},
  ]);
});
