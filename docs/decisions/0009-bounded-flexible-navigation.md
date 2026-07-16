# Decision 0009: Bounded flexible navigation

Status: accepted for local dogfooding, 2026-07-15

Dogfood build 5 showed that accurate transcription was reaching an overly
rigid deterministic layer. Exact known target names required an unnecessary
verb, destination-first searches such as “YouTube for dining with Derek” were
unsupported, and explicit public domains could only be searched. It also
showed that Chrome launch arguments activate an already-running Chrome without
delivering a `chrome://` route.

Build 6 keeps typed deterministic authority while expanding bounded language:

- Exact known application and website aliases may execute as terse commands.
- Known query providers may lead a query with `for`, `search`, comma, or colon
  forms. These rules do not apply to unknown destinations.
- A likely sentence-ending `.`, `?`, or `!` is removed from an extracted
  command query or domain only. The exact raw transcript remains unchanged,
  and future dictation does not inherit this normalization.
- Explicit navigation verbs may produce `HTTPSDomain`. This type accepts only
  public DNS-style hosts and always constructs HTTPS. It rejects paths,
  credentials, ports, IP addresses, non-HTTPS schemes, and local or reserved
  names. Known targets are resolved first.
- Browser-owned routes are sent as URLs to the registered application through
  `NSWorkspace`, which works for an existing instance; they are not passed as
  launch-only arguments.

Arbitrary application identifiers, paths, schemes, scripts, browser content,
and model-created URLs remain outside the command boundary. Capability success
means macOS accepted the handoff, not that Topher inspected or verified the
resulting browser page. End-to-end action correctness remains a separate
dogfood rating until a permissioned screen/browser context layer exists.
