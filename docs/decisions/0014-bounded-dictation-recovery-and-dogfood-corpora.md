# 0014: Finalize bounded holds and separate public from private dogfood corpora

- Status: accepted
- Date: 2026-07-16

## Context

Build 9 treated the 30-second hold limit as a failure and canceled capture. A
real two-minute dictation test exposed the consequence: once the limit was
reached Topher discarded the entire transcript instead of inserting or
previewing the text already recognized. Capture streams can also fail after
producing a useful partial. Executing or inserting that partial would be unsafe,
but losing it without a review path is unnecessarily destructive.

Dogfooding also produced two different data needs. Contributors need a public,
repeatable list of representative phrases and expected behavior. The developer
also needs a private inventory of what was actually tried so unsupported
language and personal terminology are not forgotten. Treating either dataset as
the other would leak private speech or make the shared corpus an unreviewed log.

## Decision

Maximum hold duration is a finalization boundary rather than a cancellation:

1. Assistant commands automatically finalize after 30 seconds; dictation uses
   a 120-second maximum suited to natural prose.
2. Automatic finalization keeps the shortcut physically held until key-up. A
   late key-up cannot finalize, execute, or insert a second time, and a held key
   cannot begin another request.
3. The existing eight-second finalization watchdog remains a genuine failure
   boundary.
4. If a result-stream or finalization failure leaves a usable partial, assistant
   text returns to the manual development field and dictation text to the local
   pending preview. A partial is never resolved, executed, or inserted.
5. A secure or newly secure dictation target discards recovered text. The
   developer trace persists only a fixed capture-failure reason and an empty
   transcript for partial-recovery failures.

Dogfood data is split by purpose:

1. `dogfood/manual-corpus.json` is sanitized, reviewed, schema-checked, and
   committed. It contains explicit mode, setup, expected status/result, and
   human checks.
2. `.topher-local/dogfood/observed-queries.json` is a developer-created durable
   plaintext export of the bounded trace. It is gitignored, excludes dictation
   by default, merges repeated phrases, deduplicates imported record IDs, uses
   owner-only paths, and enforces entry, phrase, and file bounds.
3. Topher never creates the observed-query corpus automatically. The developer
   explicitly exports and deletes it. Only reviewed and sanitized cases may be
   promoted into the public corpus.

Diagnostics identify automatic finalization, fixed capture and dictation
failure reasons, and optional fixed issue tags after a user rates an action
incorrect. Detailed framework errors and recovered partial content remain out
of persisted diagnostics.

## Consequences

- Long dictation is bounded without turning the bound into data loss.
- Recovery favors user review while preserving the no-effect rule for uncertain
  final text.
- Assistant and dictation durations can evolve independently without splitting
  the shared capture controller.
- The physical-release gate remains part of exactly-once execution, including
  after timer-driven finalization.
- The shared corpus is useful to humans and future agents without publishing
  raw dogfood history.
- The private corpus persists beyond the rolling trace and therefore requires
  intentional deletion; local and gitignored do not mean encrypted.

## Rejected alternatives

- Cancel and discard at the maximum: rejected because the maximum is a resource
  bound, not evidence that already recognized text is invalid.
- Insert or execute the last partial after a stream failure: rejected because a
  partial may be unstable or incomplete.
- Reuse the 30-second command limit for dictation: rejected because normal prose
  and multi-paragraph input need a materially larger but still finite window.
- Automatically export every trace record: rejected because it silently creates
  a second durable content sink and defeats rolling retention expectations.
- Commit observed phrases directly: rejected because raw commands and dictation
  can contain private queries, credentials, document text, or personal context.
