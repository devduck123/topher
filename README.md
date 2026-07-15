# Topher

Topher is a local-first macOS assistant. This repository currently contains a
small but end-to-end voice-command path: a native menu-bar UI, configurable
global push-to-talk, on-device English transcription, deterministic typed
command resolution, policy validation, native application launching, and
allowlisted Google/YouTube navigation.

Topher is open source under the [MIT License](LICENSE). It is an early personal
project, not a notarized application release for general installation.

Status: the 0.3.0 development build passes all 62 Swift tests and automated
Debug/Release app-bundle checks. Direct Apple
`SpeechAnalyzer`/`SpeechTranscriber` is integrated as the provisional engine for
local dogfooding. Installation in `/Applications`, launch, and process liveness
were verified for the strictly checked Release bundle. A live Core Audio
callback-isolation failure was captured, fixed, and covered by an off-main
regression test. Accuracy, latency, permission-recovery, sleep/wake, and
repeated-session acceptance remain explicit post-merge dogfood gates; this
source merge is not evidence that those paths passed.
The comparative speech benchmark is still open.

## Implemented in this slice

- A SwiftUI `MenuBarExtra` with visible ready, listening, transcribing,
  executing, success, and failure states.
- A user-recorded global shortcut. Key down starts microphone capture after
  permission and local assets are ready; key up stops capture and explicitly
  finalizes the transcript.
- Live partial text in Topher and a transient, non-activating cross-app voice
  HUD for preparation, listening, finalization, execution, and outcomes.
- A 30-second listening watchdog, an 8-second finalization watchdog, immediate
  stream-error recovery, and generation guards against late results.
- Direct Apple on-device transcription for fixed `en_US`, with on-demand asset
  preparation and no raw-audio file writes.
- Manual execution for development without speech.
- Typed, allowlisted commands for Chrome, Safari, and Visual Studio Code.
- Typed, allowlisted navigation to Google and YouTube.
- Google, general web, and YouTube searches built from fixed HTTPS endpoints.
- Native launch through `NSWorkspace`.
- A separate policy decision before execution.
- Safe rejection of unknown text and applications.
- XCTest coverage for parsing, policy, native capabilities, audio conversion,
  permission/assets, transcription, cancellation, and push-to-talk races.

## Current interaction boundary

Topher's global shortcut already works while another application is focused;
the menu does not need to be open. The current hold is a **push-to-talk assistant
command**: release sends the transient transcript through Topher's typed command
resolver and policy.

It is not yet general-purpose text dictation into the focused field. Always-on
wake listening, remote chat requests, conversational follow-ups, browser-page
reading, Accessibility context, and screen understanding are also not
implemented. They are separate modes and trust boundaries rather than flags on
the current command path.

See [Interaction modes](docs/product/interaction-modes.md) and
[Request lifecycle and context](docs/architecture/request-lifecycle.md) for the
canonical product and architecture contracts.

## Where the AI is (and is not)

Speech recognition is now the first ML component in the live path, but there is
still no LLM deciding what Topher may do. The current grammar turns a transcript
into a typed command, passes an independent policy check, and reaches one narrow
native capability without giving a model arbitrary control of the Mac.

The intended layers are:

1. Deterministic commands for exact requests such as “Open Safari,” “Go to
   YouTube,” and “Search YouTube for local AI.” These do not need AI.
2. A future optional local model that interprets fuzzier phrasing into the same
   typed commands. It proposes; the policy layer still decides what can execute.
3. Permissioned browser context for requests such as “What’s on my feed?” or
   “Go to this Chrome tab.” Those require a narrow Chrome extension/native
   adapter and are not implemented yet.

## Build and run

Use full Xcode with the macOS 26 SDK selected:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift test
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug build
```

Tests remain SwiftPM-owned in this slice. The `TopherApp` scheme has no Xcode
test target, so use `swift test` as the authoritative test command rather than
Cmd-U.

For normal app development, open `Topher.xcodeproj`, select the `TopherApp`
scheme, and Run. The separate SwiftPM `Topher` scheme builds a bare executable;
it is useful for compiler checks but is not the deployable app bundle.

For an interactive smoke test:

1. Click Topher's sparkles icon in the menu bar.
2. Record a normal modified shortcut.
3. Hold it once. Grant microphone access if macOS asks, then let Topher prepare
   the local English speech asset. Release and hold again after Topher says it
   is ready.
4. Say “Open Safari,” release, and confirm the HUD changes from listening to
   finalizing before Safari opens exactly once.
5. Try “Go to YouTube,” “Search YouTube for C++ and Swift,” and “Search Google
   for best local speech model.”
6. Speak unknown text and confirm it fails closed.
7. Use the manual transcript field and **Run** as a development fallback.

No default shortcut is claimed. This avoids silently overriding an existing
system or application shortcut.

## Voice privacy and permissions

Topher asks for microphone access only from an explicit voice action. Its app
bundle contains `NSMicrophoneUsageDescription`; the Release signature contains
only the `com.apple.security.device.audio-input` entitlement needed for capture.
The direct `SpeechAnalyzer` path does not request legacy `SFSpeechRecognizer`
authorization, Accessibility, Automation/Apple Events, or Screen Recording
access.

Audio buffers are streamed from `AVAudioEngine` to the local analyzer and are
not written to disk. Partial/final transcripts exist transiently in process
memory and UI so the requested command can run; Topher does not persist or log
them. Denied microphone access links to the macOS Microphone privacy pane and is
rechecked when Topher becomes active again.

## Current macOS security posture

Hardened Runtime is enabled, while App Sandbox is currently disabled. These are
separate protections: the current local build must not be described as
sandboxed merely because Hardened Runtime is on. Debug and Release use local
ad-hoc signing; Debug also receives Xcode's development-only
`com.apple.security.get-task-allow` entitlement. There is no Developer ID
signature or notarized release.

The current web commands construct allowlisted HTTPS destinations and hand them
to the user's default browser through `NSWorkspace`. Topher itself has no direct
network client, embedded browser, Chrome extension/native-messaging host,
browser-page or tab capture, Accessibility provider, or screen-capture
implementation. The browser performs the external request and maintains its
normal history when the user explicitly runs a search or navigation command.

Before Topher adds direct networking, browser-content adapters, broader local
data access, or distribution to other Macs, revisit the App Sandbox decision,
capability-specific entitlements, stable Developer ID signing, notarization,
and the corresponding permission and denial-recovery tests.

## Logs and diagnostics

Topher writes metadata-only events to macOS Unified Logging under subsystem
`dev.topher.app` and category `control-path`. It does not create an app-owned log
file or database, and it does not log the manual transcript, search query, URL,
raw audio, application name, or detailed error text.

Stream new events while testing:

```sh
/usr/bin/log stream --style compact --level info \
  --predicate 'subsystem == "dev.topher.app"'
```

Inspect recently retained events:

```sh
/usr/bin/log show --last 1h --style compact --info \
  --predicate 'subsystem == "dev.topher.app"'
```

The operating system manages and rotates this diagnostic store. See
[Local diagnostics](docs/local-diagnostics.md) for the current event inventory
and the macOS-to-web-development mental model.

## Read next

- [Interaction modes](docs/product/interaction-modes.md)
- [Request lifecycle and context](docs/architecture/request-lifecycle.md)
- [Technical investigation](docs/technical-investigation.md)
- [Speech benchmark plan](docs/speech-benchmark.md)
- [Implementation plan](docs/implementation-plan.md)
- [Risk register](docs/risks.md)
- [Local diagnostics](docs/local-diagnostics.md)
- [Latest pre-merge verification](docs/evidence/2026-07-15-pre-merge-hardening.md)
- [Decision records](docs/decisions/0001-native-macos-26.md)
- [Contributing and macOS development practices](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
