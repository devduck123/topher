# Decision 0005: Opt-in bounded transcript diagnostics

Status: accepted for local dogfooding, 2026-07-15

Keep macOS Unified Logging metadata-only. Add a separate developer trace that
stores finalized voice/manual command text only after an explicit warning and
confirmation. Recording defaults off and has a persistent orange indicator.

The trace is disposable local development evidence, not conversation history.
Store it as plaintext JSON under Topher's user Caches directory with POSIX modes
`0700` for its directories and `0600` for its file, backup exclusion, atomic
writes, and rejection of symlinked, non-regular, multiply linked, or differently
owned targets. Local plaintext remains readable by the same macOS account,
administrators, and any access granted through filesystem ACLs.

Each record contains the trimmed finalized command, voice/manual source, fixed
typed outcome, fixed command/capability metadata when available, duration,
timestamp, and app version/build. Topher does not separately append raw audio,
partial speech, retrieved page/screen/message/document context, constructed
URLs, Keychain/config values, or detailed errors. The user-authored command can
itself contain queries, URLs, pasted content, credentials, or other sensitive
text, so every record is treated as sensitive.

Apply all retention bounds: remove records older than 24 hours during cleanup,
keep at most the newest 200 records and 1 MiB encoded, and cap each transcript at
4 KiB of valid UTF-8. Cleanup runs on load, refresh, writes, setting changes, and
hourly while Topher runs. macOS may purge the cache sooner.

Disabling collection and deleting evidence are distinct actions. Disable stops
new collection, invalidates previously issued trace tokens, and prevents their
queued late records, while retaining prior records for debugging until cleanup.
**Clear Now** deletes the cache file and also invalidates prior tokens. Storage
failure never changes the command result and is reported only with fixed
metadata and generic UI text. A failed new-record write rolls back that
transcript; persistence retries restore only the prior record set or finish
cleanup, so the failed transcript is not silently saved later. Pending cleanup
remains visible in the menu and **Clear Now** stays available as a retry even
when collection is disabled and no records are currently readable.

Rejected:

- Putting transcript text in Unified Logging, `print`, or crash/error payloads.
- Recording by default or enabling without an explicit warning.
- Unbounded history, durable conversation memory, or retention in source control.
- Storing raw audio, partial speech, separately captured context, constructed
  destinations, or detailed framework errors.
- Silently deleting prior evidence merely because collection was disabled.
- Treating local storage as encrypted, sandbox-isolated, or safe to attach to a
  public issue without review.

Operational details live in [Local diagnostics](../local-diagnostics.md).
