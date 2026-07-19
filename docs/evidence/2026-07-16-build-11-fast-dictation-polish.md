# Build 11 fast dictation-polish evidence

Date: 2026-07-16

## Scope

Build 11 adds a deliberately narrow speed-first polish layer to finalized
focused-field dictation:

- synchronous, linear-time local removal of high-confidence adjacent one- to
  three-word restarts when a following word makes the repetition non-terminal;
- conservative preservation of punctuation/newline boundaries, terminal and
  common intentional repetition, numbers, single-letter ambiguity, and all-caps
  acronyms;
- a persisted **Clean repeated speech** switch that defaults on and provides a
  presentation-only path when disabled;
- presentation-only recovery of incomplete partial text;
- raw-versus-polished bounded diagnostics with a fixed cleanup reason and a
  distinct feedback reason for an unremoved stutter or filler;
- two sanitized manual cases covering removable and intentional repetition; and
- an explicit architecture contract for a separately optional future smart
  tier with deadline fallback and no implicit screen-context authority.

No filler removal, grammar/tone rewriting, invented punctuation, model call,
network request, new permission, or new entitlement was added. The decision is
recorded in
[decision 0016](../decisions/0016-layer-dictation-polish-under-a-latency-budget.md).

## Automated verification

The complete suite passed normally and under Thread Sanitizer:

```text
Executed 223 tests, with 0 failures (0 unexpected)
Executed 223 tests under Thread Sanitizer, with 0 failures (0 unexpected)
```

New coverage verifies single- and multiword restart removal, repeated stutter
collapse, preserved intentional and ambiguous repetition, punctuation/newline,
number and acronym safeguards, a 4,000-word pathological repeated chain,
presentation-only mode, persisted opt-out, model-level insertion,
raw-versus-polished diagnostics, and unpolished partial recovery.

Additional gates passed:

- dependency parity;
- Ruby syntax for all four diagnostic/dogfood scripts;
- validation and dictation-mode listing of all 18 sanitized dogfood cases;
- observed-query exporter regression tests, including polish-reason aggregation;
- strict recursive Swift formatting lint;
- `git diff --check`;
- bounded repository credential-pattern scan with no match;
- Xcode Debug build;
- universal Xcode Release build; and
- Xcode Debug static analysis.

## Release-bundle and installation verification

The Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 11
LSUIElement = true
architectures = x86_64 arm64
executable SHA-256 = 5b3c672472168e7b6c9a3f250ffd968d3ef0160779bd2e10168b9d806346058e
```

Strict deep signature validation passed. Release entitlements still contained
only:

```text
com.apple.security.device.audio-input = true
```

The checked installer replaced `/Applications/Topher.app`, revalidated the
source, staging, and installed bundles, launched it, and reported one active
process. A separate check confirmed installed build `11`, the same executable
hash, a valid strict signature, and exactly one installed Topher process.

## Remaining live and measured acceptance

The deterministic corpus proves bounded behavior, not the user's actual speech
or the Apple engine's recognition of a stutter. Build 11 still needs manual
dictation checks in Notes and Chrome for:

- a natural spoken restart that should be removed;
- intentional repetition that must remain;
- the presentation-only switch and persistence across relaunch;
- raw-versus-polished diagnostics and the new feedback reason;
- perceived key-up-to-insertion responsiveness; and
- the broader app, permission, long-session, route-change, and sleep/wake matrix
  carried forward from Builds 9 and 10.

The fast-tier p95 10 ms maximum-length budget and all recognition, disfluency
precision/recall, and end-to-end latency thresholds remain unmeasured. This
checkpoint is not evidence that Topher matches Wispr Flow, Willow, or any other
product's accuracy, formatting, or latency.
