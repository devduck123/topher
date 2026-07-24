# Build 21 YouTube recovery verification

- Date: 2026-07-21
- Version: 0.5.1 (21)
- Branch: `codex/youtube-feed-recovery`
- Scope: recoverable Chrome/native-host setup, current YouTube Home channel
  selector compatibility, direct typed feed-row actions, and explicit
  ambiguous-reference behavior

## Outcome

Build 21 closes the source-level causes of the failed YouTube feed experience
without adding an LLM or broadening page authority:

- the app bundles a reproducible stable-ID unpacked extension and exposes
  explicit native-host **Set Up**/**Repair**, Chrome Extensions, and extension
  folder actions;
- readiness inspection is read-only, while registration writes occur only from
  the explicit user action and refuse unsafe/conflicting manifests;
- one securely owned legacy Topher origin/path can be migrated to the packaged
  ID, so an earlier unpacked setup is not stranded;
- the packaged extractor recognizes current
  `yt-content-metadata-view-model` channel attribution while keeping its legacy
  fixture seam and incomplete-observation behavior;
- visible recommendation rows are accessible buttons that send a typed ordinal
  through the same policy/revalidation/exactly-once path as speech; and
- “Open that YouTube video” requests a displayed number or exact title and
  performs no effect. A model is neither required nor allowed to invent the
  missing referent.

No origin, route, extracted field, protocol operation, feed-retention rule, or
browser mutation was added. The installed app, Chrome extension state, optional
YouTube permission, and native-host registration were not changed.

## Root-cause evidence

Read-only local checks found `/Applications/Topher.app` at `0.5.0 (20)` and no
per-user Chrome native-host manifest at
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.topher.chrome_bridge.json`.
Build 20 therefore had no user-facing path to establish the required bridge.

A content-free structural inspection of the active regular YouTube Home tab
found 45 candidate card containers and 15 relevant strict watch-card
structures. The Build 20 channel selector seam completed 0 of those 15. Adding
the reviewed `yt-content-metadata-view-model` handle/channel selectors completed
14; one card without complete channel attribution remains excluded and marks
the observation incomplete. No feed title, channel, video ID, or URL was copied
into this record, repository data, or ordinary diagnostics.

## Platform evidence

Current official Chrome documentation was rechecked before implementation:

- [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
  documents the macOS per-user host location, absolute executable path, and
  exact non-wildcard `allowed_origins` entry.
- [`chrome.permissions`](https://developer.chrome.com/docs/extensions/reference/api/permissions)
  requires optional host access to be requested from a user gesture.
- [`chrome.scripting`](https://developer.chrome.com/docs/extensions/reference/api/scripting)
  requires the API permission plus host access and supports a packaged file in
  the isolated world.
- [Manifest `key`](https://developer.chrome.com/docs/extensions/reference/manifest/key)
  supports a reproducible development extension ID.
- [Extension messaging](https://developer.chrome.com/docs/extensions/develop/concepts/messaging)
  and the
  [service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
  continue to justify versioned validation, restart-safe app-owned authority,
  and no automatic mutation replay.

## Automated validation

The following checks passed from the isolated Build 21 worktree:

```sh
ruby scripts/check_dependency_parity.rb
# passed; one aligned KeyboardShortcuts 3.0.1 pin

ruby scripts/check_dogfood_corpus.rb
# passed; 47 sanitized cases

ruby scripts/test_observed_query_export.rb
# passed

xcrun swift-format lint --strict -r Package.swift Sources Tests
# passed

swift test
# passed; 341 tests, 0 failures

swift test --sanitize=thread
# passed; 341 tests, 0 failures, no Thread Sanitizer report

node --test ChromeExtension/tests/*.test.mjs
# passed; 30 tests, 0 failures

ruby scripts/test_chrome_native_host.rb
# passed; 6 tests, 43 assertions, 0 failures

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-build21-debug build
# BUILD SUCCEEDED

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-build21-release build
# BUILD SUCCEEDED

xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-build21-analyze analyze
# ANALYZE SUCCEEDED

git diff --check
# passed
```

The Swift corpus covers deterministic pronoun clarification, typed UI-command
policy routing, secure registration creation, legacy migration, moved-app
repair, conflicting-helper refusal, symlink and insecure-mode refusal, and all
existing protocol, staleness, cancellation, timeout, and exactly-once cases.
The extension corpus derives the expected extension ID from the public manifest
key and covers exact permission scope plus current/legacy sanitized selector
fixtures. The manual corpus adds the no-guess pronoun case.

## Bundle and static checks

The fresh Release artifact proved:

- `CFBundleShortVersionString = 0.5.1`, `CFBundleVersion = 21`, and
  `LSUIElement = true`;
- universal `x86_64 arm64` app and native-host executables;
- valid deep strict local signatures;
- only the expected audio-input entitlement;
- an executable helper at
  `Contents/Helpers/TopherChromeBridgeHost`; and
- a byte-identical source manifest at
  `Contents/Resources/ChromeExtension/manifest.json`.

Targeted scans found no required/broad host access, private key material,
common credential patterns, feed persistence, or title/channel/video/URL values
interpolated into application or extension logs. The public manifest key is the
only identity material in the extension; it is not a credential.

## Remaining manual acceptance

This record does **not** claim a live Topher command round trip. Build 21 was not
installed or launched, no native-host manifest was written, the unpacked
extension was not loaded/reloaded, and YouTube access was not granted or
removed. On the exact candidate app:

1. Open **Settings → General → Chrome and YouTube**. Verify absent, current,
   legacy, moved-app, and conflicting registration states; press **Set Up** or
   **Repair** only for the intended cases.
2. Use Topher's fixed buttons to open `chrome://extensions` and reveal the
   bundled folder. Enable Developer mode, load/reload that folder, and confirm
   Chrome reports ID `mhbppdheppcibhhcnhnfockmfpcfhndj`.
3. In the extension popup, verify current state, denial, grant, removal, and
   re-grant for only `https://www.youtube.com/*`.
4. With YouTube Home active, ask “What’s on my YouTube feed?” Verify a useful
   bounded numbered list, explicit truncation when applicable, a concise HUD,
   keyboard/VoiceOver row actions, and no content in ordinary logs or exports.
5. Click one row, then repeat fresh reads with “Open the third one” and “Open
   the YouTube video titled X.” Confirm immediate source/item revalidation and
   one navigation. Exercise duplicate, truncated-title, stale, changed-page,
   permission-revoked, disconnect, timeout, and unknown-outcome refusal.
6. Say “Open that YouTube video.” Confirm Topher preserves the list, asks for a
   number or exact title, and performs no navigation.
7. Repeat around extension reload, Chrome restart, service-worker suspension,
   lazy loading, non-Home routes, non-YouTube tabs, and an incognito window.
   Confirm no replay, fallback scrape, screenshot, OCR, or Accessibility read.

Installing/replacing `/Applications/Topher.app`, mutating TCC, registering the
native host, changing Chrome's loaded extension, and granting page access all
remain explicit user-controlled actions outside this automated checkpoint.
