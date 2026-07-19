# Build 14 bounded contextual dictation follow-up evidence

Date: 2026-07-16

## Trigger

Build 13 dogfooding found that “Search Chrome for Ball is Life” searched for
“Chrome for Ballislife,” a third dictation could not append to an already
nonempty ChatGPT/Codex composer, a short human pause became an unwanted
“. And” sentence split, and `UI slash UX` remained literal. The user remained
happy with speed and asked to improve accuracy without making the system
unnecessarily complex.

## Change

- Strip bounded Chrome-search qualifiers before creating the typed Google
  query. No provider or free URL is inferred from dictation.
- Carry Apple alternative hypotheses into a dictation-only selector. It accepts
  one only when it uniquely equals a configured built-in or personal-vocabulary
  spoken-form correction; unrelated prose changes are rejected.
- Request Apple audio-time attributes and convert them transiently into pause
  boundaries. A fixed rule joins only a pause at most 700 ms before an
  “And” continuation whose next word is in a small fixed continuation allowlist.
  Timing and full alternatives are never persisted.
- Convert spoken `slash` only between compact uppercase developer tokens such
  as `UI` and `UX`, with a typed diagnostic change reason.
- Permit one append-only whole-value mutation for a single-line, object-free,
  web-descendant text area of at most 4,096 UTF-16 units when the caret is
  exactly at the end. Multiline, object-bearing, native rich, oversized, and
  mid-value surfaces retain the previous refusal.
- Verify immediate success without waiting; otherwise poll after 10, 20, 40,
  and 80 ms before classifying a readable unchanged mutation. No second
  mutation, clipboard write, synthetic key, Return, submission, or send was
  added.
- Add four sanitized acceptance cases for the observed Chrome qualifier,
  nonempty composer, short pause, and spoken slash scenarios.

The architecture tradeoff is recorded in
[decision 0018](../decisions/0018-bounded-contextual-dictation-followup.md).

## Automated verification

- dependency parity passed;
- the 24-case sanitized dogfood corpus and observed-query exporter tests passed;
- strict Swift formatting, Xcode-project plist validation, and
  `git diff --check` passed;
- all 244 tests passed normally;
- all 244 tests passed under Thread Sanitizer with no sanitizer report;
- Xcode Debug build passed;
- universal Xcode Release build passed; and
- Xcode Debug static analysis passed.

Regression coverage includes browser-qualified search parsing; conservative
spoken slash and timed pause joining; long-pause and new-sentence preservation;
built-in and personal-vocabulary alternatives; rejection of unrelated
alternatives; direct Apple attributed-time extraction; pause propagation across
speech results; model-level dictation selection; bounded nonempty web-composer
append; native/multiline refusal; delayed-host verification; punctuation-boundary
spacing; and existing command/dictation separation.

## Bundle verification

The checked and installed Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 14
LSUIElement = true
architectures = x86_64 arm64
executable SHA-256 = 1c07ca76e75e3742763a924a7a4e694cffdf7625ae57af9b00d97e28ddcb9d97
```

Strict signature verification passed. Release entitlements still contain only
`com.apple.security.device.audio-input`; this change adds no entitlement,
networking, Automation/Apple Events, Screen Recording, clipboard automation, or
raw-input permission.

The checked install explicitly reset only Topher's Accessibility decision,
installed `/Applications/Topher.app`, launched it, and found exactly one
`/Applications/Topher.app/Contents/MacOS/Topher` process. The installed bundle
matched the checked Release version, universal architectures, strict signature,
and executable hash.

## Remaining live acceptance

The Accessibility reset intentionally requires the user to approve Build 14
again. Automated seams cannot prove how the current ChatGPT/Codex, Notion, or
Chrome versions expose and delay their live Accessibility elements, nor can
synthetic attributed text prove Apple's timing granularity for the user's voice.

Manually test the 24-case corpus, prioritizing: the Chrome-qualified search;
two consecutive dictations into the same ChatGPT/Codex composer; a short versus
deliberately long pause before “And”; `UI slash UX`; a personal vocabulary term
with a known spoken form; delayed Notion insertion; and multiline/rich refusal.
Live cross-app compatibility, semantic false-positive rate, real latency, IME
composition, and long-session stability remain unverified. This is not yet a
claim of Wispr-style accuracy or universal editor compatibility.
