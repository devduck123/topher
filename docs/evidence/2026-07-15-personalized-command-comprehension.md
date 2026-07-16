# Personalized command comprehension verification

Date: 2026-07-15

This record covers the first target-aware language and personalized speech
interpretation slice. It records automated evidence only; recognition quality
still requires the physical-microphone corpus in `docs/speech-benchmark.md`.

## Implemented behavior

- Exact known website brands are resolved before native application names.
  “Open Crunchyroll,” “Search Crunchyroll,” and “Search for Crunchyroll” open
  the allowlisted Crunchyroll homepage. GitHub and YouTube use the same
  target-specific navigation rule.
- Query-bearing generic searches, such as “Search Crunchyroll anime releases”
  or “Search Chrome extensions,” remain Google searches. Provider-specific
  requests, such as “Search YouTube for Swift concurrency,” remain YouTube
  searches.
- The system default browser performs web navigation. Topher does not acquire
  browser-control authority merely to open a destination or search URL.
- Apple Speech alternatives and primary confidence can flow through capture
  without persisting the complete alternative list.
- A bounded local developer vocabulary and user-editable personal vocabulary
  are supplied to on-device speech as fail-soft context and to a pure transcript
  interpreter.
- A correction is executable only when it resolves through the existing typed
  command allowlist. If the raw transcript already resolves, a correction must
  preserve its application target, website target, or search provider.
- Local rolling diagnostics retain bounded raw and interpreted transcripts, a
  fixed interpretation reason, and primary confidence. Diagnostics remain
  clearable and can be explicitly disabled.

## Automated verification

- Dependency parity passed for KeyboardShortcuts 3.0.1 across SwiftPM, Xcode,
  and both lockfiles.
- Strict recursive `swift-format` lint and `git diff --check` passed.
- `swift test` passed 128 tests with zero failures.
- The same 128 tests passed under Thread Sanitizer with no reported data race.
- An unsigned universal arm64/x86_64 Release app build succeeded.
- Debug `xcodebuild analyze` succeeded. Xcode emitted only the existing
  App Intents metadata warning because Topher does not link AppIntents.
- A targeted credential-term scan found no credential-like terms in source,
  tests, package/project configuration, scripts, or CI.

Tests cover target-specific bare-search behavior, query preservation, known
developer-term corrections, personal vocabulary, whole-phrase boundaries,
ambiguous alternatives, same-authority enforcement, persisted-input
sanitation, bounded diagnostics, and exactly-once capability execution.

## Deferred interactive acceptance

The automated suite does not prove that Apple Speech will distinguish terms
such as GitHub, GitLab, npm, pnpm, TypeScript, or Crunchyroll with Wispr-like
accuracy on the repository owner's microphone and speaking style. Run the
40–60 phrase corpus in `docs/speech-benchmark.md` from another focused app,
then compare raw transcript, interpreted transcript, confidence, execution,
latency, and false-positive rates. Keep complete audio and recognition
alternatives out of diagnostics.

Chrome tab inspection, page/feed understanding, screen context, arbitrary
website discovery, and model-backed intent planning remain separate authority
and implementation milestones; this slice does not imply those capabilities.
