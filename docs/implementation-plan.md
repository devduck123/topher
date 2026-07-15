# Ordered implementation plan

Every slice ends with a runnable application. Deterministic browser navigation
may move forward when it uses fixed endpoints and native APIs. Do not start
browser page reading, Accessibility, screen capture, or wake-word work until the
speech-to-action loop survives the reliability slice.

## Prerequisite: reproducible native build — complete

1. Xcode 26.6 is installed and selected with `xcode-select`.
2. `swift test` passes all 53 tests and the SwiftPM product builds.
3. The conventional Xcode macOS application target uses fixed bundle ID
   `dev.topher.app`, `LSUIElement`, local signing, and the existing local core.
4. Debug and Release bundles build. The tightened Release bundle is installed
   in `/Applications`, passes strict signature validation, launches as a UI
   element, creates its status-item scene, and remains running.

The original 0.2.0 installed bundle completed the no-permission matrix. The
microphone-specific Xcode-versus-`/Applications` matrix remains part of the
0.3.0 acceptance gate.

## Slice 1: control path without speech — complete

- Menu-bar presence and configurable global shortcut.
- Key-down/listening and key-up/transcribing lifecycle using mock text.
- Deterministic typed `openApplication` command.
- Policy validation and native `NSWorkspace` execution.
- Visible success/failure and unit tests.

Automated evidence covers parsing, policy, native capability outcomes,
Debug/Release compilation, bundle metadata, signing, installation, process
liveness, and status-item creation. The user manually confirmed that Safari,
Chrome, and Visual Studio Code execute from the panel, unknown input fails
closed, and the key-down/up lifecycle works as expected.

## Slice 2: isolated speech benchmark — pending measured corpus

- Build separate direct-Apple, AuralKit, FluidAudio, WhisperKit, and (if still
  justified) whisper.cpp adapters in the benchmark harness.
- Record the user's corpus with consent.
- Capture accuracy, latency, resources, assets, partial/final behavior, and
  recovery results in `speech-benchmark.md`.
- Select one engine. Delete temporary raw recordings.

Exit: a measured decision record names one engine and its fallback behavior;
the main app remains runnable without speech.

## Slice 3: speech-connected command loop — implemented, live acceptance open

Topher now integrates the direct Apple candidate for dogfooding before the
comparative benchmark closes. This makes the real loop testable without
pretending the permanent engine decision has been made.

- Complete: direct `SpeechAnalyzer`/`SpeechTranscriber`, `AVAudioEngine`
  capture, explicit audio conversion, asset preparation, and a focused
  microphone permission manager.
- Complete: `NSMicrophoneUsageDescription` and only the Hardened Runtime
  `com.apple.security.device.audio-input` entitlement needed by capture.
- Complete: the manager names the feature and reason, exposes authorization
  state, requests only from a user voice action, explains denied/restricted
  recovery, provide a verified route to the correct System Settings pane,
  and refreshes state when Topher becomes active.
- Complete: no speech-recognition authorization because the current direct path
  does not use `SFSpeechRecognizer`.
- Complete: hotkey down starts capture and key-up explicitly finalizes it; live
  partials appear in the menu and transient cross-app HUD.
- Complete: 30-second listening and 8-second finalization watchdogs, immediate
  stream failure recovery, stale-generation rejection, and regression tests for
  key-up/cancellation races.
- Complete: manual transcript fallback remains available.
- Complete: raw audio is never written and transcript text is not persisted or
  logged.
- Pending: install 0.3.0, exercise first-run grant/denial/settings recovery, and
  measure the seven-command corpus on the user's microphone and voice.

Exit: the seven-command corpus reaches the accepted local bar without a network
dependency, and installed-app denial/error recovery is verified.

## Slice 4: useful deterministic command set — in progress

- Complete in 0.2.0: allowlisted Google/YouTube home navigation plus Google,
  general web, and YouTube search through fixed HTTPS endpoints.
- Add validated explicit HTTPS URL opening only if a later use case needs it.
- Add application discovery plus explicit aliases without accepting arbitrary
  model-provided bundle IDs.
- Add a read-only active-application provider for “What app am I using?”
- Expand parser, policy, URL validation, and executor tests.

Exit: every proposed MVP command works without an LLM, Accessibility, or Screen
Recording.

## Slice 5: optional structured interpretation

- Recheck `SystemLanguageModel.default.availability` and locale support.
- Add constrained structured output only for deterministic misses.
- Evaluate against a held-out command corpus and adversarial retrieved text.
- Keep deterministic behavior identical when Apple Intelligence is disabled.

Exit: fuzzy phrasing improves without increasing unauthorized action rate; if
it does not, remove the model path.

## Slice 6: reliability and local diagnostics

- Exercise 100 repeated sessions, cancellation, timeouts, sleep/wake, and audio
  device changes.
- Add bounded local action diagnostics that distinguish proposed, rejected,
  started, and completed actions without raw audio, transcript text, search
  queries, or page contents.
- Test shortcut conflicts and launch-at-login only if daily use warrants it.

Exit: the core loop recovers without restarting Topher and meets the measured
latency/resource bar.
