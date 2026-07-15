# Assistant pipeline foundation verification

Date: 2026-07-15
Source commit: `4cbbf3a`

This is a historical checkpoint. The later opt-in developer transcript trace is
covered by [Developer transcript diagnostics verification](2026-07-15-developer-transcript-diagnostics.md);
its bounded persistence does not alter the metadata-only Unified Logging claims
below.

This record covers the foundation refactor and the first small command-set
extension after the 0.3.0 speech merge. It records automated evidence only;
physical-microphone and daily cross-application dogfooding remain explicitly
deferred.

## Implemented boundaries

- `PushToTalkCaptureController` now owns permission, speech assets, engine
  preparation, capture, partial/final state, timeouts, generation guards,
  cancellation, and terminal shutdown. It returns raw finalized text and does
  not choose command versus dictation behavior.
- `AssistantCommandProcessor` owns deterministic resolution, independent policy
  evaluation, and exactly-one registered capability execution.
- Unsupported text is a `CommandResolution`, not an executable
  `TopherCommand`, and does not cross the policy boundary.
- `TopherModel` retains presentation and request-kind routing. It tracks one
  command task, rejects overlapping work, preserves command-only global HUD
  behavior, and tears down active capture when released.
- The HUD retains one nonactivating panel and hosting view across partial
  updates. The menu-bar item exposes its current phase as an accessibility
  value, and the recorder is visibly labeled as an assistant-command shortcut.

## Deterministic capability extension

- Notion was added to the application-owned allowlist after confirming the
  installed app uses bundle identifier `notion.id`.
- Bounded phrase variants include “Navigate Chrome,” “Navigate to Chrome,”
  “Switch to Chrome,” “Switch over to Google Chrome,” and “Pull up YouTube.”
- Negative cases such as embedded webpage instructions, negated requests,
  questions, and extra target suffixes remain unsupported.
- No arbitrary bundle identifier, URL, shell command, AppleScript, browser
  JavaScript, or model-generated action path was added.

## Automated verification

- Dependency parity passed for KeyboardShortcuts 3.0.1 across SwiftPM, Xcode,
  and both lockfiles.
- Strict recursive `swift-format` lint passed.
- `swift test` passed all 92 tests with zero failures.
- The same 92 tests passed under Thread Sanitizer with no reported data race.
- Tests cover raw-text preservation, first-run retry gates, duplicate key-up,
  late final replacement, stream failures, both watchdogs, suspended cleanup,
  terminal shutdown/deallocation, unsupported-to-valid retry, stale permission
  recovery, and exactly-one command execution.
- The final unsigned Debug app build passed.
- The final Debug `xcodebuild analyze` invocation passed.
- A locally signed universal Release app build passed.
- `git diff --check` and the targeted credential-pattern scan passed.
- Independent lifecycle/test and security/privacy reviews ended with no open
  actionable findings.

The Xcode target explicitly includes both new app source files; SwiftPM
discovers them automatically.

## Release bundle inspection

The inspected candidate was:

```text
/tmp/topher-foundation-signed/Build/Products/Release/Topher.app
```

Confirmed properties:

- Strict deep code-signature validation passed.
- Signature is ad hoc with Hardened Runtime enabled, as expected for local
  dogfooding; it is not Developer ID signed or notarized.
- Executable architectures are `arm64` and `x86_64`.
- Bundle identifier is `dev.topher.app`; version/build is `0.3.0`/`3`;
  `LSUIElement` is true; minimum macOS version is 26.0.
- The only Release entitlement is
  `com.apple.security.device.audio-input = true`.
- Executable SHA-256 is
  `c9728b6ccdc8a7954f9640335676681f193902b4f703d3347d84af02e21dc149`.

## Privacy and permission check

Unified Logging uses fixed metadata-only messages in `control-path` and
`voice-capture`. Signpost intervals contain only the fixed names
`VoicePreparation`, `VoiceCapture`, and `VoiceFinalization`; they carry no
payload. No transcript, query, URL, raw audio, target identifier, or detailed
error is logged.

This slice adds no credential, network client, persistent transcript/history,
Accessibility, Automation/Apple Events, Screen Recording, browser extension,
or ambient-listening permission. App Sandbox remains disabled as an existing
documented local-dogfood limitation.

## Deferred interactive acceptance

Installation and live physical-microphone testing were not repeated for this
foundation branch. Before treating it as a dogfood release, verify the global
shortcut from another focused app, first-run permission and settings recovery,
Notion/Chrome/YouTube phrase variants, unknown-command rejection, repeated
holds, and relaunch. Browser feed reading, Chrome tab inspection, focused-field
dictation, wake listening, and remote chat ingress remain separate future trust
boundaries rather than implied capabilities of this refactor.
