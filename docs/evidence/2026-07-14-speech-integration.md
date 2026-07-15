# 0.3.0 speech integration evidence

Date: 2026-07-14

Status: automated integration, Debug/Release bundle, installation, and process
liveness checks pass. Microphone/TCC and user-voice acceptance remain pending.

## Implemented path

- The first explicit voice action reads or requests macOS microphone
  authorization. Merely launching Topher or opening its menu does not prompt.
- `SpeechTranscriber` uses the fixed `en_US` request with the progressive
  transcription preset. The equivalent supported locale and asset inventory
  are resolved at runtime.
- Required assets are prepared through `AssetInventory`; progress and recovery
  are exposed as bounded UI states.
- `AVAudioEngine` supplies in-memory PCM buffers. `AVAudioConverter` converts
  the active input format to the analyzer's preferred format, and no audio file
  is created.
- Key down prepares/starts one generation. Live complete partials are visible in
  the menu/HUD. Key up stops capture, flushes conversion, finalizes the analyzer,
  and allows one final typed command through the existing policy/capability
  path.
- Cancellation and generation checks prevent late results from a previous hold
  from reaching the next hold.
- A 30-second listening timeout and 8-second finalization timeout recover from
  missing key-up and stalled framework operations.

This is a direct-Apple dogfooding integration, not the final result of the
comparative speech benchmark in `docs/speech-benchmark.md`.

## Automated verification observed

Project metadata and entitlement syntax:

```sh
plutil -lint Topher.xcodeproj/project.pbxproj \
  Sources/TopherApp/Topher.entitlements
```

Result: both files report `OK`.

Swift package tests:

```sh
swift test
```

Result: 53 tests pass with zero failures. Coverage includes microphone-state
mapping, deferred prompting, speech-asset inventory/install behavior, generated
48 kHz stereo Float32 to 16 kHz mono Int16 conversion, transcription
partial/final behavior, volatile-result revocation, cancellation generations,
permission preparation, duplicate key events, stream failures, both
finalization stall modes, and the timeout/key-up race.

Strict formatting:

```sh
xcrun swift-format lint --strict -r Package.swift Sources Tests
```

Result: clean.

The deployable shared scheme built conventional Debug and Release app bundles:

```sh
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug -derivedDataPath /tmp/topher-0.3-debug build
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release -derivedDataPath /tmp/topher-0.3-release build
```

Observed bundle checks:

- `CFBundleShortVersionString=0.3.0`
- `CFBundleVersion=3`
- `LSUIElement=true`
- `NSMicrophoneUsageDescription` is present and describes hold-to-talk capture.
- The binary is universal `arm64`/`x86_64`.
- `codesign --verify --deep --strict` succeeds for Debug and Release.
- Debug entitlements contain audio input plus Xcode's expected
  `com.apple.security.get-task-allow`.
- Release contains only `com.apple.security.device.audio-input`; it does not
  contain `com.apple.security.get-task-allow`.

The deployable shared scheme is `TopherApp`. The similarly named SwiftPM
`Topher` scheme creates a bare executable and is not installation evidence.

## Installed Release verification observed

The existing 0.2.0 bundle was moved to a temporary rollback location before the
verified Release bundle was copied to `/Applications/Topher.app`. A broad,
truncated process-list check initially missed the still-resident 0.2.0 process;
an exact PID/elapsed-time check caught it before acceptance testing. That stale
process was terminated, and a fresh process was launched only after the 0.3.0
bundle was in place.

Post-copy checks establish:

- Installed version/build is `0.3.0`/`3` with bundle ID `dev.topher.app`.
- Strict deep signature validation succeeds.
- Installed Release entitlements contain only
  `com.apple.security.device.audio-input`.
- SHA-256 of the installed main executable exactly matches the verified Release
  build (`92b2ae44258d1b72b7567fdee3f69adbf9c71adae6c5d7a6fbfc844870608ef8`).
- LaunchServices accepts the bundle. Fresh PID `54268` started at 23:07:23 from
  `/Applications/Topher.app/Contents/MacOS/Topher` and remains alive as an
  accessory process after launch.

## Privacy boundary checked in source and tests

- The target requests microphone capture only. It has no Accessibility,
  Automation/Apple Events, Screen Recording, or App Sandbox network entitlement.
- The direct `SpeechAnalyzer` path does not call `SFSpeechRecognizer` and does
  not request its legacy authorization.
- Raw audio is not persisted.
- Transcript text, search text, URLs, application names, and detailed framework
  errors are not sent to Unified Logging.
- Unified Logging receives only fixed lifecycle/capability metadata.

## Pending installed-app acceptance

These checks require the locally installed 0.3.0 bundle and user interaction:

1. First hold displays the macOS microphone prompt only once and does not begin
   capture behind the prompt.
2. Grant path prepares assets if needed, asks for a fresh hold, shows live
   partial feedback, finalizes on release, and executes exactly once.
3. Denial path displays recovery guidance; returning from the Microphone privacy
   pane refreshes readiness without exposing transcript data.
4. The seven-command corpus meets local accuracy/latency thresholds on the
   user's voice and microphone.
5. Relaunch/rebuild behavior establishes how stable ad-hoc signing is for TCC on
   this Mac; no persistence guarantee is assumed before that check.
