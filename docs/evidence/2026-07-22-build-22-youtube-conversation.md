# Build 22 YouTube conversation verification

- Date: 2026-07-22
- Version: 0.5.2 (22)
- Branch: `codex/youtube-feed-recovery`
- Scope: realistic model-free YouTube feed dialogue, protocol-v3 observation
  completeness and target revalidation, and truthful content-free readiness

## Outcome

Build 22 makes the narrow YouTube Home flow conversationally useful without
adding an LLM or widening browser authority:

- common feed, homepage, recommendation, list, play, watch, ordinal, number,
  exact-title, and polite variants resolve through reviewed deterministic
  grammar;
- terse numbers, ordinals, “last,” and bare exact titles are recognized only
  while one visible 90-second feed session exists, and registered commands keep
  precedence;
- “that video,” “that one,” and “it” request a number or exact title for a
  multi-item feed, open the only item in a one-item feed, and never fall through
  to generic web search when no feed exists;
- conflicting ordinal/title evidence, ambiguous titles, conflicting speech
  alternatives, stale sessions, and unsupported pages refuse rather than
  guess;
- protocol v3 separates the 20-row presentation bound from completeness of a
  bounded 60-candidate title scan, and only the displayed records cross the
  native protocol;
- open revalidation binds the active YouTube Home source and chosen video, with
  fresh uniqueness proof for title selection, while tolerating unrelated feed
  reordering, lazy loading, channel loss, and tab-title/index churn; and
- Settings distinguishes local host registration, extension connection, and
  optional YouTube access through a content-free status operation. The primary
  app creates its authenticated local relay eagerly, but tab/page acquisition
  remains demand-driven.

The existing required `scripting` permission and optional
`https://www.youtube.com/*` permission are unchanged. No origin, supported
route, extracted field, persistence boundary, arbitrary navigation, or retry
after an unknown mutation outcome was added. The installed app, native-host
registration, loaded extension, Chrome profile, and optional permission were
not changed.

## Product and safety decisions

No LLM is required for this slice. The user-visible domain is finite and the
authority-sensitive values are a short-lived numbered list, strict video IDs,
and normalized exact titles. Deterministic grammar provides predictable
latency, complete auditability, and safer ambiguity behavior than statistical
reference guessing. A future model may propose typed intent for broader
language, but it cannot infer an unidentified feed item or authorize browser
mutation.

The selected item—not the dynamic feed as a whole—is the mutation invariant.
An ordinal is bound to the video observed at that displayed position. A title
selection is bound to the unique video with that normalized title in the
complete bounded candidate scan. Immediately before one navigation, the
extension rechecks permission, active source tab/window and Home route,
expiration, selected video identity, and title uniqueness when applicable. It
constructs the watch URL from the strict video ID and does not automatically
retry a dispatched request whose outcome is unknown.

All feed strings remain untrusted, bounded data. The native response carries at
most 20 validated display items; extra bounded candidates used for uniqueness
exist only within one packaged extractor invocation. Returned feed values are
shown in the transient result surface and kept in one short-lived in-memory
session, but are not appended to ordinary logs, exports, UserDefaults, or the
dogfood trace.

## Platform evidence

Current official Chrome documentation was rechecked before implementation:

- [`chrome.permissions`](https://developer.chrome.com/docs/extensions/reference/api/permissions)
  requires optional host access to be requested from a user gesture and
  provides explicit state/removal APIs.
- [`chrome.scripting`](https://developer.chrome.com/docs/extensions/reference/api/scripting)
  requires the API permission plus host access and supports a packaged file in
  the isolated world.
- [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
  defines the native-host framing and exact extension-origin registration
  boundary.
- [Extension service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
  confirms that workers can stop and lose globals, supporting app-owned
  authority, versioned messages, bounded duplicate handling, and no automatic
  mutation replay.
- [`activeTab`](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab)
  is a temporary user-invocation grant and does not fit a later macOS voice
  request; the existing explicit optional YouTube origin remains the narrow
  appropriate grant.

## Automated validation

The following checks passed from the isolated Build 22 worktree:

```sh
ruby scripts/check_dependency_parity.rb
# passed; one aligned KeyboardShortcuts 3.0.1 pin

ruby scripts/check_dogfood_corpus.rb
# passed; 55 sanitized cases

ruby scripts/test_observed_query_export.rb
# passed

xcrun swift-format lint --strict -r Package.swift Sources Tests
# passed

swift test
# passed; 350 tests, 0 failures

swift test --sanitize=thread
# passed; 350 tests, 0 failures, no Thread Sanitizer report

node --test ChromeExtension/tests/*.test.mjs
# passed; 35 tests, 0 failures

ruby scripts/test_chrome_native_host.rb
# passed; 6 tests, 43 assertions, 0 failures

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-build22-debug build
# BUILD SUCCEEDED

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-build22-release build
# BUILD SUCCEEDED

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-build22-analyze analyze
# ANALYZE SUCCEEDED

git diff --check
# passed
```

The Swift corpus covers natural feed phrasing, session-scoped bare replies,
one-item and multi-item pronouns, “last,” registered-command precedence,
ordinal/title collisions, exact normalized title matching, ambiguous and stale
context, one exact or conflicting speech alternatives, natural title requests
without a “titled” keyword, permission/readiness states, protocol validation,
cancellation, timeout, and exactly-once/unknown outcomes. The
extension corpus covers exact manifest scope, shared Swift/JavaScript title
normalization fixtures, current and legacy sanitized DOM, malformed and
oversized data, missing channels, presentation versus title completeness,
duplicate titles, target drift, unrelated drift, route/permission changes,
duplicate messages, and protocol-version errors.

## Bundle and static checks

The fresh Release artifact proved:

- `CFBundleShortVersionString = 0.5.2`, `CFBundleVersion = 22`, and
  `LSUIElement = true`;
- universal `x86_64 arm64` app and native-host executables;
- valid deep strict local signatures;
- only the expected audio-input entitlement;
- an executable helper at
  `Contents/Helpers/TopherChromeBridgeHost`; and
- a source-identical embedded `ChromeExtension` directory.

Targeted scans found no required/broad host access, private key material,
common credential patterns, feed persistence, or page-derived
title/channel/video/URL values interpolated into application or extension
logs. Ordinary native relay logs contain only content-free lifecycle and
malformed-message classifications.

## Remaining manual acceptance

This record does **not** claim a live Topher/Chrome/YouTube command round trip.
Build 22 was not installed or launched, no native-host manifest was written,
the unpacked extension was not loaded/reloaded, and YouTube access was not
granted or removed. On the exact candidate app:

1. Open **Settings → General → Chrome and YouTube**. Verify absent, current,
   legacy, moved-app, and conflicting registration states. Confirm extension
   disconnected, connected-without-access, and ready states are distinct and
   do not require a tab/page read.
2. Use Topher's fixed actions to set up/repair the intended registration, open
   `chrome://extensions`, and reveal the bundled folder. Load/reload it and
   confirm Chrome reports ID `mhbppdheppcibhhcnhnfockmfpcfhndj` and version
   0.3.0.
3. In the extension popup, verify denial, grant, removal, and re-grant for only
   `https://www.youtube.com/*`. Confirm each state has understandable recovery.
4. With YouTube Home active, ask “What’s on my YouTube feed?”, “What’s YouTube
   recommending?”, and a polite homepage/list variant. Verify a useful numbered
   list of at most 20 titles/channels, accurate bounded wording, concise HUD,
   keyboard/VoiceOver row actions, reduced-motion behavior, and no feed content
   in ordinary logs or exports.
5. From fresh reads, exercise “Open the third one,” “Open video three,” “number
   three,” “the last one,” “Open the video called X,” one bare exact listed
   title, and a row click. Confirm exactly one revalidated navigation each.
6. On a multi-item feed, say “Open that YouTube video,” then answer with a bare
   number or exact title. Confirm no first-step navigation and one second-step
   navigation. On a one-item feed, confirm “open that video” opens it. Without a
   feed, confirm pronouns request a new feed and never trigger web search.
7. Exercise duplicate titles, conflicting ordinal/title language, stale and
   expired sessions, target title/ID drift, revoked permission, changed route,
   active-tab changes, native disconnect, timeout, and unknown post-dispatch
   outcomes. Confirm refusal and no retry. Verify unrelated card reorder/lazy
   loading, channel loss, and tab-title/index churn do not invalidate an
   otherwise unchanged selected video.
8. Repeat around extension reload, Chrome restart, service-worker suspension,
   non-Home routes, non-YouTube tabs, and an incognito window. Confirm no replay,
   fallback scrape, screenshot, OCR, Accessibility read, or retained feed.

Installing/replacing `/Applications/Topher.app`, mutating TCC, registering the
native host, changing Chrome's loaded extension, and granting page access all
remain explicit user-controlled actions outside this automated checkpoint.
