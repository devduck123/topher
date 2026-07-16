# Decision 0006: Default-on dogfood transcript diagnostics

Status: accepted for local dogfooding, 2026-07-15

Default the bounded developer transcript trace on while Topher is being built
and dogfooded locally. A previously persisted opt-out remains authoritative, so
turning recording off keeps it off across relaunches. Re-enabling after an
opt-out still presents the existing sensitive-text warning and requires
confirmation.

This changes only the initial boolean. Decision 0005's data boundary, storage
hardening, retention, orange indicator, failure isolation, token invalidation,
and **Clear Now** behavior remain in force. In particular, local plaintext is
not treated as encrypted merely because it stays on this Mac.

Rationale: unsupported or misresolved commands are most valuable during this
phase, and requiring a setup step made that evidence too easy to miss. The
trace remains deliberately disposable: 24 hours, 200 records, 1 MiB total, and
4 KiB per finalized transcript, with no raw audio, partial speech, separately
captured screen/browser context, constructed URLs, or detailed framework
errors.

Before an externally distributed release, explicitly review this default as a
release/privacy decision rather than carrying the dogfood posture forward by
accident.
