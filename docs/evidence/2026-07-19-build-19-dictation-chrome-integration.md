# Build 19 dictation and Chrome integration verification

- Date: 2026-07-19
- Version: 0.4.0 (19)
- Base integrated: `origin/main` at `f7f8a55`
- Scope: PR 4 merge preparation after the Chrome context foundation landed
- Live combined-build acceptance: deferred

## Why this checkpoint exists

The global-dictation branch and structured Chrome-context branch were developed
in parallel from the same older base. Each had passed independently, but that
was not evidence that their combined resolver, runtime, diagnostics, Xcode
project, documentation, and release bundle were valid.

The integration preserved both feature sets without rewriting the shared PR
history. Conflict resolution:

- retained dictation-mode refusal and all three Chrome tab intents in the
  deterministic resolver;
- assigned unique Xcode project object identifiers to the dictation sources
  while retaining the Chrome host target, dependency, and copy phase;
- kept Build 19 as the combined application build;
- retained the metadata-only Chrome boundary and focused-field-only
  Accessibility boundary; and
- kept Chrome's already-merged ADR 0013 and renumbered the dictation ADR sequence
  to 0014 through 0023, including every checked reference.

## Automated verification

The resolved combined tree passed:

```text
ruby scripts/check_dependency_parity.rb
ruby scripts/check_dogfood_corpus.rb
ruby scripts/test_observed_query_export.rb
node --test ChromeExtension/tests/*.test.mjs
ruby scripts/test_chrome_native_host.rb
xcrun swift-format lint --strict -r Package.swift Sources Tests
swift test
swift test --sanitize=thread
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug -derivedDataPath /tmp/topher-pr4-debug build
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Release -derivedDataPath /tmp/topher-pr4-release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug -derivedDataPath /tmp/topher-pr4-analyze analyze
git diff --check
```

Results:

- Swift: 320 tests, zero failures, both normal and Thread Sanitizer runs.
- Chrome extension: 13 tests, zero failures.
- Native-host registration: 5 runs and 40 assertions, zero failures.
- Sanitized manual corpus: 39 cases.
- Dependency parity, observed-query export, strict Swift formatting, Debug,
  universal Release, static analysis, and whitespace checks passed.

## Release bundle verification

The exact checked artifact is:

```text
/tmp/topher-pr4-release/Build/Products/Release/Topher.app
```

It reports version `0.4.0 (19)` and `LSUIElement = true`. Both the app executable
and embedded `Contents/Helpers/TopherChromeBridgeHost` are universal
`x86_64 arm64`. Strict deep signature and designated-requirement validation pass.
The app is locally ad hoc signed with Hardened Runtime, no Team identifier, and
only the `com.apple.security.device.audio-input` entitlement.

Executable SHA-256 values:

```text
Topher: 444257ba5a7d2844b7ba8a0fff61011444ef136b39c9de2bc04f0f1bc2837ecb
TopherChromeBridgeHost: c00d3caa40823b2fe070e7156864fb2f666186b40cb9a9f157cdb36d6f14dd83
```

## Deferred live acceptance

This integration bundle was not installed or launched. The user explicitly
accepted pausing further dictation optimization and deferred Build 19 manual
acceptance. Live Chrome extension/native-host registration and tab behavior also
remain governed by the separate Chrome acceptance guide. These are documented
dogfood gates, not claims made by this source-only merge checkpoint.
