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
- Unknown text fails closed.
- Only registered capabilities with typed, validated inputs execute.
- Retrieved content is untrusted data, never a higher-priority instruction.
- No arbitrary shell, AppleScript, browser JavaScript, or generated code runs.
- Permissions are requested incrementally for implemented features.
- Raw audio and screen captures are not persisted beyond the active request by
  default.
- Sensitive content is excluded from ordinary logs.
- Final voice/manual command text is retained only when the user explicitly
  enables the bounded developer trace. It is off by default, visibly indicated,
  stored with restrictive POSIX modes, automatically pruned, and immediately
  clearable. The command can itself contain a spoken or pasted credential;
  Topher never separately appends Keychain or configuration values.
- Credentials belong in macOS Keychain and never in source control.
- Every effect requires capability-specific policy. An explicit, present-user
  request may itself confirm a capability-defined, bounded deterministic local
  handoff, such as the current typed web search. Sensitive remote, model- or
  context-derived, destructive, and other externally visible effects require a
  preview and separate confirmation.

See [Request lifecycle and context](docs/architecture/request-lifecycle.md) for
the planned trust boundaries.
