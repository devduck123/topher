# 0017: Add bounded contextual evidence to the fast dictation tier

- Status: accepted
- Date: 2026-07-16
- Extends: decisions 0015 and 0016

## Context

Build 13 dogfooding showed four distinct gaps. “Search Chrome for Ball is Life”
kept “Chrome for” in the Google query. ChatGPT/Codex accepted whole-value
insertion while empty but its selected-text setter became a no-op once the
composer contained text. Apple punctuation split a brief human pause into
“. And” even when the user intended one sentence. “UI slash UX” remained
literal, and dictation ignored the alternative hypotheses already available to
assistant commands and the recognizer's personal vocabulary.

Broad grammar rewriting, application allowlists, a blanket whole-document
rewrite, synthetic paste, or an LLM on every key-up would improve coverage at
the cost of authority, semantic risk, privacy, or latency. The observed cases
have narrower evidence that can stay inside the deterministic fast tier.

## Decision

Topher makes five bounded changes:

1. Browser-qualified search grammar strips “Chrome for” and maps the remaining
   value to the existing typed Google-search capability.
2. Dictation may select an Apple alternative only when it is uniquely
   equivalent to replacing one configured spoken form with its canonical
   built-in or personal-vocabulary term. It does not generally rank alternatives
   or change unrelated prose. If an alternative is selected, timing evidence
   tied to the primary text is discarded.
3. The Apple transcriber requests audio-time attributes. Topher converts them
   immediately into bounded pause durations and UTF-16 boundaries, never logs
   or persists them, and uses them only to remove a period before “And” when the
   pause is at most 700 ms and the following word is in a small fixed
   continuation allowlist such as `dictate`, `also`, or `continue`. Without
   matching timing and vocabulary, punctuation is preserved.
4. Spoken `slash` becomes `/` only between compact uppercase developer tokens
   of at most twelve characters, such as `UI` and `UX`. Literal lowercase prose
   remains unchanged.
5. A whole-value append is permitted at an empty selection only when the target
   is a writable text area below a web-area ancestor, the caret is exactly at
   the end, the existing value is nonempty and at most 4,096 UTF-16 units, and
   it contains neither a newline nor an object-replacement character. Native,
   multiline, object-bearing, oversized, and mid-value targets retain the
   previous refusal. Topher still chooses exactly one mutation, revalidates the
   target, and requires exact content/caret readback. Ambiguous readback uses
   10, 20, 40, and 80 ms waits; immediate success remains immediate.

Raw and interpreted dictation remain distinct in the bounded developer trace,
with fixed reasons for speech alternative, short-pause join, spoken punctuation,
or repeated-speech cleanup. Audio timing and the full alternative list never
enter diagnostics.

## Consequences

- The observed Chrome query and developer punctuation are deterministic fixes.
- Personal vocabulary now affects dictation only with corroborating Apple
  alternative evidence, reducing false corrections.
- Nonempty short ChatGPT/Codex-style composers gain a standards-based path
  without clipboard mutation or raw key synthesis.
- Notion and other delayed hosts have up to 150 ms to expose readback, but a
  successful immediate insertion adds no wait.
- Rich, multiline, long, or structurally ambiguous editors still fall back.
  Live third-party compatibility and semantic accuracy remain acceptance gates.

## Rejected alternatives

- Rewrite every writable nonempty text area: rejected because it can flatten
  rich text, composition, mentions, or document structure.
- Try selected text and then whole value in one request: rejected because a
  delayed first mutation could duplicate text.
- Automatically paste through the clipboard: rejected because it expands
  shared-state and synthetic-input authority.
- Remove every “. And” or replace every spoken “slash”: rejected because both
  change legitimate prose without sufficient evidence.
- Choose the most confident alternative generally: rejected because aggregate
  confidence is not token-level semantic proof.
