# Pre-merge speech and cross-app UX hardening

Date: 2026-07-15

This record covers the automated repair pass after the initial installed-app
speech integration and the final source-merge gate. It separates verified
evidence from physical-microphone dogfooding so an experimental source merge is
not mistaken for a tested or distributable release.

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

## Installed candidate verification

The Release candidate built from source commit `a78b1a5` was installed at
`/Applications/Topher.app` and checked independently of Xcode:

- Deep, strict `codesign` verification passed after installation.
- The installed executable exactly matched the built candidate with SHA-256
  `ca3e79014467039fe4a5f5add381964dadb855431b37f09e292293f22da5186b`.
- The installed Mach-O contains both arm64 and x86_64 slices.
- Hardened Runtime is enabled with an ad-hoc signature. The only Release
  entitlement is `com.apple.security.device.audio-input`.
- Bundle identifier, version/build, minimum macOS version, agent-app setting,
  and microphone usage description matched the checked project configuration.
- The installed app launched as `/Applications/Topher.app`, remained alive
  during the verification window, and produced no new Topher diagnostic crash
  report. The only report present remained the 2026-07-14 pre-fix crash used to
  drive the callback-isolation repair.

This verifies build/install integrity and launch stability. It does not verify
recognition accuracy or the end-to-end physical shortcut and microphone path.

## Deferred interactive dogfood

The repository owner explicitly deferred physical-microphone acceptance while
feature exploration continues. Before describing 0.3.0 as tested or
release-quality, run the installed candidate and verify:

1. Fresh microphone grant and deny -> System Settings -> grant recovery.
2. Preparing feedback appears immediately while another app is focused, and
   the user waits for Listening before speaking.
3. The seven supported commands execute exactly once and unknown speech fails
   closed with visible feedback.
4. Ten to twenty consecutive global holds survive without clipped first words,
   stuck capture, duplicate execution, or a new crash report.
5. Relaunch once and repeat a supported command.

Record the macOS version, input device, shortcut, command corpus, pass/fail
counts, any clipped or duplicate result, and the timestamps of matching
metadata-only Unified Log events. Do not record raw audio. Keep ordinary
Unified Logging metadata-only; final transcript text may appear only in the
later, explicitly enabled bounded developer trace documented in
`docs/local-diagnostics.md`.

The 100-session run, external audio routes, sleep/wake, speech-engine benchmark,
Developer ID signing, and notarization remain later gates. Deferring them is an
explicit experimental-merge tradeoff, not evidence that they passed.
