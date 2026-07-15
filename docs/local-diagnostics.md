# Local diagnostics

Topher currently uses Apple's `Logger` API. The closest web/cloud analogy is a
structured application logger whose sink is supplied by the operating system:

| Topher/macOS | Web/cloud analogy |
|---|---|
| Unified Logging | Platform log aggregation |
| Subsystem `dev.topher.app` | Service or application name |
| Category `control-path` | Logger namespace |
| `log stream` | Follow/tail live events |
| `log show` | Query retained events |
| Xcode debug console | Local development console |

There is no file such as `topher.log`, no local diagnostics database, and no
remote telemetry backend in this slice. macOS owns retention and rotation.

## Watch a test run

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

The retained result can be smaller than the live stream. In particular,
information-level events are not a durable audit trail and may no longer appear
in a later `log show` query. Use `log stream` when verifying a specific action.

When launching from Xcode, the same events also appear in Xcode's debug console.
Console.app can stream them too; filter on the subsystem `dev.topher.app`.

## Current event inventory

The control path records only these event shapes:

- Push-to-talk started, ended, or timed out.
- A fixed registered capability identifier started.
- A capability completed or failed.
- An unsupported command was rejected.

It intentionally does not record:

- The manual transcript or future speech transcript.
- Search terms, URLs, page contents, or browser history.
- Raw audio.
- Application names or bundle identifiers selected by a command.
- Detailed errors that might contain user data.

For searches, the query is still transmitted to the selected provider when the
default browser opens Google or YouTube, and normal browser history or provider
retention may apply. The manual text also remains visible in Topher's text field
and in process memory until it is changed or the app exits. “Not logged by
Topher” does not mean “not present anywhere on the computer or requested web
service.”

## Planned diagnostics

A later reliability slice can add a bounded, local action history with explicit
event types such as proposed, rejected, started, and completed. It should keep
the same privacy boundary by default: action metadata and timing, never raw
audio, transcript text, search text, or page contents.
