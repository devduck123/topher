# Build 7 single-instance and canonical-navigation evidence

Date: 2026-07-15

## Trigger

Build 6 dogfooding accurately transcribed Netflix, Hulu, and Amazon but rejected
the bare names as unknown targets. It also produced a plausible but potentially
wrong explicit domain. Separately, installation validation had left three app
processes subscribed to the global shortcut, so one request opened three tabs.

The Build 6 trace is valid for resolver-pattern discovery but not for tab-count,
timing, or concurrent-storage reliability claims.

## Implemented boundary

- Added fixed canonical web destinations for Amazon, Ballislife, Hulu, and
  Netflix. Unknown names never become guessed `.com` domains.
- Added observed canonical speech context and bounded corrections for Grok and
  Ballislife. Free-domain-to-known-site narrowing is voice-only; exact manual
  domains remain literal.
- Added a typed `uncertainDomain` outcome. A voice-originated unfamiliar domain
  with hypotheses resolving to multiple hosts stops before policy or browser
  execution.
- Added a per-user, nonblocking BSD file lock. Only the primary process may
  subscribe to shortcut events; secondary and unsafe lock states terminate.
- Added a random per-launch identifier to new bounded developer records.
- Added a staged local installer with signature verification, rollback on
  failure, one-process assertion, and no leftover staging bundle.

## Automated validation

- `swift test`: 161 tests passed, 0 failures.
- `swift test --sanitize=thread`: 161 tests passed, 0 failures and no Thread
  Sanitizer report.
- Focused destination, interpreter, processor, web executor, and process-lock
  regressions passed before the full runs.
- `xcrun swift-format lint --strict` passed for every changed Swift file.
- `git diff --check`, Ruby syntax, zsh syntax, and Xcode project plist syntax
  passed.
- Dependency parity passed for KeyboardShortcuts 3.0.1 across SwiftPM and Xcode
  lockfiles.
- Xcode Debug build succeeded.
- Xcode Release build succeeded.
- Xcode Release static analysis succeeded. Xcode emitted only its expected
  metadata-extraction warning because Topher does not link AppIntents.

## Final bundle and installed runtime

Artifact:

```text
/tmp/topher-build7-final-release/Build/Products/Release/Topher.app
```

- Version/build: `0.3.0 (7)`.
- Bundle identifier: `dev.topher.app`.
- `LSUIElement`: true.
- Strict deep signature verification passed.
- Release entitlements contain only
  `com.apple.security.device.audio-input = true`.
- Executable SHA-256:
  `11b9ecc8d46728a875ed43da69dc55b69769c7c236a56228cc86666c1179de9c`.
- The staged installer completed without residue. The installed executable hash
  exactly matches the artifact.
- A forced `open -n` launch and direct executable invocation both exited while
  the original installed process remained alive. Final active Topher process
  count: one.

## Remaining acceptance

This checkpoint does not claim a clean user voice corpus for Build 7. The next
dogfood pass should verify exactly one action per hold; the new canonical brands;
Grok and Ballislife transcription; unfamiliar-domain disagreement; and the
independent transcript/action ratings. Screen-aware and browser-context
requests remain outside this build.
