# Security policy

Topher controls local applications and is expected to handle microphone,
browser, message, document, accessibility, and screen data over time. Security
and privacy regressions are product defects even when they do not resemble a
traditional server vulnerability.

## Reporting a vulnerability

Do not include credentials, private recordings, transcripts, screenshots,
documents, message contents, or other sensitive data in a public issue.

Use GitHub's private vulnerability-reporting flow from the repository Security
tab. If that flow is unavailable, contact the repository owner through GitHub
before sharing sensitive reproduction material.

Public issues are appropriate for non-sensitive bugs and hardening ideas.

## Current support

Security fixes target the latest `main` revision and the locally dogfooded
development build. There is not yet a notarized public binary release.

## Security invariants

- Models propose; application policy authorizes.
- Non-command text, malformed address-like input, ambiguous app names, and
  explicitly missing applications fail closed. An explicit generic navigation
  request may use the registered Google-search fallback and must disclose that
  fallback visibly.
- Only registered capabilities with typed, validated inputs execute.
- Installed applications come from a bounded launch-time catalog. Speech or
  future model output never becomes an application path, launch argument, or
  free-form bundle identifier; the executor re-resolves catalog identities
  through macOS, and independent policy requires the exact target identity
  issued by the captured launch catalog.
- Retrieved content is untrusted data, never a higher-priority instruction.
- Chrome tab titles and URLs are untrusted retrieved data. Exact-title matching
  can select only one fresh typed tab identity after the adapter proves its
  bounded eligible-tab observation was complete; it cannot create a command,
  navigate, close, reload, submit, or bypass policy.
- YouTube titles, channels, video IDs, and observation metadata are untrusted
  retrieved data. They are length/count/schema validated, never interpreted as
  instructions, and live only in one 90-second in-memory feed session. Ordinal
  selection is limited to that list; normalized exact-title selection refuses
  ambiguity and incomplete observations. The extension revalidates optional
  permission, active source tab/page/fingerprint, expiry, and selected-item
  presence before one navigation constructed from a strict video ID.
- A bare reference such as “that YouTube video” cannot select among multiple
  observed items. Topher requests a listed ordinal or exact title and preserves
  the short-lived list; neither deterministic fallback nor a future model may
  guess the referent.
- No arbitrary shell, AppleScript, browser JavaScript, or generated code runs.
- Permissions are requested incrementally for implemented features.
- Accessibility is requested only from an explicit dictation action. Focus,
  selection, immediate surrounding text, and secure-field state are revalidated
  before insertion; a mismatch fails to a local preview instead of mutating a
  guessed target.
- Accessibility mutation success is verified by bounded text readback instead
  of trusting the framework setter result. The plain-value adapter may
  transiently read at most 16,384 UTF-16 units and is restricted to writable
  text fields, empty text areas, full-value text-area replacement, or an
  object-free web-descendant text area whose existing value is at most 4,096
  UTF-16 units and whose caret is exactly at the value end, except for the
  separately proven Codex/ChatGPT semantic-empty case and bounded Notion
  single-line caret case below. The bounded web
  ancestor, placeholder state, and attributed-value classification must be
  observed before capture and revalidated immediately before mutation. Uniform
  presentation and varying spellcheck metadata are permitted; placeholder-
  backed values, unproven start/middle/partial selections outside that Notion
  case, attributes exposing links,
  attachments, or list markers, styled/mixed/unknown attributes,
  oversized/cyclic/structurally changing web
  composers, native partially selected nonempty text areas, and protected
  content fail closed. Captured values and attributes are never logged or
  persisted separately. A Notion start/middle caret may use whole-value
  insertion only when the value is single-line, object-free, length-bounded,
  uniformly presented, unchanged, and exactly verified afterward.
- Dictation never synthesizes Return, submits, sends, or mutates the clipboard
  automatically. Copy is a separate explicit action, and guarded undo refuses
  to run after the focus, caret, or inserted content changes.
- Current dictation polish is an in-process bounded transform of finalized
  user-authored text. It acquires no screen/app content, uses no network or
  model, preserves the raw diagnostic form when recording is enabled, and has
  a persisted presentation-only switch. Transient word timing may authorize
  only the fixed short-pause allowlisted-continuation rule and is never
  retained. An Apple alternative may replace dictation only when it uniquely
  equals a configured vocabulary correction; unrelated prose changes are
  rejected. Recovered partials are never polished.
- When the system-wide focused element is unavailable, dictation may query only
  the current frontmost application's focused element and must preserve that
  process identity through mutation verification. Codex/ChatGPT suggestion text
  may be replaced only when bounded semantic Accessibility evidence proves the
  logical composer is empty or the entire bounded value exactly equals the
  observed app-owned suggestion. Suggestion attributes, character count,
  text-marker state, and the exact compatibility classification are evaluated
  independently and revalidated; missing, mixed, marked, changed, or ordinary
  authored evidence fails closed. Terminal input never falls back to synthesized
  keys, paste, or command execution.
- Raw audio and screen captures are not persisted beyond the active request by
  default.
- Sensitive content is excluded from ordinary logs.
- During the local dogfood phase, final voice/manual command text and non-secure
  dictation are retained by the bounded developer trace by default unless the
  user explicitly opts out. An exact-title follow-up can therefore retain the
  title the user authored, but feed results, channels, video IDs, source URLs,
  and constructed destinations are never appended.
- The Chrome extension requires only `tabs`, `nativeMessaging`, and `scripting`;
  cannot run in incognito; and declares only optional
  `https://www.youtube.com/*` host access. That permission is requested or
  removed only from the extension popup's explicit user gesture. `scripting`
  runs only the fixed packaged YouTube Home extractor in the isolated world.
  There are no content scripts, required host permissions, screenshots, OCR,
  cookies, history, account data, comments, descriptions, forms, file-URL
  access, arbitrary/page/model-generated JavaScript, continuous observation,
  or stored browser snapshots. Native-host registration binds one exact
  packaged extension origin to an absolute checked helper inside the current
  Topher bundle. The committed manifest key is public development identity,
  not a credential; its private key is not stored. Readiness inspection does
  not mutate external state. Only an explicit **Set Up** or **Repair** action
  may create or update the per-user manifest, and only when an existing
  manifest is absent or is a secure current-user Topher registration with one
  valid origin and the exact Topher app/helper path shape. This permits
  explicit migration from a pre-stable-ID Topher build. Multiple origins,
  non-Topher helper paths, symlinks, insecure modes, and malformed data are
  refused. Setup never loads the extension or grants page access. Only the
  primary Topher process may construct the app-side relay.
  Recording is visibly indicated, stored with restrictive POSIX modes,
  automatically pruned, and immediately clearable. The command can itself
  contain a spoken or pasted credential; Topher never separately appends
  Keychain or configuration values. Dictation aimed at a secure field is
  refused before capture; if the target becomes secure during the hold, Topher
  discards the final text without a preview or developer record. Revisit the
  default before distribution.
  Preparation and insertion evidence may retain one fixed application family,
  focus source, failure reason, and structural/semantic enums for local
  compatibility testing; it never retains a raw bundle ID, process ID, window
  title, URL, selected text, suggestion text, or additional field content.
- A developer may explicitly copy recent trace records into the bounded,
  gitignored `.topher-local/dogfood/observed-queries.json` corpus. Topher never
  creates this second sink automatically, the exporter excludes dictation
  unless explicitly requested, and owner-only modes reduce accidental local
  exposure. It remains durable plaintext until deliberately deleted; never
  commit or publish it. Public regression cases belong in the sanitized
  `dogfood/manual-corpus.json` corpus.
- Credentials belong in macOS Keychain and never in source control.
- Every effect requires capability-specific policy. An explicit, present-user
  request may itself confirm a capability-defined, bounded deterministic local
  handoff, such as the current typed web search. Sensitive remote, model- or
  context-derived, destructive, and other externally visible effects require a
  preview and separate confirmation.

See [Request lifecycle and context](docs/architecture/request-lifecycle.md) for
the planned trust boundaries.
