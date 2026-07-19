# Local diagnostics

Topher has two deliberately separate diagnostic paths:

| Path | Purpose | Contains request text? | Retention owner |
|---|---|---:|---|
| macOS Unified Logging | Lifecycle troubleshooting and signpost timing | No | macOS |
| Bounded developer trace | Recent local dogfood requests and typed outcomes | Yes; defaults on during dogfooding with an explicit off switch | Topher, with hard bounds |
| Private observed-query corpus | Durable local list of phrases for later manual testing | Yes; commands by default, dictation only by explicit flag | Developer, by explicit export and deletion |

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

- Push-to-talk started, ended, or reached its mode-specific maximum duration.
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

## Bounded developer transcript trace

**Settings → Developer → Local diagnostics** exposes **Record final commands
and dictation**. During local dogfooding it defaults on so unsupported phrasing
and dictation outcomes are captured without setup. The menu shows the latest
three retained requests and their ratings. Turning recording off persists the
opt-out; re-enabling it
presents a warning and requires confirmation. While enabled, an orange dot
appears in both the diagnostics section and Topher's menu-bar icon.

Each record contains only:

- The exact finalized voice/manual command or non-secure dictation after
  surrounding whitespace is removed. This can include a search term or secret
  typed/spoken by the user.
- The bounded interpreted, formatted, or inserted text only when it differs, a
  fixed correction reason when applicable, and an available confidence summary.
  Dictation repeated-speech cleanup therefore preserves both raw and polished
  forms with the fixed `dictationDisfluencyCleanup` reason.
- Whether the request came from assistant voice, dictation, or the manual
  development field.
- A fixed outcome: unsupported, policy denied, capability succeeded,
  capability failed, no usable speech, dictation inserted, dictation fallback,
  dictation failed, or capture failed.
- The fixed command kind and registered capability identifier when resolution
  produced one.
- A fixed unsupported reason when resolution rejects the command.
- Fixed dictation-fallback and content-free capture-failure reasons when those
  paths occur, plus whether the maximum duration caused automatic finalization.
- For every dictation target preparation, a fixed system-wide/application focus
  source, known application family, and content-free failure reason when one
  occurred. This identifies focus-discovery and field-contract failures without
  storing a process identifier, element path, title, or field content.
- For an insertion attempt, fixed content-free evidence: selected-text or
  whole-value method, content-and-caret/content-only/not-observed/unavailable
  verification, target role, and whether its three relevant attributes were
  settable. It also records a fixed known application family, selection
  relationship, placeholder state, attributed-value classification, and one
  fixed whole-value adapter decision. A Codex/ChatGPT semantic-empty attempt may
  additionally record fixed suggestion-attribute, character-count, text-marker,
  known-application-suggestion, and final decision states. These values describe
  only whether each signal was absent, unavailable, empty/nonempty,
  recognized/unrecognized, or inconsistent; they never retain the suggestion
  or editor text. Application
  families are limited to Chrome, Codex/ChatGPT, Notion, Notes, Safari,
  Terminal, Visual Studio Code, other, or unknown; no raw bundle identifier is
  retained. This evidence never includes the app or window title,
  process identifier, ancestor path, selected text, full field value, attributed
  content, URL, or native error.
- Optional user-set judgments for whether the transcript text was accurate and
  whether Topher's action was correct. These are independent because correct
  transcription can still lead to the wrong intent, and vice versa.
- An optional fixed issue tag after a user marks an action or insertion wrong,
  such as wrong destination, wrong field, wrong position, missing text,
  duplicated text, an unremoved stutter/filler, or spacing/punctuation.
- Voice-stage durations when available: hold-to-listening,
  listening-to-first-transcript, and key-up-to-final. These are monotonic local
  durations and do not imply a detected acoustic speech-onset time.
- Command processing duration, record time, and app version/build. Command
  processing begins after final transcription, so it must not be reported as
  speech latency.
- An ephemeral random launch-session identifier. It groups records written by
  one app process and makes accidental concurrent instances detectable; it is
  regenerated on launch and is not a device or user identifier.

Topher does not separately capture or append raw audio, partial transcripts,
the complete speech-alternative list, microphone buffers, retrieved
browser/screen/message/document context,
constructed destination URLs, detailed framework errors, Keychain/config
values, or arbitrary error text. The exact user-authored request can itself
contain a query, URL, pasted content, credential, or error string. Dictation
aimed at a secure field is refused before capture; if the field becomes secure
during a hold, the final text is discarded without a preview or trace record.

The JSON file is:

```text
~/Library/Caches/dev.topher.app/TranscriptDiagnostics/transcript-diagnostics.json
```

The latest three menu records expose an **Action** rating for commands or an
**Insertion** rating for dictation. Voice and dictation records also expose a
separate **Transcript** rating. Selecting an already-selected rating clears
that judgment.
Ratings use the same local file, permissions, retention, and **Clear Now**
semantics as the corresponding request.

When capture fails after producing a usable partial, the partial remains only
in the in-process manual field or dictation preview. The persisted failure
record contains an empty transcript and a fixed capture-failure reason. It is
never silently executed or inserted. If a prepared dictation target becomes
secure, even that preview is discarded and no content-bearing record is made.

Summarize retained outcomes, feedback rates, insertion methods, verification,
target roles/application families, selection/placeholder/attribute decisions,
whole-value and semantic signal decisions, interpretation/polish reasons, and timing percentiles
without printing command text:

```sh
scripts/summarize_dogfood_diagnostics.rb
```

The summary prints the newest launch session first, labeled only with app
version/build, and then prints all retained history. This keeps the current
installed build's dogfood signal separate from older sessions without exposing
the random session identifier or transcript text.

Capability success is not a transcription-accuracy metric. The transcript
rating is useful dogfood evidence, while controlled corpus runs remain the
source of word-error-rate and proper-noun claims.

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
- Each raw or interpreted transcript is at most 4 KiB of valid UTF-8 and the
  record is marked when content is truncated.

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

## Dogfood query datasets

Topher keeps two intentionally different corpora:

- `dogfood/manual-corpus.json` is checked in. It contains sanitized, deliberate
  assistant, dictation, negative, and future-context cases with setup and
  expected-result notes. It is the shared human test menu and must not contain
  private observed speech.
- `.topher-local/dogfood/observed-queries.json` is gitignored local plaintext.
  It records bounded phrases the developer actually tried, aggregate outcome
  and rating metadata, and the builds in which they occurred. It is useful for
  deciding what the product should understand, not as a claim that a phrase is
  supported.

Validate and inspect the public corpus:

```sh
ruby scripts/check_dogfood_corpus.rb
ruby scripts/check_dogfood_corpus.rb --list
ruby scripts/check_dogfood_corpus.rb --list --mode dictation
```

Create or incrementally update the private corpus from the rolling trace:

```sh
ruby scripts/export_observed_queries.rb
```

The export is a deliberate developer action, not an app background task. It is
idempotent for already imported trace record IDs, merges duplicate phrases,
keeps at most 500 entries and 1 MiB, limits a phrase to 4 KiB, rejects unsafe
storage paths, and uses `0700` directories plus a `0600` file. It excludes
dictation by default because prose is more likely to contain private content;
`--include-dictation` is an explicit higher-sensitivity choice.

This second file is not covered by the trace's 24-hour rolling deletion.
Delete it deliberately when it is no longer useful. Never commit, publish, or
attach it without reviewing every phrase. Promote only sanitized, generally
useful cases into the checked-in manual corpus.

## Other places request text can exist

Raw microphone buffers are passed to Apple's local speech analyzer and are not
written to an audio file or project-owned cache. Speech text exists transiently
in Topher's process memory and visible UI until request processing or later UI
state replaces it. An unsupported dictation target can keep finalized text in
the in-process pending preview until the user clears it, replaces it with a
later result, or quits. **Copy** explicitly writes it to the system clipboard;
Topher never does so automatically. “Not in ordinary logs” is not the same as
“never held in memory.”

For searches, the query is sent to the selected provider when the default
browser opens Google or YouTube, and normal browser history or provider
retention may apply. Manual text remains visible in Topher's field and process
memory until changed or the app exits. The bounded developer trace adds the
bounded local copy described above; it does not change browser/provider
behavior.
