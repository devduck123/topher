# Decision 0010: Single-instance command ownership

Status: accepted for local dogfooding, 2026-07-15

Build 6 was accidentally launched three ways during installation validation.
All processes subscribed to the same global shortcut, so one user request
opened two or three browser tabs. LaunchServices normally reuses a running app,
but `open -n` and direct executable invocation can deliberately bypass that
behavior. Installer discipline alone is therefore not a sufficient invariant.

Topher now acquires a nonblocking per-user file lock before subscribing to
shortcut events. The lock is held for the process lifetime. Its directory and
file must be owned by the current user, use restricted permissions, and not be
symbolic links. Only the primary lock owner listens. A secondary or unsafe lock
state terminates before shortcut registration.

The local installation helper stops the prior process, verifies the bundle
before and after copying, launches once, and requires exactly one process. New
developer records also carry a random per-launch session identifier so future
duplicate-writer evidence is visible without retaining more transcript data.

This lock is a local lifecycle guard, not authentication or a cross-user
security boundary. Topher still relies on typed resolution, policy, and
capability checks for every request.
