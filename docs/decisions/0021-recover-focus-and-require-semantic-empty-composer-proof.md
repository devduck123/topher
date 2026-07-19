# 0021: Recover app focus and require semantic empty-composer proof

- Status: accepted
- Date: 2026-07-18

## Context

Build 16 dogfooding found three distinct failures. Codex/ChatGPT often exposes a
visually empty composer as a nonempty `AXValue` containing suggestion text.
VS Code can omit the system-wide focused element even when its frontmost
application object exposes one. Terminal does not expose a standard writable
prompt contract. Treating all three as generic selected-text failures hid the
cause and tempted unsafe compatibility fallbacks.

## Decision

Topher keeps the system-wide focused element authoritative. Only when that
lookup is unavailable may it query the current frontmost application's focused
element. The process identifier must match the frontmost process at preparation
and mutation time; a conflicting system-wide element fails closed.

For Codex/ChatGPT only, a nonempty web-composer value at a zero-length selection
at the start may be replaced with the transcript alone when Accessibility proves
one of two semantic states:

1. every UTF-16 unit in the full attributed value is marked `AXIsSuggestion`, or
2. both the character-count attribute and the element's full web text-marker
   range independently report zero logical content.

Active marked text, mixed suggestion/authored content, authored logical content,
missing evidence, inconsistent evidence, placeholder-backed values, objects,
and out-of-bounds values are refused. The same semantic decision is re-read
immediately before one whole-value write. Topher performs no selected-text write
on this path, never submits, and reports success only after exact readback no
longer describes an empty/suggestion-only composer.

Terminal remains an explicit review/copy fallback. Topher does not synthesize
keystrokes, paste automatically, invoke a shell, or press Return to broaden
coverage. VS Code compatibility depends on the editor exposing a standard
writable Accessibility field, commonly through its screen-reader optimized
mode.

Diagnostics retain only fixed preparation source, known application family,
failure reason, and semantic decision values. They never retain process IDs,
roles outside the fixed enum, element paths, editor content, suggestion text, or
native errors beyond the existing bounded transcript trace.

## Consequences

- Codex suggestion replacement becomes possible without treating arbitrary
  nonempty editor text as a placeholder.
- Application-scoped focus recovery improves compatible Electron editors without
  allowing cross-process insertion.
- Terminal remains less convenient but cannot accidentally execute dictated
  text.
- Host Accessibility changes can reduce compatibility; unavailable or changed
  evidence produces the existing review/copy fallback.

## Rejected alternatives

- Replace any caret-at-start Codex value: rejected because authored content and
  suggestions are structurally indistinguishable without semantic proof.
- Trust setter success or a later matching `AXValue`: rejected because either can
  describe host suggestion state rather than committed editor content.
- Fall back to clipboard paste, keyboard events, AppleScript, or shell input:
  rejected because these add global side effects and execution risk.
- Search every running application for a focus target: rejected because it can
  redirect dictation across an application switch.

## Relationship to earlier decisions

This decision narrows and extends decisions 0016 through 0019. Decision 0019's
generic refusal for caret-at-start web values remains the default; this decision
adds one Codex/ChatGPT-only semantic exception.
