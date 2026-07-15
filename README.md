# Topher

Topher is a local-first macOS assistant. This repository currently contains a
small but end-to-end voice-command path: a native menu-bar UI, configurable
global push-to-talk, on-device English transcription, deterministic typed
command resolution, policy validation, native application launching, and
allowlisted Google/YouTube navigation.

Status: the 0.3.0 development build passes all 53 Swift tests and automated
Debug/Release app-bundle checks. Direct Apple
`SpeechAnalyzer`/`SpeechTranscriber` is integrated as the provisional engine for
local dogfooding. The strictly verified Release bundle is installed and running
from `/Applications`; microphone/TCC, accuracy, and latency acceptance on the
user's voice remains the release gate. The comparative speech benchmark is
still open.

## Implemented in this slice

- A SwiftUI `MenuBarExtra` with visible ready, listening, transcribing,
  executing, success, and failure states.
- A user-recorded global shortcut. Key down starts microphone capture after
  permission and local assets are ready; key up stops capture and explicitly
  finalizes the transcript.
- Live partial text in Topher and a transient, non-activating cross-app voice
  HUD while listening/finalizing.
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
bundle contains `NSMicrophoneUsageDescription` and only the Hardened Runtime
audio-input entitlement needed for capture. The direct `SpeechAnalyzer` path
does not request legacy `SFSpeechRecognizer` authorization, Accessibility,
Automation, Screen Recording, or Apple Events access.

Audio buffers are streamed from `AVAudioEngine` to the local analyzer and are
not written to disk. Partial/final transcripts exist transiently in process
memory and UI so the requested command can run; Topher does not persist or log
them. Denied microphone access links to the macOS Microphone privacy pane and is
rechecked when Topher becomes active again.

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

- [Technical investigation](docs/technical-investigation.md)
- [Speech benchmark plan](docs/speech-benchmark.md)
- [Implementation plan](docs/implementation-plan.md)
- [Risk register](docs/risks.md)
- [Local diagnostics](docs/local-diagnostics.md)
- [Decision records](docs/decisions/0001-native-macos-26.md)
