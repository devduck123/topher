# Pre-merge speech and cross-app UX hardening

Date: 2026-07-15

This record covers the automated repair pass after the initial installed-app
speech integration. It does not replace the pending interactive acceptance on
the user's installed bundle.

## Correctness changes

- A failed `SpeechTranscriber` result stream now fails Topher's public event
  stream immediately, stops microphone capture, closes analyzer input,
  invalidates the session generation, and cancels/resets the runtime.
- A finalizer captures its own result task before its first suspension, so a
  cancelled hold cannot await a later hold's still-open result stream.
- Global feedback has a voice-origin-only lifecycle: preparing, listening,
  finalizing, executing, and transient success/failure. Manual commands and the
  menu's setup action do not present the cross-app HUD.
- A finalized transcript replaces stale partial text before execution and in
  finalizing feedback.
- Permission refresh cancels and generation-guards stale asset checks. A
  denied-to-authorized transition clears the stale denial outcome, while a
  restricted state explains the policy boundary without offering a misleading
  Settings recovery button.
- The pointer-only in-menu hold surface was removed. The user-recorded global
  shortcut remains the supported push-to-talk input.

## Automated verification

- Dependency parity: passed for `KeyboardShortcuts` 3.0.1 across SwiftPM,
  Xcode, and both lockfiles.
- Strict recursive `swift-format` lint: passed.
- `swift test`: 62 tests passed with zero failures, both normally and with
  Thread Sanitizer. The eight session tests include immediate failure teardown
  and cancel/new-generation isolation regressions.
- Unsigned Debug app build: succeeded.
- Unsigned universal arm64/x86_64 Release app build: succeeded.
- Debug `xcodebuild analyze`: succeeded.
- `git diff --check`: passed.

Xcode emitted only its existing App Intents metadata message because Topher
does not link `AppIntents.framework`; it emitted no Topher compiler or analyzer
warning.

## Interactive acceptance still required

Before merging, install/run the current patched build and verify:

1. Fresh microphone grant and deny -> System Settings -> grant recovery.
2. Preparing feedback appears immediately while another app is focused, and
   the user waits for Listening before speaking.
3. The seven supported commands execute exactly once and unknown speech fails
   closed with visible feedback.
4. Ten to twenty consecutive global holds survive without clipped first words,
   stuck capture, duplicate execution, or a new crash report.
5. Relaunch once and repeat a supported command.

The 100-session run, external audio routes, sleep/wake, speech-engine benchmark,
Developer ID signing, and notarization remain later gates.
