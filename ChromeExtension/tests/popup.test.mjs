import assert from "node:assert/strict";
import test from "node:test";

const {
  YOUTUBE_ORIGIN_PATTERN,
  hasYouTubeAccess,
  removeYouTubeAccess,
  requestYouTubeAccess,
} = await import("../popup.js");

function permissionsStub({granted = false, requestResult = true} = {}) {
  const calls = [];
  return {
    calls,
    api: {
      permissions: {
        contains: async (value) => {
          calls.push(["contains", value]);
          return granted;
        },
        request: async (value) => {
          calls.push(["request", value]);
          return requestResult;
        },
        remove: async (value) => {
          calls.push(["remove", value]);
          return true;
        },
      },
    },
  };
}

test("permission helpers request only the exact optional YouTube origin", async () => {
  const stub = permissionsStub({granted: true});
  assert.equal(YOUTUBE_ORIGIN_PATTERN, "https://www.youtube.com/*");
  assert.equal(await hasYouTubeAccess(stub.api), true);
  assert.equal(await requestYouTubeAccess(stub.api), true);
  assert.equal(await removeYouTubeAccess(stub.api), true);
  assert.deepEqual(stub.calls, [
    ["contains", {origins: [YOUTUBE_ORIGIN_PATTERN]}],
    ["request", {origins: [YOUTUBE_ORIGIN_PATTERN]}],
    ["remove", {origins: [YOUTUBE_ORIGIN_PATTERN]}],
  ]);
});

test("permission denial is returned without broadening the request", async () => {
  const stub = permissionsStub({requestResult: false});
  assert.equal(await requestYouTubeAccess(stub.api), false);
  assert.deepEqual(stub.calls, [
    ["request", {origins: [YOUTUBE_ORIGIN_PATTERN]}],
  ]);
});
