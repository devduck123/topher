# 0013: Keep global dictation separate and insert through revalidated Accessibility selection

- Status: accepted
- Date: 2026-07-15

## Context

Topher's assistant shortcut turns speech into typed commands and native effects.
Using that route for general prose would create an unacceptable ambiguity: the
same utterance could either type text or execute an assistant action. Global
dictation also needs to work while another application owns focus, which adds
an Accessibility permission and a stale-target risk not present in the existing
command path.

Common dictation apps often synthesize paste keystrokes and temporarily replace
the system clipboard. That technique is broadly compatible, but it mutates
shared sensitive state, makes restoration races possible, and can deliver input
to a different target if focus changes. Rewriting an element's complete value
would preserve neither rich text nor app-specific editing behavior. Simulating
Return is outside dictation authority because it can submit a form or send a
message.

## Decision

Global dictation is a distinct request kind with a distinct user-recorded hold
shortcut. It may reuse `PushToTalkCaptureController`, but its finalized text
never enters `TranscriptInterpreter`, `CommandResolver`, or assistant capability
dispatch. Shortcut ownership is explicit: a key-up from one shortcut cannot
finalize a hold started by the other.

Accessibility trust is read without prompting. Topher asks macOS to explain the
permission only after an explicit dictation hold or **Enable** action and offers
the corresponding System Settings route. The first capability is deliberately
narrow:

1. At key-down, capture the focused Accessibility element, selected text,
   selected range, and immediate text boundary.
2. Refuse secure-text-field and protected-content surfaces before microphone
   capture.
3. After local transcription, revalidate element identity, selection, boundary
   text, settable attributes, and secure state.
4. Conservatively normalize only whitespace, line endings, punctuation spacing,
   and a word-boundary space needed to avoid joining adjacent words.
5. Replace only the selected text through Accessibility and move the caret to
   the end of that insertion. Never synthesize Return, paste, arbitrary keyboard
   input, submit, or send.
6. Keep one undo receipt containing the original selection and inserted text.
   Undo succeeds only if focus, caret, and inserted content still match; otherwise
   it leaves the app unchanged.
7. If no safely mutable field exists or focus/selection changes, keep a local
   pending preview. Writing that preview to the clipboard requires an explicit
   **Copy** action.

The dogfood developer trace records dictation as a distinct source with raw
versus formatted/inserted text and typed insertion outcomes. Dictation aimed at
a secure field never starts. If the target becomes secure during the hold, the
final text is discarded without a preview or developer record.

## Consequences

- Dictated prose cannot accidentally become an assistant command.
- The initial implementation fails closed in editors that do not expose safely
  settable selected-text and selected-range attributes. Compatibility must be
  measured before broad claims.
- Topher does not disturb the user's clipboard during normal dictation or
  fallback creation.
- Immediate boundary reads improve spacing without creating a general screen or
  Accessibility-context provider.
- One-step undo is intentionally narrower than application-native undo and may
  refuse after any intervening edit or caret movement.
- Accessibility permission is now part of Topher's local security posture even
  though Screen Recording, Automation/Apple Events, arbitrary input synthesis,
  and general UI-tree inspection remain absent.
- Rich dictation rewriting, spoken formatting commands, app-specific adapters,
  and broader context remain future measured layers rather than implicit powers
  of this capability.

## Rejected alternatives

- Reusing the assistant command shortcut or resolver: rejected because prose
  and executable intent must be unambiguous before transcription completes.
- Automatic clipboard replacement plus simulated paste: rejected for the
  foundation because clipboard restoration and focus races expand shared-state
  risk. Explicit Copy remains a visible fallback.
- Replacing the element's entire value: rejected because it can destroy rich
  text, composition state, or app-owned editing semantics.
- Raw keyboard synthesis: rejected because target and submission behavior are
  harder to constrain and test than selected-text replacement.
- Automatic terminal punctuation or vocabulary rewriting: rejected until a
  dictation corpus measures benefit and semantic-change failures.
