# 0018: Permit bounded whole-value insertion for uniform web composers

Date: 2026-07-16

Status: Accepted; live third-party acceptance pending

Supersedes the web-composer restriction in decisions 0016 and 0017. Their
exactly-one-mutation and verified-readback requirements remain in force.

## Context

Build 14 dogfooding produced accurate, fast transcripts in the current Codex
composer but did not insert them. Content-free diagnostics showed that Codex's
selected-text attribute was reported writable and its setter returned success,
yet bounded readback observed no mutation. A local Accessibility inspection
then found a writable `AXTextArea` whose `AXWebArea` ancestor was 22 parents
away. The existing adapter searched only 12 ancestors and only allowed a
single-line append at the end, so it could not select the one-mutation
whole-value path for this host.

Trying a second mutation after the selected-text no-op could duplicate text in
a merely delayed host. Depending on an undocumented replacement attribute,
synthetic paste, or application-specific bundle logic would expand authority
or create a fragile private contract. A blanket whole-value rewrite could
flatten rich text, links, mentions, attachments, or editor structure.

## Decision

Topher may choose one whole-value mutation for a nonempty web text area only
when all of the following evidence is present before capture and remains true
immediately before mutation:

1. The same non-secure focused element and process, selection, selected text,
   nearby text, role, and complete value still match.
2. A cycle-checked ancestor walk finds `AXWebArea` within 32 parent steps.
3. The existing value is at most 4,096 UTF-16 units and contains no object-
   replacement character.
4. A standard attributed-string read for the complete value exactly matches
   that value, has one effective attribute run, exposes only the normal font
   attribute, and does not indicate bold, italic, or oblique styling.
5. The selected range is valid. It may be a caret or selection at any position,
   and the plain value may contain newlines.

Topher computes the replacement locally, performs exactly one standard
`AXValue` write, updates the selection if the host permits it, and reports
success only after bounded exact content readback. It does not try selected
text first, use a private parameterized mutation, synthesize keys, mutate the
clipboard, press Return, submit, or send. Whole-value insertion still does not
advertise Topher-managed undo.

The content-free adapter decision is retained in developer diagnostics and the
private observed-query aggregate. It contains no app identity, field content,
selection, ancestor path, or native error.

## Consequences

- The current plain Codex/ChatGPT composer shape can use one verifiable
  mutation even when its web ancestor is deeply nested, the caret is mid-draft,
  or the draft contains plain newlines.
- Native nonempty text areas and rich, mixed-format, object-bearing, oversized,
  cyclic, or structurally changing web surfaces still fail to local review
  without mutation.
- The full plain value and attributed representation exist transiently in
  process memory. They are never separately logged or persisted.
- Uniform styling that an Accessibility provider fails to expose remains a
  platform limitation, so live rich-editor refusal is an acceptance gate.
- Compatibility with the user's current Codex, ChatGPT, Notion, Chrome, IME,
  and editor versions remains manual evidence, not an automated claim.

## Rejected alternatives

- Try selected text and then whole value: rejected because delayed first writes
  can produce duplicate effects.
- Use the undocumented `AXReplaceRangeWithText` parameterized attribute:
  rejected because Topher does not depend on private mutation behavior.
- Paste or synthesize keyboard input: rejected because it expands shared-state
  and raw-input authority and weakens exact target verification.
- Allow every web or native text area: rejected because whole-value writes can
  flatten semantic editor structure.
- Add a Codex or ChatGPT bundle allowlist: rejected because application identity
  is not evidence that the focused field is structurally safe.
