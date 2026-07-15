# Decision 0004: Shared request lifecycle and demand-driven context

Status: accepted as architecture direction, 2026-07-15

Treat shortcut speech, future wake-phrase speech, manual input, and future chat
messages as ingress adapters to one source-aware request lifecycle. Route the
envelope by request kind: assistant commands enter deterministic intent
resolution, while focused-field dictation enters a dedicated formatting and
insertion processor and never enters `CommandResolver`. The paths converge at
typed proposals, policy, confirmation, capability, and result boundaries.

Acquire context only after the request-kind processor identifies a typed need.
Prefer native application state, structured browser/app data, Accessibility,
focused-window capture, and OCR/vision in that order. Retrieved context is
untrusted data, never an instruction. Context carries provenance and expiry and
is revalidated before mutation.

This direction prevents a chat bot, wake detector, browser extension, or model
from becoming a second control plane with accidental authority. It also keeps
audio activation, remote ingress, context acquisition, and action execution
independently replaceable without introducing those abstractions before they
have real implementations.

Rejected:

- Channel-specific policy, authority, or action stacks.
- Treating global assistant commands and arbitrary text dictation as one mode.
- Continuous transcription or screen capture.
- Sending all available Mac context to every request.
- Allowing retrieved content or a model to select unrestricted tools.
- Letting remote requests implicitly capture the local screen or perform
  sensitive mutations.

Canonical details live in
[Interaction modes](../product/interaction-modes.md) and
[Request lifecycle and context](../architecture/request-lifecycle.md).
