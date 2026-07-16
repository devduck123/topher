# 0016: Verify Accessibility dictation mutations and use a bounded plain-value adapter

- Status: accepted
- Date: 2026-07-16
- Supersedes: the categorical whole-value rejection in decision 0013 only

## Context

Build 12 dogfooding recorded six dictation attempts as `dictationInserted`, but
the user observed visible text in only three targets. ChatGPT/Codex, Notion, and
a Chrome search field all produced false-positive success. Permission, capture,
finalization, and processing timings were healthy, so the failure was isolated
to the focused-element mutation boundary.

The implementation treated a successful
`AXUIElementSetAttributeValue(kAXSelectedTextAttribute, ...)` result as proof of
insertion. The macOS 26.5 Accessibility headers describe selected text as not
writable, while an element's value is the standard writable text attribute.
Chromium/Electron-backed surfaces can therefore accept the selected-text setter
without changing visible content. An attempted native mutation must not be
reported as a completed user effect without observable evidence.

A general whole-value rewrite is still unsafe for rich text, composition state,
long documents, and app-owned editing semantics. Clipboard replacement plus a
synthetic paste remains broader shared-state and input authority than this
feature needs.

## Decision

Topher captures a fixed, content-free target profile at dictation key-down:
process identity, text role, and whether selected text, selected range, and
plain value are writable. It revalidates process, element, selection, boundary,
and secure state before mutation.

For a writable plain `AXTextField`, an empty `AXTextArea`, or a text area whose
entire value is selected, Topher may use a bounded whole-value adapter. The
captured value and result must each be at most 16,384 UTF-16 units, and the
captured selected substring must exactly match the captured selection. Web
areas, partially selected nonempty text areas, other roles, protected content,
invalid ranges, and unavailable values cannot use this adapter. Topher chooses
one insertion strategy before mutation; it never tries a second strategy after
an ambiguous result.

Other compatible fields retain the selected-text path from decision 0013. Both
paths perform bounded readback immediately and after at most three 10 ms waits.
Success requires the inserted range or exact expected value to match. Caret
readback distinguishes content-and-caret verification from content-only
verification. A readable unchanged value becomes `mutationNotObserved`; an
unreadable result becomes `mutationUnverified`. Neither is presented as
successful insertion. Unverified results keep pending text but warn the user to
inspect the target before copying, because copying blindly could duplicate a
late host mutation.

The developer trace records only fixed insertion method, verification result,
role, and settable-capability booleans. It does not add the destination app,
field value, selected content, or framework error. The bounded full value exists
only transiently in memory. Whole-value insertion does not advertise Topher's
guarded undo; selected-text insertion retains it only after content and caret
are both verified.

## Consequences

- A framework false positive can no longer become a visible success claim.
- Common plain fields in Chromium/Electron and native apps have a standards-
  based insertion route without clipboard or raw-key synthesis.
- The worst-case verification wait is 30 ms and only occurs when immediate
  readback is inconclusive, preserving the observed fast dictation path.
- Rich and ambiguous editors still fall back instead of risking formatting or
  document corruption; broad app compatibility remains a manual acceptance
  gate.
- Whole-value insertion may participate in the host application's own undo
  stack, but Topher does not claim or implement undo for that method.
- The target profile is an insertion-safety input, not general screen-aware
  application context. Browser reading and intent context remain separate
  future capabilities.

## Rejected alternatives

- Trust a successful Accessibility setter: rejected because live dogfooding
  demonstrated three false-positive effects in six attempts.
- Try selected text and then rewrite the full value when readback is unchanged:
  rejected because a delayed first mutation could duplicate or corrupt text.
- Rewrite every writable value: rejected because roles alone do not prove rich
  text, composition, or document semantics are safe to flatten.
- Add app-specific bundle allowlists first: rejected because the actual safety
  properties are field capabilities and verified mutation, not an app name.
- Replace the clipboard and synthesize paste: deferred because it expands
  clipboard, focus-race, and raw-input authority and needs its own design.
