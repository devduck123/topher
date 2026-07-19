# Build 15 menu and web-composer recovery evidence

Date: 2026-07-16

## Trigger

Build 14 dogfooding showed two distinct regressions. The menu-bar popover could
collapse its scroll content and display only the Settings, diagnostics, and
Quit footer. Separately, fast and accurate dictation into the current Codex
composer produced no visible insertion.

The retained content-free record for Codex reported a writable text area, a
successful selected-text setter, and `notObserved` verification after the full
150 ms polling budget. A local Accessibility inspection of the focused Codex
composer found a plain ProseMirror text area with a writable standard value and
its web-area ancestor 22 parents away. The Build 14 adapter stopped at 12 and
allowed only single-line end appends.

## Change

- Give the menu panel a deterministic 380 × 460 point frame and let the main
  scroll view consume the available space above its fixed footer.
- Find a web-area ancestor with a cycle-checked walk bounded to 32 parents.
- Permit one whole-value mutation for a nonempty web text area only when its
  value is at most 4,096 UTF-16 units, contains no object-replacement character,
  and an exact full-range attributed read has one plain font-only run.
- Allow a valid caret or selection anywhere in that bounded plain value,
  including a multiline value.
- Revalidate role, value, web ancestry, and uniform attributes immediately
  before the write. A formatting or structure change fails closed without a
  mutation.
- Continue to choose exactly one standard Accessibility mutation and require
  exact bounded readback. No second setter, private mutation attribute,
  application allowlist, automatic clipboard write, synthetic key, Return,
  submission, or send was added.
- Persist and display a fixed content-free whole-value adapter decision and add
  it to the metadata-only diagnostic summary and private corpus aggregate.
- Add sanitized manual cases for multiline/mid-draft Codex insertion and rich
  web-editor refusal.

The boundary and rejected alternatives are recorded in
[decision 0019](../decisions/0019-bounded-uniform-web-composer-insertion.md).

## Automated verification

- dependency parity passed;
- the 26-case sanitized dogfood corpus and observed-query exporter tests passed;
- strict Swift formatting, Xcode-project plist validation, credential-pattern
  scan, and `git diff --check` passed;
- all 248 tests passed normally;
- all 248 tests passed under Thread Sanitizer with no sanitizer report;
- Xcode Debug build passed;
- universal Xcode Release build passed; and
- Xcode Debug static analysis passed.

Regression coverage includes deterministic menu dimensions; deep web-composer
classification through an injected depth of 22; multiline and mid-value whole-
value insertion; native, object-bearing, and mixed-format refusal; lazy
attributed-value reads; pre-write formatting revalidation; exactly one value
write; exact content/caret verification; delayed-host polling; content-free
diagnostic persistence and export; and existing secure-field, focus, selection,
command/dictation, clipboard, and submission boundaries.

## Bundle and installation verification

The checked Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 15
LSUIElement = true
architectures = x86_64 arm64
executable SHA-256 = 1c575d514d44830dc3fe42bcb5183d7bbc140dd362485ce9f0ab840a5cef0843
```

Strict signature verification passed. Release entitlements still contain only
`com.apple.security.device.audio-input`; this change adds no entitlement,
networking, Automation/Apple Events, Screen Recording, direct browser control,
clipboard automation, or raw-input permission.

The checked install reset only Topher's Accessibility decision, installed the
exact Release artifact at `/Applications/Topher.app`, launched it, and found
exactly one installed Topher process. The installed version, universal
architectures, strict signature, and executable hash match the checked product.

## Remaining live acceptance

The Accessibility reset intentionally requires explicit approval for Build 15.
Automated seams cannot prove how the user's current Codex, ChatGPT, Notion,
Chrome, or rich editors apply live mutations. Computer Use could inspect normal
application windows but the menu-only Topher scene and SystemUIServer status
item did not expose a controllable window, so the installed popover itself was
not visually certified by automation.

Prioritize these manual checks:

1. Open Topher's status item and confirm the full 380 × 460 panel appears, with
   the readiness/mode content above the footer and internal scrolling as needed.
2. Re-enable Topher under Accessibility for this exact Build 15 binary.
3. Dictate once into an empty Codex composer, then again into the same nonempty
   plain draft. Confirm each inserts once and never sends.
4. Try a short plain multiline draft with the caret in the middle. Confirm all
   existing characters and lines remain exact around the one insertion.
5. Try mixed formatting, a link, mention, or attachment. Confirm Topher leaves
   the editor unchanged and offers local review; do not use a sensitive draft.
6. Inspect local diagnostics. Supported Codex insertion should report
   `wholeValue`, verified readback, and `Plain web composer eligible`; rejected
   content should show a fixed refusal reason.

Live third-party compatibility, rich-surface preservation, IME/non-Latin text,
real latency, and repeated-session stability remain unverified. This checkpoint
does not claim universal editor compatibility or Wispr-style accuracy.
