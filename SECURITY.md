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
- No arbitrary shell, AppleScript, browser JavaScript, or generated code runs.
- Permissions are requested incrementally for implemented features.
- Raw audio and screen captures are not persisted beyond the active request by
  default.
- Sensitive content is excluded from ordinary logs.
- The Chrome extension requests only `tabs` and `nativeMessaging`, cannot run in
  incognito, and has no host permissions, content scripts, scripting, DOM/page
  extraction, screenshots, cookies, history, forms, file-URL access, or stored
  browser snapshots. Native-host registration binds one exact extension origin
  to an absolute checked helper inside the current Topher bundle. Only the
  primary Topher process may construct the app-side relay.
- During the local dogfood phase, final voice/manual command text is retained by
  the bounded developer trace by default unless the user explicitly opts out.
  Recording is visibly indicated, stored with restrictive POSIX modes,
  automatically pruned, and immediately clearable. The command can itself
  contain a spoken or pasted credential; Topher never separately appends
  Keychain or configuration values. Revisit the default before distribution.
- Credentials belong in macOS Keychain and never in source control.
- Every effect requires capability-specific policy. An explicit, present-user
  request may itself confirm a capability-defined, bounded deterministic local
  handoff, such as the current typed web search. Sensitive remote, model- or
  context-derived, destructive, and other externally visible effects require a
  preview and separate confirmation.

See [Request lifecycle and context](docs/architecture/request-lifecycle.md) for
the planned trust boundaries.
