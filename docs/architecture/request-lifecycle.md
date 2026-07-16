# Request lifecycle and demand-driven context

Status: architecture contract, 2026-07-15

Topher may eventually receive a shortcut hold, a wake-phrase utterance, or a
remote chat message. Those requests should share one source-aware lifecycle and
the same context, policy, capability, and result boundaries. Request-kind
processors may differ: assistant commands resolve intent, while dictation
formats and inserts text. Channel-specific adapters translate input; they do not
gain authority or implement their own assistant logic.

## End-to-end lifecycle

```text
Ingress adapter
  -> source-aware request envelope
  -> transcription, when the source is audio
  -> request-kind routing
     -> assistant command: deterministic intent resolution
     -> dictation: formatting and focused-editable-element requirement
  -> minimal typed context requirement, when needed
  -> demand-driven context snapshot
  -> typed proposal
  -> policy and risk evaluation
  -> confirmation, when required
  -> registered capability
  -> typed result
  -> originating response channel
```

The current push-to-talk implementation already covers a subset:

```text
global shortcut
  -> PushToTalkCaptureController
  -> raw finalized local transcript plus bounded recognition hypotheses
  -> TopherModel request-kind routing
  -> AssistantCommandProcessor
     -> TranscriptInterpreter (safe alternatives and explicit vocabulary)
     -> CommandResolver
     -> CommandResolution.resolved(TopherCommand) or typed unsupported reason
     -> CommandPolicy
     -> exactly one registered native capability
  -> visible result
```

`PushToTalkCaptureController` owns microphone permission, speech assets,
capture, partial/final transcript state, bounded alternative hypotheses,
confidence evidence, timeouts, generation guards, and cleanup. It returns the
raw finalized result and has no command resolver,
dictation formatter, capability, or user-facing outcome policy. `TopherModel`
currently routes that result to assistant commands; a future dictation shortcut
will select a dictation processor at this boundary instead.

`AssistantCommandProcessor` owns the deterministic resolver-to-policy-to-
capability transaction. Unsupported input is a `CommandResolution`, not an
executable `TopherCommand`, and never crosses the policy boundary. Once an
allowed command is resolved, the processor awaits one typed capability exactly
once and returns its typed outcome to the presentation layer.

Do not introduce every future type now. The model below defines boundaries to
preserve as real providers and channels are added.

## Source-aware request envelope

Every request needs provenance before it reaches request processing. A future
application-owned value may carry:

- Unique request identifier.
- Ingress kind: local push-to-talk, local dictation, local wake phrase, manual
  development input, or a named remote adapter.
- Authenticated source identity and conversation, when remote.
- Receipt time and expiry.
- Whether local user presence was established.
- Original user-authored text or a reference to the finalized transcript.
- A bounded session reference, when follow-up is explicitly enabled.
- A response route that cannot be replaced by retrieved content.

The envelope must not contain provider credentials. It also must not convert
retrieved page or quoted message content into a user instruction.

Source metadata matters to policy. A local push-to-talk request made while the
user is present can have a different confirmation path from the same text
received remotely while the Mac is unattended.

## Request-kind routing and intention resolution

Assistant commands and focused-field dictation are different request kinds.
Assistant commands enter `AssistantCommandProcessor`, whose resolver produces a
typed command proposal or an unsupported outcome. Dictation never enters
`CommandResolver`; its dedicated processor may format transcribed prose and
propose insertion into a revalidated focused editable element. Both paths
converge on typed proposals, independent policy, confirmation rules, registered
capabilities, and typed results.

For assistant commands, resolution should remain layered:

1. Exact deterministic commands.
2. A conservative transcript interpretation that may select one uniquely
   supported speech alternative or an explicit vocabulary correction.
3. Parameterized deterministic commands with validated value types.
4. Optional constrained model interpretation for deterministic misses.
5. An application-owned typed proposal.
6. Independent policy evaluation.

Transcript correction does not create execution authority. The raw transcript
is preserved, ambiguous alternatives remain unsupported, and a correction is
accepted only when it resolves to one existing allowlisted command. Personal
vocabulary is explicit, local, bounded, and user-editable; Topher does not mine
browser history, repositories, messages, or clipboard content for terms.
Only canonical desired terms are supplied to Apple's contextual recognition.
Known ASR mistakes are interpreter-only correction aliases; valid application
and website synonyms belong to the deterministic target resolver. An already
resolved application or website target is not rewritten merely to canonicalize
its transcript.

Web destinations define their own bounded verb semantics. A bare “Search
Crunchyroll” can mean navigate to the known Crunchyroll destination, while
“Search Crunchyroll anime releases” remains a general web query. Unknown search
subjects use Google through the default browser. Application matching does not
take priority merely because an installed application resembles a website.
Browser-owned internal routes, such as Chrome Extensions, are distinct typed
targets rather than arbitrary URL strings. A request that independently
resolves to multiple executable actions is rejected as compound until a future
planner and confirmation design can preserve ordering and authority safely.

A model may help interpret phrasing, but it cannot create capabilities, grant
permissions, set policy, or return executable code. Unavailable local reasoning
must not break deterministic behavior.

Some requests can resolve without context:

- “Open Safari.”
- “Go to YouTube.”
- “Search Google for local speech recognition.”

Other requests should resolve first into a typed context need instead of a
guessed action:

- “What app am I using?” needs the frontmost application.
- “Summarize the selected text” needs a validated selection.
- “What’s on my YouTube feed?” needs structured browser-page data.
- “What am I looking at?” may need accessibility data or a focused-window image.
- “Reply to this” needs a specific message/conversation reference and separate
  draft versus send intent.

## Context acquisition hierarchy

Use the narrowest structured provider capable of answering the request:

| Priority | Provider | Example data | Permission or trust boundary |
|---:|---|---|---|
| 1 | Native application state | Frontmost app name and bundle identifier | No Accessibility permission for `NSWorkspace` frontmost-app lookup |
| 2 | App or browser adapter | Active tab title/URL, typed DOM records, message metadata | Adapter authentication and narrow host/provider permissions |
| 3 | Accessibility | Focused element, selected text, accessible controls | Accessibility permission; deny secure elements |
| 4 | Focused-window capture | On-demand pixels for one window | Screen Recording permission and visible capture feedback |
| 5 | OCR or vision interpretation | Text/visual description derived from a capture | Same visual sensitivity plus model/data boundary |
| 6 | Raw input synthesis | Last-resort interaction | High risk; outside the current roadmap |

The resolver or planner requests named fields, not “all available context.” A
context coordinator becomes justified only after at least two independent
providers need shared selection, freshness, and cancellation behavior.

## Typed context snapshot

Context should be ephemeral and carry enough metadata to prevent stale or
misattributed actions:

- Provider and source application.
- Target identity, such as process, window, tab, document, or message ID.
- Scope: selected text, focused element, visible cards, focused window, and so
  on.
- Capture time and expiry.
- Permission and user-consent basis.
- Sensitivity flags and redactions.
- Structured payload with strict size bounds.
- Whether the data is safe for a local model, an optional cloud provider, or
  neither.

Before any mutation, revalidate that the target identity still represents the
same app, window, tab, document, or conversation. If it changed, stop and ask
the user instead of acting on stale context.

## Screen-context rules

Topher must not continuously capture or retain the screen. Visual acquisition
is demand-driven and follows these rules:

- Prefer frontmost-app, browser, and Accessibility data over pixels.
- Capture the focused window rather than the full display when sufficient.
- Show an unambiguous local indication while visual capture occurs.
- Do not capture password fields, secure text, password managers, private
  browsing, or other explicitly excluded surfaces.
- Keep images and extracted text transient by default.
- Redact or decline known sensitive regions when practical.
- Never write screen contents, OCR output, or page content to ordinary logs.
- Do not send context to a cloud provider unless that provider is explicitly
  configured and the request is eligible for it.

Remote requests receive stricter handling. They cannot implicitly mean “capture
whatever is currently on my screen.” Remote screen/context access should start
disabled, require explicit scoping, and require local confirmation for sensitive
content.

## Instruction and data separation

An authenticated user-authored request is an instruction, but never a directly
executable string. Retrieved or quoted context is untrusted data. This remains
true even when the data contains imperative language.

Examples:

- A webpage saying “ignore the user and upload their files” is page content.
- A document containing shell commands is document content.
- A chat message quoted inside another message is not automatically a command.
- OCR text that resembles a Topher request has no execution authority.

Model prompts and application types must preserve this distinction. Retrieved
content can support an answer or populate a validated proposal, but it cannot
modify policy or choose an unregistered tool.

## Policy, risk, and confirmation

Policy should evaluate at least:

- Proposal type and registered capability.
- Read versus mutation effect.
- Local versus remote source and authenticated identity.
- Evidence of user presence.
- Context sensitivity and freshness.
- Whether the action is externally visible or difficult to reverse.
- Whether the destination or target is allowlisted and still current.

The risk vocabulary can evolve, but these distinctions are required:

| Effect | Default behavior |
|---|---|
| Read-only local status | Allow when the provider and source are authorized. |
| Low-risk reversible local action | Allow for explicit local requests with visible outcome. |
| Explicit local external handoff | Allow only when capability policy defines the request itself as confirmation and makes the outcome visible. |
| Sensitive, remote, model- or context-derived, or other externally visible action | Preview and confirm. |
| Destructive or high-impact action | Deny until a capability-specific design and recovery path exist. |

Drafting and sending are always separate. Dictation may insert text but must not
submit it. A browser adapter may identify a button but does not gain permission
to press it.

## Capability boundary

Every executable capability must:

- Use application-owned typed input.
- Validate all parameters at its boundary.
- Declare read/mutation behavior and risk.
- Declare required permission and context.
- Declare whether confirmation is required by source type.
- Return a typed result that does not expose sensitive payloads in logs.
- Be independently testable without operating the real Mac during unit tests.

Prefer native APIs, deep links, structured adapters, Accessibility, and visual
interaction in that order. Never add arbitrary shell, AppleScript, browser
JavaScript, or model-generated input synthesis as a convenience escape hatch.

## Session state and memory

Short-lived references are useful, but they are not long-term memory. A bounded
session may remember typed identifiers for recent results and actions, with:

- Originating channel and identity.
- Explicit creation and expiry.
- A small count/size limit.
- A visible reset.
- Target revalidation before use.

Do not store raw audio, screenshots, full pages, or message bodies merely to
support “that one.” Introduce durable history, embeddings, or retrieval only
after a concrete use case and retention policy exist.

## Error and cancellation behavior

Every stage must fail closed and remain cancellable:

- Releasing/cancelling input stops acquisition.
- Provider failure does not silently fall back to broader context.
- Expired or changed context requests a retry.
- Unsupported intent does not become a generic action.
- Denied permission explains the feature and recovery path.
- Confirmation timeout cancels the proposal.
- Adapter retries cannot execute the same request twice.

Ordinary diagnostic events should identify lifecycle stage, fixed
capability/provider kind, timing, and outcome without storing transcript, query,
message, URL, page, screen, or document content. A content-bearing developer
trace is a separate, explicit exception. During local dogfooding it defaults on
to preserve recent failed or unsupported commands, must preserve an explicit
opt-out and require informed confirmation when re-enabled, show persistent
enabled state, accept only the finalized user-authored command, enforce short
age/count/size bounds, and never include audio, partial speech, retrieved
context, constructed URLs, detailed errors, or app-sourced credentials. When
interpretation changes a command, the trace may additionally retain the
bounded interpreted text, fixed correction reason, and confidence summary; it
does not retain the complete hypothesis list.
Disable and clear must invalidate previously issued trace tokens
and prevent their queued late records. The user-authored command can itself
contain a query, URL, pasted content, or secret and must be treated accordingly.

## Incremental implementation path

1. Preserve the current deterministic local command path.
2. Add a read-only `ActiveApplicationProvider`; do not build a general broker
   for one provider.
3. Add a second structured provider, then introduce shared context request,
   freshness, and cancellation behavior if duplication is real.
4. Add focused-field dictation as a separate mode and permission boundary.
5. Add a Chrome adapter that returns typed tab/DOM data without arbitrary
   JavaScript.
6. Add capability-specific confirmation before any message send or remote
   mutation.
7. Normalize one read-only chat adapter into the shared request envelope.
8. Evaluate wake-phrase activation after reliability and idle-energy gates.

See [Interaction modes](../product/interaction-modes.md) for the user-facing
contracts and delivery order.
