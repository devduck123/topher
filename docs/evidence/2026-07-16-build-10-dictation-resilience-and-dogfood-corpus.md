# Build 10 dictation-resilience and dogfood-corpus evidence

Date: 2026-07-16

## Scope

Build 10 hardens the Build 9 dictation foundation after dogfooding exposed
whole-utterance loss at the capture limit. It also turns observed requests into
a deliberate testing workflow. The slice includes:

- 30-second assistant and 120-second dictation maximum holds that automatically
  finalize instead of canceling and discarding recognized text;
- a physical-release gate that prevents a timer-driven finalization and late
  key-up from completing twice;
- review-only recovery of usable partial text after stream/finalization failure,
  with no command execution or focused-field insertion;
- secure-target rejection for recovered dictation and content-free persisted
  capture-failure records;
- typed insertion, capture, and incorrect-action reasons plus automatic-
  finalization metadata in local diagnostics;
- visible warning when no dictation shortcut is configured;
- natural observed YouTube query forms, explicit dictation-mode guidance, and a
  canonical eBay website target;
- a 16-case sanitized manual corpus checked by CI; and
- an explicit, bounded, owner-only private observed-query exporter that excludes
  dictation by default and never runs from the app.

The architecture and data-retention choices are recorded in
[decision 0014](../decisions/0014-bounded-dictation-recovery-and-dogfood-corpora.md).

## Automated verification

The complete normal suite passed:

```text
Executed 217 tests, with 0 failures (0 unexpected)
```

The same 217 tests passed under Thread Sanitizer with no sanitizer report.
Coverage added in this slice includes timer-driven finalization, retained
physical-key ownership, late key-up exactly-once behavior, model-level dictation
insertion after the maximum, preview-only partial recovery, secure recovery
refusal, content-free failure diagnostics, schema-compatible typed metadata,
incorrect-action reason lifecycle, observed YouTube wording, eBay resolution,
and assistant-to-dictation recovery guidance.

Additional gates passed:

- strict Swift formatting lint;
- Ruby syntax checks for all three dogfood/diagnostic scripts;
- dependency parity validation;
- validation and filtered listing of all 16 public dogfood cases;
- repeatable exporter tests for default exclusion, idempotence, typed metadata,
  explicit dictation inclusion, POSIX modes, and symlink rejection;
- private corpus export and repeat-import check: 68 distinct command phrases,
  92 observations, 94 imported record IDs, no dictation;
- private corpus storage checks: gitignored, `0700` directories, `0600` file;
- `git diff --check`;
- a bounded repository credential-pattern scan with no match;
- Xcode Debug build;
- universal Xcode Release build; and
- Xcode Debug static analysis.

No raw observed phrase is included in this evidence record.

## Release-bundle verification

The Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 10
LSUIElement = true
architectures = x86_64 arm64
executable SHA-256 = 66572e718c181a18650699c18c04107823ed974b7521dc05d41165be229ebe01
```

Strict deep signature validation passed. Release entitlements still contained
only:

```text
com.apple.security.device.audio-input = true
```

No Screen Recording, Automation/Apple Events, direct network, App Sandbox, or
new signing entitlement was added. Release remains a local ad-hoc Hardened
Runtime build; this is not distribution or notarization evidence.

## Remaining live acceptance

Automated validation proves bounded state transitions and packaging, not real
speech accuracy or editor behavior. Build 10 still needs interactive checks for:

- a normal short dictation in Notes and Chrome;
- a real hold beyond two minutes that preserves and inserts or previews text
  once, followed by a late key-up with no duplicate;
- assistant and dictation stream failures on real audio/device transitions;
- recovered-text UI clarity and secure-field non-retention;
- the warning and recovery flow when the dictation shortcut is unset;
- the new eBay and YouTube phrase variants through real speech; and
- the broader native/browser/editor/chat compatibility and permission matrix
  already listed in the Build 9 evidence.

The 68-phrase private dataset helps choose future manual cases, but it is not a
controlled accuracy benchmark and observed success is not the product
specification. Only reviewed, sanitized phrases should move into the public
manual corpus.
