# Interaction modes

Status: product contract and planning reference, 2026-07-15

Topher should accept requests through several channels over time, but those
channels must converge on one policy-controlled assistant rather than becoming
separate products with different safety rules. This document defines the modes
clearly enough that implementation and user expectations stay aligned.

## Vocabulary

These concepts are related, but they are not interchangeable:

- **Activation** decides when Topher starts a local interaction, such as a
  shortcut or wake phrase.
- **Ingress** is how a request reaches Topher, such as microphone audio or a
  Discord message.
- **Transcription** converts speech to text. It does not decide intent.
- **Request processing** routes an authenticated user-authored instruction to
  the processor for its mode. The instruction is never directly executable.
- **Intent resolution** turns an assistant command into an application-owned
  proposal. Dictation instead uses a formatting and insertion processor.
- **Context acquisition** reads only the Mac state required to resolve that
  proposal.
- **Execution** runs a registered capability after policy and confirmation.
- **Session state** supports bounded follow-ups such as “open the second one.”
  It is not long-term memory.

Keeping these concepts separate lets Topher add a new input mode without giving
that mode new authority over the Mac.

## Mode matrix

| Mode | User experience | Status | New trust or permission boundary |
|---|---|---|---|
| Global push-to-talk command | Hold a configured shortcut while any app is focused, speak a Topher request, then release to resolve and execute it. | Implemented | Microphone and local speech assets |
| Manual panel command | Type a would-be transcript into Topher and run the same command path. | Implemented development fallback | None beyond the selected capability |
| Global text dictation | Hold a distinct shortcut and insert conservatively formatted text into the focused editable field. | Safe foundation implemented; app-compatibility acceptance pending | Accessibility plus focused-element validation |
| Local wake phrase | Opt in to local “Topher” detection, then capture one request without a keyboard hold. | Research only | Persistent microphone use, energy, false activation, visible ambient-state controls |
| Remote chat message | Send Topher a request from another device through Discord, Slack, WhatsApp, or another adapter. | Planned investigation | Provider network, account identity, credentials, replay and remote-presence policy |
| Conversational follow-up | Keep a short, visible interaction window for references such as “the second one.” | Future | Bounded local state, expiry, provenance, and clear reset behavior |

## Current global push-to-talk contract

The current feature is a global **assistant command** mode:

1. Topher remains a menu-bar application in the background.
2. Shortcut key-down begins a user-authorized microphone session.
3. A passive HUD appears without taking focus from the active app.
4. Shortcut key-up finalizes the local transcript.
5. The transcript enters the deterministic resolver, policy, and capability
   path.
6. Unsupported text fails visibly and does not become an executable string.

The menu does not need to be open and Topher does not need to be the focused
application. The microphone is active only for the hold, subject to the
30-second safety timeout.

This shortcut remains command-only. Dictated prose uses the distinct global
dictation shortcut below, so speech cannot accidentally switch between typing
and executing an assistant action.

## Global text dictation

Text dictation is a separate capability, not a flag inside command execution.
Build 9 implements a distinct shortcut so dictated prose cannot accidentally
become a Topher action.

The implemented foundation contract is:

- Capture and transcribe locally using the same replaceable speech boundary.
- Transform only bounded presentation details: trim outer whitespace, normalize
  horizontal spacing and line endings, remove spaces before closing
  punctuation, and add a boundary space only when insertion would weld words.
  Topher does not invent terminal punctuation, capitalization, or meaning.
- Identify and revalidate the focused editable element before insertion.
- Insert text without pressing Return, submitting a form, or sending a message.
- Refuse secure/password fields and other excluded surfaces.
- Preserve a preview/copy fallback when direct insertion is unsupported.
- Define one-step undo behavior before broad app support is claimed.
- Request Accessibility only from an explicit dictation hold or enable action.
- Revalidate focus, selection, surrounding text, and secure-field state after
  transcription and before mutation. A mismatch produces a preview, not a guess.
- Never mutate the clipboard automatically; copying a fallback is explicit.
- Exclude secure-field dictation from the content-bearing developer trace.

The foundation uses Accessibility selected-text and selected-range attributes.
Editors that do not expose a safely settable selection are intentionally routed
to the pending preview. Broad app compatibility, spoken formatting commands,
punctuation quality, and multi-paragraph behavior remain measured acceptance
work rather than implied guarantees.

Dictation quality is a system-level result. The benchmark must cover recognition
accuracy, partial stability, endpoint latency, punctuation, application-specific
insertion, undo behavior, and recovery—not only word error rate.

## Local wake phrase and ambient operation

Wake-phrase mode means continuous **local wake detection**, not continuous
transcription or continuous storage.

Before implementation it needs measured proof for:

- False accepts per hour and false rejects for the word “Topher.”
- Idle CPU, memory, energy impact, and sleep/wake recovery.
- Whether audio remains entirely local.
- A persistent, unambiguous enabled indicator and one-click kill switch.
- Behavior when the Mac is locked, asleep, on battery, or using a changed
  microphone.

The detector may keep only the bounded in-memory audio window required to
recognize the wake phrase. That window is continuously discarded and is never
persisted, logged, transmitted, or treated as a transcript. Request
transcription begins only after a confirmed wake event.

Wake activation does not imply authorization for sensitive work. User presence
and confirmation still matter after the wake phrase.

## Remote chat adapters

A chat adapter is an untrusted network ingress, not merely another text box.
Discord, Slack, WhatsApp, and similar services also weaken the pure local-first
boundary because messages pass through their infrastructure.

Every adapter must provide a source-aware request envelope containing an
authenticated account or conversation identity, a provider message identifier,
receipt time, and reply route. The adapter must also enforce:

- Credentials in macOS Keychain, never source, plist files, logs, or ordinary
  user defaults.
- Explicit allowlists for users, workspaces, servers, channels, or chats.
- Expiration, duplicate/replay rejection, rate limiting, and reconnect safety.
- Provider-specific permission and data-retention documentation.
- The same request-kind routing, typed proposal, policy, and capability
  boundaries as local requests.
- A conservative remote policy: begin with read-only status and low-risk work.
- Preview and explicit confirmation for externally visible or sensitive
  mutations.

“Draft a reply” and “send a reply” are different capabilities. Topher must
never infer sending authority from permission to read or draft a message.

A remote message must not silently capture the current screen. The request must
explicitly name the desired device context, the policy must allow remote context
access, and sensitive visual capture should require local confirmation.

## Conversational follow-up

Follow-up mode should retain only a small interaction state with:

- The originating channel and authenticated source.
- Typed references to recent results, tabs, documents, or actions.
- Creation and expiry times.
- A visible way to clear the session.
- No raw screen, page, message, or audio retention by default.

References must be revalidated before mutation. “Close that tab” cannot use a
stale tab reference after the active browser state has changed.

## Shared rules across every mode

No input mode receives special authority. All modes must follow the same rules:

1. Treat an authenticated user-authored request as an instruction, but never as
   directly executable text.
2. Treat retrieved or quoted webpage, document, accessibility, OCR, and message
   context as untrusted data and keep it separate from the instruction.
3. Produce application-owned typed proposals through the request-kind
   processor.
4. Acquire the least context required for the current request.
5. Apply policy based on source, user presence, risk, and requested effect.
6. Let an explicit present-user request satisfy confirmation only for a
   capability-defined, bounded deterministic local handoff; otherwise preview
   and confirm sensitive remote, model- or context-derived, destructive, or
   other externally visible effects.
7. Execute only registered capabilities with validated inputs.
8. Return a typed result to the originating local or remote channel.
9. Keep raw audio, transcript, message, and screen content out of ordinary
   logging. Any content-bearing developer trace must be separately opted into,
   visibly active, narrowly scoped, bounded, and immediately clearable.

The technical lifecycle and screen-context rules are defined in
[Request lifecycle and context](../architecture/request-lifecycle.md).

## Delivery order

Keep one reliable loop at every checkpoint:

1. Finish push-to-talk accuracy, latency, permissions, sleep/wake, and repeated
   session validation.
2. Add the read-only active-application provider as the smallest context slice.
3. Complete in build 9: build global text dictation as an explicitly separate
   mode and permission; continue its app-compatibility and speech-quality gate.
4. Add structured browser tab/page context before screenshot-based context.
5. Establish confirmation and bounded-session behavior before remote mutation.
6. Spike one chat adapter with read-only authority.
7. Evaluate a local wake phrase only after idle-resource and privacy gates exist.

This order is a planning default, not a promise that every mode will ship.
Measured usefulness and safety determine whether each phase proceeds.
