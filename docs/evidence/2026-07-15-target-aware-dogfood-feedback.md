# Target-aware dogfood follow-up evidence

Date: 2026-07-15

## Observed input

The retained local dogfood trace contained 29 voice requests from earlier
builds: 17 fixed capability-success outcomes and 12 unsupported outcomes. Two
records used a safe interpreted transcript. Thirteen newer records carried the
voice-stage metrics added in build 4.

The trace did not contain user correctness ratings, so capability success could
not establish either transcription accuracy or semantic action correctness.
This is the measurement gap addressed by build 5; no accuracy percentage is
claimed from the existing records.

## Build 5 behavior

- Added allowlisted Notes and Gmail targets.
- Added Chrome Extensions as a fixed browser-owned route launched through the
  installed Chrome application.
- Added target-specific Google and YouTube query phrasing, including “Open
  YouTube for dining with Derek.”
- Added typed unsupported reasons for missing values, unknown targets,
  unsupported target actions, context-dependent requests, unsupported phrasing,
  and compound requests.
- Rejects independently executable multiple actions while preserving ordinary
  queries containing “and.” A three-clause regression prevents a leading search
  from swallowing later actions as query text.
- Added independent local transcript-accuracy and action-correctness ratings to
  retained requests. Only voice requests show the transcript rating.
- Added a metadata-only summary script that reports aggregate outcomes, ratings,
  interpretation count, and timing percentiles without printing command text.

## Automated verification

- `xcrun swift-format lint --strict -r Package.swift Sources Tests`
- `swift test`: 142 tests, 0 failures
- `swift test --sanitize=thread`: 142 tests, 0 failures after the final
  context-classification correction
- Focused resolver regression suite: 19 tests, 0 failures after the final
  multi-action hardening
- Synthetic summary fixture: retained both positive and negative Boolean
  ratings and reported the expected 50% transcript/action results
- Existing 29-record local file: summary completed without printing transcript
  text and remained compatible with records that predate the new optional keys
- Dependency parity, strict Swift formatting, `git diff --check`, Ruby syntax,
  and a repository credential-pattern scan passed.
- Unsigned universal Release build succeeded; the executable contains `arm64`
  and `x86_64`.
- Xcode Release static analysis succeeded.
- Signed arm64 Release `0.3.0 (5)` passed deep strict signature validation with
  only the audio-input entitlement.
- The exact validated executable was installed in `/Applications` with matching
  SHA-256
  `411376504ff8078b15aa66aad79eb1c63f6350bed9844164783ffd29d5248a49`.
- The installed UI-element app launched and remained alive as PID 99932.

## Remaining measured gates

This build instruments ordinary dogfooding; it does not complete the controlled
speech benchmark. Word error rate, named/developer-term accuracy, room-noise
behavior, 100-session reliability, sleep/wake recovery, and comparative engine
selection remain open until the consented corpus is run.
