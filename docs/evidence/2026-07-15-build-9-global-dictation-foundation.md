# Build 9 global-dictation foundation evidence

Date: 2026-07-15

## Scope

Build 9 adds a separate global hold-to-dictate path while preserving assistant
commands as a different request kind. The slice includes:

- an independently configurable dictation shortcut and shortcut-owner guard;
- explicit, user-initiated Accessibility authorization and recovery UI;
- conservative transcript formatting with no vocabulary rewriting or invented
  punctuation;
- focused-selection insertion that revalidates focus, selection, nearby text,
  settable attributes, and secure-field state immediately before mutation;
- a local preview when insertion cannot be proven safe, with clipboard access
  only after the user presses **Copy**;
- a one-step undo that runs only while focus, caret, content, and non-secure
  state still match the insertion receipt; and
- dictation-specific HUD and bounded developer-diagnostic outcomes.

The architecture and trust boundary are recorded in
[decision 0014](../decisions/0014-safe-focused-field-dictation.md).

## Safety properties

The dictation path does not invoke the command resolver or a command capability.
It never synthesizes Return, never submits content, and never automatically
writes to the clipboard. A key-up from one shortcut cannot finalize a capture
owned by the other shortcut.

Secure fields are rejected before selected text is read. If the field becomes
secure during capture, Topher discards the final transcript without creating a
preview or diagnostic record. Undo also invalidates itself without reading the
field if the original target becomes secure.

Insertion replaces only the selection captured at key-down. If the focused
element, selection, selected text, or immediate text context changes before the
final transcript is ready, Topher leaves the field unchanged and retains a
reviewable local preview instead. An insertion that succeeds but cannot move
the caret is reported as inserted without offering an unsafe undo operation.

## Automated verification

The final normal suite passed:

```text
Executed 209 tests, with 0 failures (0 unexpected)
```

The same 209 tests passed under Thread Sanitizer with no sanitizer report.
Coverage added in this slice includes permission prompt side effects, secure
fields before and after capture, oversized selections, unsupported elements,
focus/selection/context changes, word-boundary spacing, caret-update failure,
guarded undo, explicit clipboard use, shortcut ownership, distinct command and
dictation routing, fallback preview, and raw-versus-inserted diagnostics.

Additional gates passed:

- `xcrun swift-format lint --strict -r Package.swift Sources Tests`
- `ruby scripts/check_dependency_parity.rb`
- `ruby -c scripts/summarize_dogfood_diagnostics.rb`
- `git diff --check`
- a bounded repository secret-pattern scan with no match
- Xcode Debug build
- universal Xcode Release build
- Xcode Debug static analysis

## Release-bundle verification

The final Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 9
LSUIElement = true
architectures = x86_64 arm64
```

The microphone purpose string covers both user-held assistant and dictation
capture. Strict deep signature validation passed. Release entitlements still
contained only:

```text
com.apple.security.device.audio-input = true
```

Accessibility consent is a macOS privacy grant, not a new code-signing
entitlement. No Screen Recording, Automation/Apple Events, direct network, or
App Sandbox entitlement was added. Release remains a local ad-hoc Hardened
Runtime build; this is not distribution or notarization evidence.

## Remaining live acceptance

This PR deliberately does not claim broad application compatibility. It was not
installed or granted Accessibility access as part of automated validation. The
next dogfood session must exercise the built app across:

- a native single-line field and multiline editor;
- Chrome text inputs and `contenteditable` surfaces;
- a developer editor, chat composer, and rich-text surface;
- selections, emoji, composed characters, and multiline prose;
- a password field before capture and a target that changes during capture;
- focus and caret changes while the shortcut is held;
- successful undo plus every refusal state; and
- Accessibility grant, denial, Settings recovery, relaunch, and permission
  revocation.

That session should also rate prose transcription accuracy separately from
insertion correctness. Unsupported fields falling back to the local preview are
an expected safe result until the compatibility matrix justifies another
bounded insertion adapter.
