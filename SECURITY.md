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
- No arbitrary shell, AppleScript, browser JavaScript, or generated code runs.
- Permissions are requested incrementally for implemented features.
- Accessibility is requested only from an explicit dictation action. Focus,
  selection, immediate surrounding text, and secure-field state are revalidated
  before insertion; a mismatch fails to a local preview instead of mutating a
  guessed target.
- Accessibility mutation success is verified by bounded text readback instead
  of trusting the framework setter result. The plain-value adapter may
  transiently read at most 16,384 UTF-16 units and is restricted to writable
  text fields, empty text areas, or full-value text-area replacement. It is not
  used for web areas, partially selected nonempty text areas, or protected
  content, and the captured value is never logged or persisted separately.
- Dictation never synthesizes Return, submits, sends, or mutates the clipboard
  automatically. Copy is a separate explicit action, and guarded undo refuses
  to run after the focus, caret, or inserted content changes.
- Current dictation polish is an in-process bounded transform of finalized
  user-authored text. It acquires no screen/app content, uses no network or
  model, preserves the raw diagnostic form when recording is enabled, and has
  a persisted presentation-only switch. Recovered partials are never polished.
- Raw audio and screen captures are not persisted beyond the active request by
  default.
- Sensitive content is excluded from ordinary logs.
- During the local dogfood phase, final voice/manual command text and non-secure
  dictation are retained by the bounded developer trace by default unless the
  user explicitly opts out.
  Recording is visibly indicated, stored with restrictive POSIX modes,
  automatically pruned, and immediately clearable. The command can itself
  contain a spoken or pasted credential; Topher never separately appends
  Keychain or configuration values. Dictation aimed at a secure field is
  refused before capture; if the target becomes secure during the hold, Topher
  discards the final text without a preview or developer record. Revisit the
  default before distribution.
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
