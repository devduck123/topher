# Topher

Topher is a local-first macOS assistant. This repository currently contains a
small but end-to-end control path: a native menu-bar UI, configurable global
push-to-talk lifecycle, manual transcript input, deterministic typed command
resolution, policy validation, native application launching, and allowlisted
Google/YouTube navigation.

Status: Release 0.2.0 is build verified. Xcode 26.6 builds the conventional
`Topher.app`, all 24 tests pass, and the locally signed app runs from
`/Applications` as a menu-bar-only process. The shortcut lifecycle, supported
app launches, and fail-closed behavior have also passed interactive acceptance.

The slice intentionally has no microphone capture or model dependency yet. It
settles the command-to-capability path before speech is selected with recordings
of the actual user.

## Implemented in this slice

- A SwiftUI `MenuBarExtra` with visible ready, listening, transcribing,
  executing, success, and failure states.
- A user-recorded global shortcut. Key down begins the mock listening state;
  key up processes the transcript through one ordered event stream. A 30-second
  timeout recovers from a missing key-up.
- Manual execution for development without speech.
- Typed, allowlisted commands for Chrome, Safari, and Visual Studio Code.
- Typed, allowlisted navigation to Google and YouTube.
- Google, general web, and YouTube searches built from fixed HTTPS endpoints.
- Native launch through `NSWorkspace`.
- A separate policy decision before execution.
- Safe rejection of unknown text and applications.
- XCTest coverage for parsing, policy behavior, and native capability outcomes.

## Where the AI is (and is not)

There is no model in the execution path yet. That is intentional: the current
grammar proves that a user request can become a typed command, pass an
independent policy check, and reach one narrow native capability without giving
a model arbitrary control of the Mac.

The intended layers are:

1. Deterministic commands for exact requests such as “Open Safari,” “Go to
   YouTube,” and “Search YouTube for local AI.” These do not need AI.
2. An optional local model that interprets fuzzier phrasing into the same typed
   commands. It proposes; the policy layer still decides what can execute.
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
3. Enter `Open Safari.` and press **Run**; then try `Go to YouTube` and `Search
   YouTube for C++ & Swift #1`.
4. Try `Search Google for best local speech model` or `Search the web for Swift
   SpeechAnalyzer`.
5. Enter unknown text and confirm it fails closed.
6. With another app focused, hold and release the shortcut and confirm the
   visible listening, transcribing, executing, and result states.

No default shortcut is claimed. This avoids silently overriding an existing
system or application shortcut.

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
