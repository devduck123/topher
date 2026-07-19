# 0021: Combine semantic signals and bound Notion caret insertion

- Status: accepted
- Date: 2026-07-18

## Context

Build 17 dogfooding found the correct system-wide Codex/ChatGPT text area on
every attempt, but the host ignored selected-text mutation. The existing
semantic fallback then returned authored content as soon as
`AXNumberOfCharacters` was positive. That was safe, but it prevented the code
from checking whether Chromium's full text-marker range still described an
empty logical editor. The current Codex desktop app also exposes the visible
`Ask for follow-up changes` suggestion as ordinary value text without
`AXIsSuggestion` or placeholder metadata.

The same run confirmed a separate Notion boundary: verified whole-value append
worked at the end of a plain block, while selected-text mutation at the start or
middle was ignored. Treating every web caret as a whole-value target would risk
flattening rich or multi-block content.

## Decision

For Codex/ChatGPT only, Topher evaluates suggestion attribution, character
count, full web text-marker length/string, and an app-owned known-suggestion
classification as separate fixed signals. A positive character count does not
short-circuit an empty full marker range. The exact observed suggestion is a
second bounded compatibility proof when native suggestion metadata is absent.
It is accepted only for the fixed Codex/ChatGPT application family, an entire
value no longer than 128 UTF-16 units, the exact trimmed suggestion string, a
zero-length caret at the start, no marked or mixed content, and unchanged
semantic evidence immediately before mutation.

Topher writes the transcript alone through one whole-value mutation and requires
exact content readback plus post-write authored-content evidence. Ordinary
authored text, partial matches, changed signals, invalid markers or character
counts, marked text, mixed suggestion/content, and unsupported application
families fail closed.

For Notion only, Topher may use the existing bounded plain web-value adapter at
a zero-length start or middle caret when the value is single-line, at most 4,096
UTF-16 units, object-free, uniformly presented, unchanged, and not placeholder
backed. It reconstructs the complete value with contextual spacing, revalidates
the role, value, web ancestry, attributes, placeholder state, selection, focus,
and process, then requires exact readback. Multiline values, partial selections,
links, mentions, lists, attachments, styling, mixed presentation, and unknown
attributes remain unsupported.

Developer diagnostics retain only the fixed semantic decision and individual
signal states. They do not retain the composer value or suggestion text beyond
the existing bounded user-authored transcript record.

## Consequences

- Codex's currently observed empty-composer suggestion can be replaced without
  appending suggestion copy to the dictated text.
- A user-authored value exactly equal to the known UI suggestion is inherently
  ambiguous. The collision is reduced, not eliminated, by the exact app, value,
  length, caret, unchanged-state, and verification requirements.
- Plain single-line Notion insertion can work at start, middle, and end without
  generalizing whole-value mutation to rich blocks.
- Host UI copy or Accessibility changes may return these surfaces to the
  explicit review/copy fallback; compatibility never widens automatically.

## Rejected alternatives

- Trust positive character count before text-marker evidence: rejected because
  current Chromium suggestion chrome can contribute to that count.
- Replace every Codex caret-at-start value: rejected because authored content
  would be overwritten.
- Pattern-match arbitrary placeholder-like prose: rejected because it would
  expand the collision set and vary across user content.
- Allow Notion whole-value mutation for multiline or rich blocks: rejected
  because exact string readback does not prove formatting and block structure
  survived.
- Add pasteboard or synthesized-key fallback: rejected because it broadens
  global side effects and does not provide the same target verification.

## Relationship to earlier decisions

This decision supersedes decision 0020's requirement that character count and
text-marker length must both be zero. It preserves that decision's process
binding, revalidation, authored-content refusal, Terminal fallback, and
exactly-one-mutation requirements. It extends decision 0019's plain web adapter
only for the narrowly bounded Notion single-line caret case.
