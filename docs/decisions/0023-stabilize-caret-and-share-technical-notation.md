# 0023: Stabilize caret and share technical notation

- Status: accepted
- Date: 2026-07-19

## Context

Build 18 dogfooding proved that the bounded whole-value adapters could insert
into the current Codex and Notion surfaces, but exposed three distinct gaps.
Codex accepted the value while leaving the caret at the beginning, a punctuated
Notion prepend joined directly to the following word, and an assistant-command
web search preserved `UI slash UX` even though dictation normalized the same
strong technical tokens to `UI/UX`.

The same session confirmed that authored Codex start/middle content remains an
ambiguous or structured editing surface. Its selected-text Accessibility setter
reported availability but produced no observable mutation. Widening the
whole-value adapter there could overwrite or flatten authored content.

## Decision

After exactly one permitted whole-value mutation and exact content readback,
Topher may reassert only the expected zero-length caret. Every attempt remains
bounded by the existing verification deadline and repeats focus, process, and
secure-field checks. A successful setter response is not proof: Topher waits
and requires stable caret readback. It never repeats the value mutation.

Insertion-boundary composition inserts a separator before existing word-like
text when the dictated text ends in a word, sentence-boundary punctuation, or a
closing delimiter. It does not add whitespace before punctuation or otherwise
rewrite the transcript.

The strong-token spoken-slash normalizer is one TopherCore operation shared by
dictation and extracted web-search payloads. It remains limited to short
uppercase technical tokens such as `UI slash UX`; lowercase prose remains
literal. Diagnostics retain the original request transcript.

Observed `Kodex` → `Codex` and `impending` → `prepending` dictation corrections
are accepted only when one Apple alternative explains the complete lexical
difference through the existing vocabulary-equivalence gate. The primary
transcript is preserved when corroboration is absent, conflicting, or changes
unrelated prose.

Authored or ambiguous Codex start/middle content continues to fail closed. The
review/copy fallback now explains that Topher left the content unchanged; this
decision does not introduce pasteboard mutation, synthesized keys, browser
JavaScript, or a general rich-editor adapter.

## Consequences

- Supported whole-value editors can retain a stable post-insertion caret while
  preserving exactly-once text mutation.
- Punctuated prepends no longer concatenate with existing words.
- Dictation and web-search queries use the same narrow technical notation rule.
- Developer-term corrections improve only when Apple supplies exact evidence;
  Topher still performs no general prose reranking.
- Inline rich Codex insertion remains unsupported but fails transparently and
  without modifying existing content.

## Rejected alternatives

- Repeat the value write when the caret is wrong: rejected because a delayed
  host update could duplicate text or overwrite a newer edit.
- Trust the caret setter result immediately: rejected because Build 18 proved
  setter completion and stable host state are different facts.
- Normalize every spoken `slash`: rejected because ordinary prose and literal
  dictation would be changed.
- Apply observed homophone corrections directly to every primary transcript:
  rejected because words such as `impending` are legitimate prose.
- Use paste, synthesized keyboard input, AppleScript, or browser JavaScript for
  Codex bullets: rejected because those paths broaden authority and cannot meet
  the current target and mutation verification contract.

## Relationship to earlier decisions

This decision preserves decision 0017's verified-mutation requirement,
decision 0018's narrow spoken-notation and alternative-selection rules, and
decision 0022's Codex/Notion whole-value safety boundaries. It refines only
post-write caret stabilization, insertion composition, shared query formatting,
and fallback clarity.
