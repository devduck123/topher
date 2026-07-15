# Xcode application verification

Date: 2026-07-14, America/Los_Angeles

This record follows the earlier Command Line Tools-only probes. It captures the
checks performed after installing and initializing full Xcode.

## Active toolchain

```sh
xcode-select -p
xcodebuild -version
xcodebuild -checkFirstLaunchStatus
swift --version
```

Relevant output:

```text
/Applications/Xcode.app/Contents/Developer
Xcode 26.6
Build version 17F113
first-launch status: success
Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
Target: arm64-apple-macosx26.0
```

## SwiftPM verification

```sh
swift package resolve
swift test
swift build --product Topher
```

Results:

- KeyboardShortcuts resolved to 3.0.1 at revision
  `49c3fc04ea827f816df67843bfcc57286b47ff06`.
- The full app, core, dependency, and test targets compiled with Swift 6.3.3.
- All 11 XCTest cases passed: 4 application-open capability tests, 2 policy
  tests, and 5 resolver tests.
- The SwiftPM executable product built successfully. It remains a bare
  executable and is not used as packaging evidence.

## Conventional app target

The repository now contains `Topher.xcodeproj`. Its shared `TopherApp` scheme
avoids a name collision with SwiftPM's bare `Topher` executable scheme.

```sh
xcodebuild -list -project Topher.xcodeproj
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-derived-20260714 build
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-release-verified-20260714 build
```

Both configurations succeeded. The Release target disables Xcode's base debug
entitlement injection before signing.

## Release bundle and signature

```sh
plutil -p Topher.app/Contents/Info.plist
file Topher.app/Contents/MacOS/Topher
codesign -dvvv --entitlements :- Topher.app
codesign --verify --deep --strict --verbose=4 Topher.app
```

Confirmed result:

```text
CFBundleIdentifier = dev.topher.app
LSUIElement = true
LSMinimumSystemVersion = 26.0
architectures = arm64, x86_64
signature = ad hoc
code-directory flags = ad hoc, runtime
release entitlements = none
strict signature verification = valid on disk; satisfies designated requirement
```

There are no valid Apple code-signing identities on this Mac. A Gatekeeper
assessment did not accept the ad-hoc artifact, so this build is local-only and
must not be represented as Developer ID signed or notarized.

## Installation and runtime

The verified Release bundle was copied to `/Applications/Topher.app` and
launched. Process inspection showed:

```text
/Applications/Topher.app/Contents/MacOS/Topher
```

The process remained alive. Unified launch logs confirmed all of the following:

- LaunchServices checked in bundle identifier `dev.topher.app` from
  `/Applications/Topher.app`.
- Its application type is `UIElement` rather than a Dock application.
- AppKit created both `NSStatusItemScene` and its hosted status-item view scene.
- No microphone or speech permission is present in this slice.

AppKit also emitted code 4097 while trying to reach the system
`com.apple.linkd.autoShortcut` service. The Topher binary does not link
AppIntents, and the process and status-item scene remained live after the error.
This is recorded as non-blocking system-integration log noise unless the manual
interaction check reveals a related symptom.

The available UI automation bridge could not attach to a status-bar-only app or
Control Center, so it did not provide reliable evidence for clicking the panel,
recording a shortcut, or executing the manual transcript. Those remain explicit
human acceptance checks rather than inferred successes.

## Manual acceptance and 0.2.0 web extension

The user subsequently confirmed that the menu, shortcut lifecycle, supported
application commands, and fail-closed behavior worked as expected. This closes
the human acceptance gap above without treating unavailable UI automation as
evidence.

Release 0.2.0 adds typed Google/YouTube homepage navigation and fixed-endpoint
Google/YouTube search. It does not add arbitrary URL handling, page reading,
Chrome tab control, or a model.

Verification performed for the extension:

```sh
swift test
xcrun swift-format lint --strict -r Package.swift Sources Tests
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-web-debug-20260714 build
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-web-release-20260714 build
codesign --verify --deep --strict --verbose=4 Topher.app
```

Confirmed results:

- All 24 XCTest cases pass.
- Strict Swift formatting passes.
- Debug and Release app builds succeed.
- Release 0.2.0 build 2 is a universal `arm64`/`x86_64` binary.
- The Release signature remains ad hoc with Hardened Runtime enabled, no release
  entitlements, and strict signature validation passing.
- Search URLs use fixed HTTPS hosts and paths; query construction encodes a
  literal plus as `%2B` rather than allowing `C++` to become spaces.
- Unified Logging from the manual run showed capability start/completion,
  push-to-talk lifecycle, and rejection events. No transcript, query, URL, raw
  audio, application name, or detailed error value is logged.

The verified 0.2.0 bundle was then copied to `/Applications/Topher.app`. The
installed executable's SHA-256 matched the Release artifact exactly:

```text
61aa726c5d32ce1324d5118fbf4baec1df8d46956722cd1be321c505092d7714
```

LaunchServices started the installed binary as PID 9549. Runtime logs confirmed
`CFBundleShortVersionString=0.2.0`, `CFBundleVersion=2`, application type
`UIElement`, and creation of the `NSStatusItemScene`. Manual acceptance of the
new web commands remains a human smoke test; installation and process liveness
do not prove that a requested browser page loaded.
