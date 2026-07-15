# Decision 0002: Typed deterministic control path

Status: accepted, 2026-07-14

Resolve supported text deterministically into an application-owned
`TopherCommand`. Evaluate policy after resolution and before a registered native
capability executes. Unknown text fails closed.

This path remains useful when Apple Intelligence is off, as it is currently on
this Mac. It also prevents transcript or model text from becoming a raw bundle
ID, URL, script, or input event.

Rejected now: routing every command through an LLM, free-form tool calls,
arbitrary shell/AppleScript/JavaScript, and a generic agent loop.
