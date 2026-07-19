# 0020: Require semantic evidence for nonempty web-composer append

Date: 2026-07-16

Status: Accepted; live third-party acceptance pending

Supersedes decision 0019's permission to rewrite a nonempty web-composer value
at any valid selection. Its exactly-one-mutation, bounded-readback, ancestry,
size, and object-refusal requirements remain in force.

## Context

Build 15 live testing showed that structural plainness is not enough to prove
that an Accessibility value is user-authored draft text. A visually empty Codex
composer exposed suggestion text as a short, writable, uniformly attributed
`AXValue` with a caret at zero. Topher prepended the correct transcript to that
value and then verified the mechanically correct but semantically wrong result.

The same test session showed the opposite compatibility problem in Notion. Its
selected-text setter produced no observable mutation, while the whole-value
adapter rejected an existing plain block because the attributed value exposed
more metadata than one font-only run. Relaxing all attributed content would risk
flattening links, mentions, attachments, lists, or authored formatting.

## Decision

For a nonempty web-descendant text area, Topher may choose one standard
whole-value mutation only when all existing bounds and revalidation checks pass
and all of the following semantic evidence is present:

1. The selected range is an empty caret exactly at the end of the complete
   value. Start, middle, and partial selections are ambiguous and do not qualify.
2. A standard `AXPlaceholderValue` does not equal the complete value.
3. Every attributed run contains only a normal font plus optional foreground,
   background, natural-language, spelling, marked-spelling, or autocorrection
   metadata.
4. Font and presentation metadata are identical across runs. Spellcheck metadata
   may vary because it is transient and host-recomputed.
5. No run contains a styled font, link, attachment, replacement string, list
   marker, underline, strike, unknown attribute, or other semantic marker.

The same placeholder state and attributed classification must still hold
immediately before mutation. Empty text areas, writable text fields, and explicit
full-value replacement retain their existing separate decisions. Topher never
tries a second mutation after a selected-text no-op.

The bounded local developer trace may retain fixed structural evidence and one
fixed target-application family: Chrome, Codex/ChatGPT, Notion, Notes, Safari,
other, or unknown. It does not retain the raw bundle identifier, process ID,
window title, URL, selection, additional field value, attributed content, or
native error.

## Consequences

- The observed Codex suggestion cannot be incorporated through the web
  whole-value adapter; it falls back for explicit review if the standard
  selected-text path also no-ops.
- A short plain Notion block may qualify for a verified end append when its
  additional runs are only uniform presentation or spellcheck metadata.
- Mid-draft and partial-selection web whole-value insertion are intentionally
  unsupported until a structured editor operation can prove the user-authored
  range independently of the host's aggregate value.
- Compatibility evidence becomes attributable to a bounded app family without
  persisting arbitrary application identifiers or more editor content.
- All classification work remains local, synchronous, bounded by the existing
  4,096-UTF-16 web value limit, and adds no model or network latency.

## Rejected alternatives

- Treat exact readback as semantic proof: rejected because Build 15 verified the
  wrong expected value after incorporating Codex suggestion text.
- Special-case a Codex suggestion string: rejected because UI copy is unstable,
  localized, and not an authorization boundary.
- Allow every Notion or Codex value by bundle identifier: rejected because app
  identity does not prove that the focused field is plain or safe to rewrite.
- Retry with whole-value mutation after selected text no-ops: rejected because a
  delayed first mutation could duplicate externally visible text.
- Restore arbitrary mid-value whole-value writes: rejected until a public,
  structured editor contract can distinguish user draft text from host UI text.
