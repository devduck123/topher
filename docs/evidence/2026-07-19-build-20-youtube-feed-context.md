# Build 20 YouTube feed-context verification

- Date: 2026-07-19
- Version: 0.5.0 (20)
- Scope: optional-permission YouTube Home feed read and short-lived listed-item open
- Live Chrome/YouTube acceptance: pending
- Installed application changed: no

## Outcome

Build 20 adds a deterministic, local YouTube-specific context slice on top of
the existing Chrome/native-messaging bridge. “What’s on my YouTube feed?” can
return at most 20 ordered Home recommendations to an accessible Topher menu
card after the user grants optional YouTube access in the extension popup.
“Open the third one” and “Open the YouTube video titled X” use only the latest
90-second in-memory snapshot. The open path consumes that session before
dispatch, revalidates permission/source/page/fingerprint/expiry/item presence,
constructs a strict watch URL from the video ID, and performs one non-retried
tab update.

This is not a general browser agent. The extractor is a fixed packaged file in
the isolated world. Tests and source review confirm no required host access,
content script, extension storage, screenshot, OCR, cookies, history, account
data, comments, descriptions, arbitrary URL, page/model-generated JavaScript,
or continuous feed mirroring. Unified Logging remains content-free. The
explicit local dogfood trace may retain the exact user-authored title command
under its existing contract, but it never receives the returned feed snapshot,
channel, video ID, source URL, observation value, or destination.

## Automated verification

The following commands passed from the isolated Build 20 worktree:

```sh
ruby scripts/check_dependency_parity.rb
ruby scripts/check_dogfood_corpus.rb
ruby scripts/test_observed_query_export.rb
xcrun swift-format lint --strict -r Package.swift Sources Tests
swift test
swift test --sanitize=thread
node --test ChromeExtension/tests/*.test.mjs
ruby scripts/test_chrome_native_host.rb
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-youtube-debug build
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-youtube-release \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-youtube-analyze analyze
git diff --check
```

Results:

- Swift: 334 tests, zero failures, normally and under Thread Sanitizer.
- Extension: 27 dependency-free Node tests, zero failures.
- Native-host registration/framing: 5 runs and 40 assertions, zero failures.
- Sanitized manual corpus: 46 cases; observed-query exporter tests passed.
- Dependency parity: KeyboardShortcuts 3.0.1 at the same revision in SwiftPM,
  Xcode, and both resolved files.
- Strict Swift formatting, Debug build, universal Release build, static
  analysis, and whitespace checks passed.
- The only Xcode warning was the existing App Intents metadata notice that no
  AppIntents framework dependency exists.

The focused deterministic corpus covers feed phrasings, ordinals 1 through 20,
normalized title selection, ambiguity, missing/stale context, truncated title
refusal, permission denial/revocation, unsupported routes, malformed and
oversized untrusted values, duplicate items/requests, extractor bounds and
sanitized DOM fixtures, cancellation/timeout, DOM drift, version mismatch,
native disconnect classification, exactly-once dispatch, and unknown
post-dispatch outcomes. Existing command, application, web, Chrome-tab,
dictation, and diagnostics suites remain included in the 334-test run.

## Release bundle verification

The exact checked artifact is:

```text
/tmp/topher-youtube-release/Build/Products/Release/Topher.app
```

`plutil`, `lipo`, and `codesign` checks confirm:

- version `0.5.0 (20)` and `LSUIElement = true`;
- app and embedded `Contents/Helpers/TopherChromeBridgeHost` are universal
  `x86_64 arm64`;
- strict deep signature and designated-requirement verification pass;
- the app is ad hoc signed with Hardened Runtime and no Team identifier; and
- its only entitlement is `com.apple.security.device.audio-input`.

Executable SHA-256 values:

```text
Topher: db9a613320901b04d225ae0a165313a3083467b2c89b4965c3e40ba0b5941a35
TopherChromeBridgeHost: b4a09fc6826e6017d6516075b35aab4f28375e761e7ae310dcd81083e8a5ee2c
```

No app was installed, launched, or used to change the user's current Topher or
Chrome configuration during this verification.

## Remaining manual acceptance

This checkpoint does not claim live Chrome/YouTube success. On the user's
chosen test bundle and Chrome profile:

1. Load the unpacked extension, register the exact extension origin/helper
   path, and launch that exact non-installed test bundle.
2. With YouTube access absent, ask for the feed and verify the extension-popup
   grant instructions. Deny once, reopen the popup, grant, remove, and regrant;
   confirm current-state and recovery copy always agree with Chrome.
3. Make YouTube Home active, ask for the feed, and verify at most 20 relevant
   title/channel rows, bounded labeling, concise HUD feedback, keyboard access,
   VoiceOver order/labels, light/dark appearance, and no new animation under
   Reduce Motion.
4. Open a listed item by ordinal and then, after a fresh read, by one unique
   exact title. Confirm one source-tab navigation and the expected video.
5. Exercise duplicate titles and a visibly bounded/lazy-loaded feed. Confirm a
   title request refuses when global uniqueness is not proven while a listed
   ordinal can still revalidate safely.
6. Between read and open, switch tabs/windows, navigate/reload Home, change the
   feed, wait past 90 seconds, close the tab, and revoke permission. Every case
   must perform zero navigation and ask for a fresh feed or grant.
7. Ask on watch, search, Shorts, non-YouTube, and incognito pages. Confirm no
   broader DOM, Accessibility, screenshot, or OCR fallback.
8. Reload/suspend the extension and disconnect/restart the native host around
   read/open requests. Confirm recoverable reads and no automatic replay after
   a dispatched unknown mutation outcome.
9. Stream Unified Logging and inspect the bounded dogfood trace/export. Confirm
   no returned title, channel, video ID, source URL, observation ID, or
   destination appears unless a title exists solely because the user spoke it
   in the explicitly retained command.

Record a new dated evidence note after that live pass. Do not amend this record
to imply acceptance it did not observe.
