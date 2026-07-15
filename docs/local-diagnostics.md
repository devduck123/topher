# Local diagnostics

Topher has two deliberately separate diagnostic paths:

| Path | Purpose | Contains command text? | Retention owner |
|---|---|---:|---|
| macOS Unified Logging | Lifecycle troubleshooting and signpost timing | No | macOS |
| Opt-in developer trace | Recent local dogfood requests and typed outcomes | Yes, when explicitly enabled | Topher, with hard bounds |

There is no remote telemetry backend. Enabling the developer trace does not
send its records anywhere.

## Unified Logging

Topher uses Apple's `Logger` API. The closest web/cloud analogy is a structured
application logger whose sink is supplied by the operating system:

| Topher/macOS | Web/cloud analogy |
|---|---|
| Unified Logging | Platform log aggregation |
| Subsystem `dev.topher.app` | Service or application name |
| Categories `control-path`, `voice-capture`, and `developer-diagnostics` | Logger namespaces |
| `log stream` | Follow/tail live events |
| `log show` | Query retained events |
| Xcode debug console | Local development console |
| `OSSignposter` intervals | Trace spans for latency investigation |

Start this in Terminal before running a command in Topher:

```sh
/usr/bin/log stream --style compact --level info \
  --predicate 'subsystem == "dev.topher.app"'
```

Use this after a test to inspect the last hour:

```sh
/usr/bin/log show --last 1h --style compact --info \
  --predicate 'subsystem == "dev.topher.app"'
```

The retained result can be smaller than the live stream. Information-level
events are not a durable audit trail and may no longer appear in a later
`log show` query. Use `log stream` when verifying a specific action. When
launching from Xcode, the same events also appear in Xcode's debug console.
Console.app can stream them too; filter on subsystem `dev.topher.app`.

Fixed events emitted across the three Unified Logging categories include:

- Push-to-talk started, ended, or timed out.
- Microphone permission denied or restricted.
- Local speech asset preparation failed.
- Voice capture failed to start, its result stream stopped/failed, or
  finalization failed/timed out.
- Microphone permission remained undetermined or the local speech model was not
  ready.
- A fixed registered capability identifier started.
- A capability completed or failed.
- An unsupported command was rejected.
- Command policy denied a registered command.
- A developer-trace setting, read, write, clear, or maintenance operation
  failed, or unreadable storage was cleared.

The `voice-capture` category also emits three payload-free signpost interval
names:

- `VoicePreparation`: permission, speech-model readiness, and engine
  preparation before listening.
- `VoiceCapture`: the active microphone hold.
- `VoiceFinalization`: key-up through final transcript completion or timeout.

Unified Logging and signposts never receive manual text, partial/final speech,
search terms, URLs, page contents, raw audio, selected application names, or
detailed errors that might carry user data. Developer-trace failures use fixed
metadata-only messages; there is no transcript fallback into `Logger` or
`print`.

## Opt-in developer transcript trace

The menu's **Developer diagnostics** section exposes **Record final command
transcripts**. It is off by default. Enabling it presents a warning and requires
confirmation; while enabled, an orange dot appears in both the diagnostics
section and Topher's menu-bar icon.

Each record contains only:

- The exact finalized voice or manual command after surrounding whitespace is
  removed. This can include a search term or secret typed/spoken by the user.
- Whether the request came from voice or the manual development field.
- A fixed outcome: unsupported, policy denied, capability succeeded,
  capability failed, or no usable speech.
- The fixed command kind and registered capability identifier when resolution
  produced one.
- Processing duration, record time, and app version/build.

Topher does not separately capture or append raw audio, partial transcripts,
microphone buffers, retrieved browser/screen/message/document context,
constructed destination URLs, detailed framework errors, Keychain/config
values, or arbitrary error text. The exact user-authored command can itself
contain a query, URL, pasted content, credential, or error string.

The JSON file is:

```text
~/Library/Caches/dev.topher.app/TranscriptDiagnostics/transcript-diagnostics.json
```

Topher uses the Caches directory because these records are disposable
development evidence, not durable user history. Topher sets POSIX mode `0700`
on its directories and `0600` on the file, and excludes both from backup. It
rejects symlinked or differently owned storage locations instead of following
them. The operating system may purge a cache earlier than Topher's limits.

Local does not mean encrypted or secret from the current macOS account. The
same account and system administrators can read the file, and App Sandbox is
not currently enabled. Review and redact any record before sharing it; never
attach the raw file to a public issue or pull request.

### Rolling retention

All four limits apply:

- Records older than 24 hours are removed.
- At most the newest 200 records are kept.
- The encoded file is at most 1 MiB; oldest records are removed first.
- Each transcript is at most 4 KiB of valid UTF-8 and is marked when truncated.

Cleanup runs on load/launch, refresh, writes, setting changes, and hourly while
Topher is running. If Topher is not running at the 24-hour boundary, stale
records are removed on its next load; macOS may purge the cache sooner.
Unreadable, corrupt, wrong-schema, or oversized documents are discarded rather
than partially trusted.

### Disable and clear semantics

- Turning recording off prevents new records, invalidates previously issued
  trace tokens, and prevents their queued late records.
- Turning recording off does not silently delete existing evidence. Existing
  records remain subject to rolling cleanup so a failed command can still be
  inspected after stopping capture.
- **Clear Now** deletes the retained file, invalidates previously issued trace
  tokens, and prevents their queued late records, whether recording is on or
  off.
- If a new transcript record cannot be stored, Topher rolls that record back.
  Any pending retry restores the previously retained state or finishes cleanup;
  it does not later persist the failed transcript.
- If cleanup remains pending after a storage failure, the menu keeps a generic
  warning visible and leaves **Clear Now** enabled as an explicit retry, even
  after recording is disabled and no records are currently readable.
- The persistent preference stores only the enabled boolean. It does not store
  transcript content.

These semantics intentionally separate “stop collecting now” from “delete what
was already collected.”

## Other places request text can exist

Raw microphone buffers are passed to Apple's local speech analyzer and are not
written to an audio file or project-owned cache. Speech text exists transiently
in Topher's process memory and visible UI until command processing or later UI
state replaces it. “Not in ordinary logs” is not the same as “never held in
memory.”

For searches, the query is sent to the selected provider when the default
browser opens Google or YouTube, and normal browser history or provider
retention may apply. Manual text remains visible in Topher's field and process
memory until changed or the app exits. The opt-in developer trace adds the
bounded local copy described above; it does not change browser/provider
behavior.
