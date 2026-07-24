# Build 22 YouTube merge-readiness audit

- Date: 2026-07-24
- Version: 0.5.2 (22)
- Branch: `codex/youtube-feed-recovery`
- Pull request: `#8`
- Scope: product, UX, safety, privacy, performance, and release-gate review of
  the bounded YouTube Home read/open slice

## Outcome

The source is ready for review as a narrow, model-free YouTube Home capability.
The audit found no permission, protocol, privacy, exactly-once, or performance
blocker. It did find and close a bounded interaction gap: ordinary phrasings
such as “Check my YouTube feed,” “Let’s watch the third one,” “I’ll take number
seven,” “Open the YouTube video number three,” and “the one called X” now map to
the same existing typed read or exact selection commands. These additions do
not guess a target, fuzzily match a title, or broaden authority.

The result handoff now explicitly tells the user to click Topher in the menu
bar. Visible titles are limited to three lines so a hostile or unusually long
bounded title cannot dominate the 380 × 460 menu; the full bounded title remains
available to accessibility and exact matching.

The observed local failure was an artifact/setup mismatch, not proof about the
candidate source:

- `/Applications/Topher.app` is still version `0.5.0` Build `20`;
- the per-user `dev.topher.chrome_bridge` native-host manifest is absent; and
- therefore that installed app cannot complete Build 22's extension relay or
  demonstrate its setup/recovery UX.

No app, registration, Chrome extension, permission, or running process was
changed during this audit.

## Architecture and performance review

The deterministic pipeline remains appropriate for the product goal:

- feed questions resolve through a finite application-owned grammar;
- selection requires a displayed ordinal or one normalized exact title;
- speech alternatives are accepted only when they converge on one listed video;
- multi-item pronouns clarify rather than guess, while a one-item pronoun is
  unambiguous;
- the packaged isolated-world extractor scans at most 60 semantic candidates
  and returns at most 20 complete title/channel rows;
- reads perform one demand-driven extraction, and opens perform one fresh
  revalidation extraction followed by exactly one `tabs.update`;
- the app consumes the 90-second session before dispatch and never retries an
  unknown navigation outcome; and
- no model, network service, polling loop, screenshot, OCR, Accessibility page
  traversal, or persisted feed cache is on the path.

An LLM is not needed for the implemented intent. It cannot safely infer which
item “that” means in a multi-item list. A future constrained interpreter could
propose an existing typed command for measured paraphrase misses, but policy,
target binding, URL construction, and execution must remain deterministic.
Semantic requests such as “the one about baseball” remain intentionally
unsupported until a separate context and authority decision.

## Platform verification

Current official Chrome documentation was rechecked:

- [`chrome.scripting`](https://developer.chrome.com/docs/extensions/reference/api/scripting)
  requires the named API permission plus host access and supports packaged-file
  execution in the isolated world;
- [`chrome.permissions`](https://developer.chrome.com/docs/extensions/reference/api/permissions)
  requires optional access requests to occur within a user gesture and provides
  explicit state and removal APIs;
- [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
  requires an absolute host path on macOS and exact, non-wildcard
  `allowed_origins`; and
- [extension service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
  documents `connectNative` keepalive behavior and reconnection after a native
  host disconnect.

The extension remains limited to required `tabs`, `nativeMessaging`, and
`scripting`, optional `https://www.youtube.com/*`, an exact application-enforced
YouTube Home route, and `incognito: "not_allowed"`.

## Automated validation

All required and proportional gates passed from the isolated worktree:

```sh
ruby scripts/check_dependency_parity.rb
# passed; one aligned KeyboardShortcuts 3.0.1 pin

ruby scripts/check_dogfood_corpus.rb
# passed; 57 sanitized cases

ruby scripts/test_observed_query_export.rb
# passed

xcrun swift-format lint --strict -r Package.swift Sources Tests
# passed

swift test
# passed; 351 tests, 0 failures

swift test --sanitize=thread
# passed; 351 tests, 0 failures, no Thread Sanitizer report

node --test ChromeExtension/tests/*.test.mjs
# passed; 35 tests, 0 failures

ruby scripts/test_chrome_native_host.rb
# passed; 6 tests, 43 assertions, 0 failures

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-build22-audit-debug build
# BUILD SUCCEEDED

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-build22-audit-release build
# BUILD SUCCEEDED

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-build22-audit-analyze analyze
# ANALYZE SUCCEEDED

git diff --check
# passed
```

The Release artifact reports version `0.5.2` Build `22`, `LSUIElement = true`,
universal `x86_64 arm64` app and helper executables, a valid deep strict local
signature, and only the expected audio-input entitlement. Its embedded
`ChromeExtension` directory is source-identical. Targeted scans found no
credential material, broad required host access, feed persistence, or
page-derived feed values interpolated into ordinary logging.

## Remaining interactive acceptance

This audit does **not** claim a live signed-in YouTube round trip. The candidate
app was built but not installed or launched; the native host was not
registered; Chrome's unpacked extension was not loaded/reloaded; and optional
YouTube access was not granted. Before treating the feature as dogfood-proven:

1. Install and launch the exact candidate only with explicit approval.
2. In Topher Settings, run **Set Up**, load the bundled extension from
   `chrome://extensions`, and grant the optional YouTube permission from the
   extension popup.
3. Verify the disconnected, permission-denied, unsupported-page, revoked, and
   recovery states in the exact candidate.
4. On a signed-in YouTube Home tab, exercise canonical and conversational reads,
   row selection, ordinal/title selection, multi-item clarification, one-item
   pronouns, expiry, target drift, unrelated lazy loading, restart/suspension,
   and unknown post-dispatch outcomes.
5. Inspect VoiceOver order, keyboard activation, reduced motion, perceived
   latency, and Unified Logging for absence of feed titles, channels, video IDs,
   source URLs, and destinations.

Until that explicit acceptance is complete, the correct claim is “automated
merge-ready with named live acceptance remaining,” not “live behavior proven.”
