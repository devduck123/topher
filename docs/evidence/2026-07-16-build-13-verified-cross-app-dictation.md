# Build 13 verified cross-app dictation evidence

Date: 2026-07-16

## Trigger and diagnosis

Build 12's local developer trace marked six dogfood dictations as inserted, but
the user observed visible insertion for only three. The failures occurred in
ChatGPT/Codex, Notion, and Chrome. There were no permission, capture,
finalization, or fallback errors, and observed processing remained fast. The
native boundary was therefore producing false-positive effect claims.

`FocusedTextInsertionCapability` treated a successful Accessibility
selected-text setter as insertion. The macOS 26.5 headers describe selected text
as non-writable, while the value attribute is the standard writable text
surface. A Chromium/Electron-backed element can accept the former call without
changing its visible content.

## Change

- Capture and revalidate focused-element process identity, role, selection,
  surrounding boundary, secure state, and fixed settable capabilities.
- Choose exactly one mutation method before writing. A bounded whole-value
  adapter is available only for a plain text field, empty text area, or full-
  value text-area replacement whose value and result are each at most 16,384
  UTF-16 units. Web areas and partially selected nonempty text areas cannot use
  it.
- Verify inserted text and caret immediately, then retry readback up to three
  times at 10 ms. A readable unchanged mutation and an unavailable readback are
  distinct typed failures; neither reports insertion.
- Preserve pending text for review. An unverifiable result specifically tells
  the user to inspect the target before copying, avoiding duplicate text if a
  host mutation appears late.
- Record only fixed method, verification, role, and settable-capability evidence
  in the bounded trace and exporters. No target app, process identity, field
  content, selected content, or framework error was added.
- Keep clipboard writes explicit, never synthesize input or Return, and do not
  advertise Topher undo for whole-value insertion.

The architecture tradeoff is recorded in
[decision 0017](../decisions/0017-verify-accessibility-dictation-mutations.md).

## Automated verification

- dependency parity passed;
- the 20-case sanitized dogfood corpus and observed-query exporter tests passed;
- strict Swift formatting and `git diff --check` passed;
- all 231 tests passed normally;
- all 231 tests passed under Thread Sanitizer with no sanitizer report;
- Xcode Debug build passed;
- universal Xcode Release build passed; and
- Xcode Debug static analysis passed.

The regression suite includes standard whole-value insertion, partial text-
field selection replacement, refusal to flatten a partially selected nonempty
text area, false setter success, a delayed host mutation within the retry
budget, exact content/caret evidence, uncertain-result presentation, diagnostic
persistence, and model-level command/dictation separation.

## Bundle verification

The checked Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 13
LSUIElement = true
architectures = x86_64 arm64
executable SHA-256 = a1b8e4cc681ecff5c595948180291fb5994b84d1bfd722b69d853f9650518eff
```

Strict signature verification passed. Release entitlements still contained only
`com.apple.security.device.audio-input`; this change adds no entitlement,
networking, Automation/Apple Events, Screen Recording, or raw-input permission.
Installer syntax validation also passed.

The explicit checked install reported:

```text
Successfully reset Accessibility approval status for dev.topher.app
Installed and launched Topher 0.4.0 (13) with one active process.
```

A separate installed-product check confirmed Build 13, universal architecture,
the same executable hash and designated requirement as the checked Release
product, a valid strict signature, and exactly one
`/Applications/Topher.app/Contents/MacOS/Topher` process.

## Remaining live acceptance

Automated seams cannot prove how each third-party app exposes its live
Accessibility element. After installing Build 13 and explicitly approving the
new ad-hoc identity, test the empty ChatGPT/Codex composer, an empty Notion
block, Chrome search and normal form fields, Notes, selection replacement, a
nonempty rich/multiline editor, and a secure field. Compare visible behavior
with the fixed method, verification, and target-role diagnostic summary.

Live compatibility, host-native undo behavior for whole-value mutation,
IME/non-Latin composition, rich-text preservation, and repeated-session
acceptance remain unverified. This checkpoint is code and design evidence, not
a claim of Wispr-style compatibility.
