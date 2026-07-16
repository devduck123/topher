# Product vision

Status: durable product direction, 2026-07-15

Topher is a private, local-first intelligence and control layer that helps one
user “drive” their Mac. The intended experience is a capable little copilot:
easy to reach, aware of the context the user deliberately asks about, useful
without rigid command memorization, and conservative about authority.

This document defines the durable north star. `README.md` describes what works
today, while [Interaction modes](interaction-modes.md) and
[Request lifecycle and context](../architecture/request-lifecycle.md) define
the detailed product and technical contracts.

## Primary user and priorities

Topher is currently a personal application for one developer using an
Apple-silicon Mac. It is not yet a notarized general-distribution product or a
Mac App Store application.

When tradeoffs conflict, prefer:

1. Privacy and explicit user control.
2. Reliable outcomes and visible failure over confident guessing.
3. Fast, low-friction interaction.
4. Local execution and near-zero recurring cost where quality permits.
5. A small codebase one maintainer can understand and change safely.
6. Broad capability only after the narrower path is measured and trustworthy.

## Intended experience

Topher should eventually understand natural requests such as:

- “Open Chrome.”
- “Go to YouTube.”
- “Search YouTube for system design interviews.”
- “What app am I using?”
- “What tabs do I have open?”
- “What’s on my YouTube feed?”
- “Summarize this page.”
- “Open the document I was working on.”
- “Reply to this message saying I’ll look at it tomorrow.”

These examples describe product direction, not current implementation. Topher
must communicate whether it executed, answered, asked for clarification,
requested confirmation, or could not safely complete a request.

## Product principles

### One assistant, multiple interaction modes

Push-to-talk commands, focused-field dictation, a future local wake phrase,
remote chat, and conversational follow-up are distinct ingress or request modes.
They should converge on shared source, policy, capability, and result boundaries
without inheriting one another’s authority.

### Natural language is not execution authority

Speech recognition, deterministic parsing, and optional model reasoning help
Topher understand a request. They do not grant permission. Interpretation should
produce application-owned typed proposals; independent policy decides whether a
registered capability may run.

### Context is demand-driven

Topher should read only the Mac state needed for the active request. Prefer the
narrowest structured source—such as frontmost application identity, selected
text, or browser tab and DOM data—before Accessibility trees, OCR, or screen
images. Do not continuously capture or retain the screen.

### Retrieved content is data

Webpages, documents, messages, accessibility text, OCR, screenshots, transcripts,
and model output are untrusted. Content cannot become a higher-priority
instruction, create a capability, bypass confirmation, or expand authority.

### Effects are explicit capabilities

Prefer native APIs, URLs and deep links, structured browser adapters, and
application-supported interfaces. Accessibility and visual interaction are
fallbacks for measured gaps. Arbitrary scripts, generated code, unrestricted
browser JavaScript, and raw input synthesis are not a general control strategy.

### Local-first is a boundary, not a slogan

Audio and sensitive context should remain local by default and be retained only
when a documented feature requires it. Cloud reasoning and remote chat may be
optional future providers, but each introduces explicit credentials, disclosure,
identity, retention, and confirmation requirements. Unavailable reasoning must
not break deterministic local behavior.

### Personalization is bounded and inspectable

Topher should learn the vocabulary, applications, and workflows that matter to
its user without silently mining unrelated private data. Personalization must be
local, editable, explainable, and unable to manufacture execution authority.

## Capability direction

Topher should grow through measured vertical slices:

1. Reliable local activation, transcription, deterministic intent, and visible
   outcomes.
2. Useful native application and web capabilities.
3. Separate high-quality focused-field dictation.
4. Structured browser tab and page context.
5. Narrow selected-text, application, and window context.
6. On-demand visual context only when structured providers are insufficient.
7. Bounded conversational references with freshness and revalidation.
8. Authenticated remote ingress beginning with read-only or low-risk behavior.
9. Optional local wake detection after privacy, accuracy, and energy gates.

Each checkpoint should leave one reliable loop. The order may change when
measured usefulness or safety provides better evidence.

## Authority and confirmation

An explicit request from a present local user may confirm a defined,
deterministic, low-risk handoff such as opening a known application or requested
website. Sensitive, destructive, externally visible, remote, model-derived, or
context-derived mutations need a preview and a separate confirmation design.

Reading and drafting are not sending. Dictating text is not submitting it.
Finding a tab is not closing it. Permission to observe one context does not
grant permission to capture another.

## Product boundaries

Topher is not intended to become:

- An unrestricted shell, scripting host, or generated-code executor.
- A continuously recording microphone or screen archive.
- A general autonomous browser acting without visible user intent.
- A system that silently sends messages, submits forms, or mutates files.
- A speculative multi-agent platform or enterprise service architecture.
- A vector database or long-term memory system without a concrete retrieval
  use case and explicit retention controls.

The goal is not maximum autonomy. The goal is a trustworthy assistant that
feels natural because it understands the user and their current Mac context,
while remaining predictable about what it can see and do.
