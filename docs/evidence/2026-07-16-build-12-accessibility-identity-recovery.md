# Build 12 Accessibility-identity recovery evidence

Date: 2026-07-16

## Trigger and diagnosis

Dogfooding showed macOS Accessibility Settings listing Topher as enabled while
Topher's live `AXIsProcessTrusted()` check remained false and the system prompt
reappeared. Disabling and re-enabling the visible toggle did not recover it.

The installed Release bundle was ad-hoc signed with no team identifier. Its
designated requirement was tied to the Build 11 universal binary's two code
hashes. The checked Build 12 Release had a different pair of code hashes. This
confirmed that the current executable could not satisfy the old ad-hoc code
requirement even though System Settings retained a visually enabled Topher row.
`security find-identity -v -p codesigning` reported no available stable code-
signing identity on this Mac.

## Change

- The checked installer compares the installed and incoming designated code
  requirements and warns when they differ.
- The installer accepts `--reset-accessibility` as an explicit operation. It
  validates the exact `dev.topher.app` bundle identifier and runs
  `tccutil reset Accessibility dev.topher.app` only when that flag is present.
  Normal installation never changes TCC state.
- Topher's denial UI explains that an already-enabled stale row must be removed
  with the **−** button after quitting Topher, followed by relaunch and fresh
  approval. Repeatedly toggling the stale row is no longer the only guidance.
- Contributor and agent guidance identify stable Apple Development signing as
  the durable development solution. The project remains ad-hoc signed because
  no suitable identity exists on this Mac.

No permission was granted programmatically. Reset removes Topher's existing
decision and macOS still requires explicit user approval.

## Automated verification

- dependency parity passed;
- the 18-case sanitized dogfood corpus and exporter regression tests passed;
- strict Swift formatting and `git diff --check` passed;
- installer `zsh -n` syntax validation passed;
- all 223 tests passed normally;
- all 223 tests passed under Thread Sanitizer with no sanitizer report;
- Xcode Debug build passed;
- universal Xcode Release build passed; and
- Xcode Debug static analysis passed.

## Bundle, reset, and installation verification

The Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 12
LSUIElement = true
architectures = x86_64 arm64
executable SHA-256 = 5c180fa5c62698a08cd080b2d5d6f59db281d9b37d6a29f45fc36e1c1ab5593d
```

Strict signature verification passed, and Release entitlements still contained
only `com.apple.security.device.audio-input`.

The explicit checked install reported:

```text
Successfully reset Accessibility approval status for dev.topher.app
Installed and launched Topher 0.4.0 (12) with one active process.
```

A separate installed-product check confirmed build `12`, the same executable
hash and designated requirement as the checked Release product, a valid strict
signature, and exactly one `/Applications/Topher.app` process.

## Remaining live acceptance

The reset is verified, but macOS intentionally requires the user to approve the
new Topher row. Complete the live gate by using **Enable** or the dictation hold,
turning on the newly created Accessibility entry, returning to the target app,
and confirming Topher changes to **Global text insertion ready** and inserts
dictation. Relaunch once to verify the grant remains valid for this unchanged
Build 12 binary.

Because future ad-hoc rebuilds will change the requirement again, persistent
permission testing across builds remains blocked on creating or selecting a
stable Apple Development signing identity.
