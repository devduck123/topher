# 0013: Use a narrow MV3 and native-messaging bridge for Chrome tab context

- Status: accepted
- Date: 2026-07-18

## Context

Topher needs to answer which Chrome tab is active, list open tabs, and activate
one explicitly titled tab. `NSWorkspace` cannot supply tab identity.
Accessibility or screenshots would add broader permissions and less-structured
data, while AppleScript, browser JavaScript, and raw input synthesis violate the
control-path boundary. A Chrome extension can provide structured tab metadata,
but its titles and URLs are sensitive untrusted content and native messaging
adds a local process boundary.

## Decision

Ship a minimal unpacked Manifest V3 extension with exactly `tabs` and
`nativeMessaging`, plus `incognito: "not_allowed"`. Do not request host
permissions, `activeTab`, scripting, content scripts, storage, or external
messaging. Do not read the DOM, page body, screenshots, cookies, history,
forms, or file URLs.

Use a dedicated `TopherChromeBridgeHost` executable embedded in
`Topher.app/Contents/Helpers`. Chrome registration is an explicit checked local
development step. The native-host manifest contains one exact extension origin
in `allowed_origins` and an absolute path to that bundled helper. The app checks
the manifest, origin, path, file types, permissions, and helper executability
again before accepting a launch-scoped, same-user Unix-socket handshake. The
helper only relays bounded framed JSON; it owns no command resolution, policy,
tab matching, or persistent state.

Protocol version 1 uses application-owned Codable request and response values,
UUID request IDs, a 64-KiB application limit, a maximum 50-tab activation
snapshot, a 25-tab displayed list, fixed URL schemes, fixed title/URL bounds,
two-second read and three-second activation timeouts, four concurrent requests,
typed cancellation, socket handshake/send timeouts, no-signal socket writes,
explicit observation-completeness metadata, and fixed failure codes. Version
mismatch, malformed JSON, oversized fields or composed responses, unexpected
IDs, duplicate replies, and disconnects fail closed. The app-side socket starts
only for a resolved Chrome request, and only in the primary Topher process. No
tab snapshot is persisted or continuously mirrored.

Read-only active-tab and list operations are separate registered capabilities.
Activation is a low-risk reversible local mutation and a third registered
capability. It resolves an exact normalized user-authored title against a fresh
bounded list, refuses when eligible tabs exceeded the observation bound, refuses
zero or multiple matches, and sends only a typed tab/window identity, capture
time, and SHA-256 fingerprint. The extension fetches the tab again and compares
the identity, fingerprint, and age immediately before making one
`tabs.update(..., {active: true})` call and one `windows.update(...,
{focused: true})` call. Neither layer retries an activation after dispatch; a
timeout, disconnect, or API failure after mutation dispatch produces an explicit
unknown outcome.

Tab titles and URLs are untrusted data. They may be shown to the requesting user
and used for exact matching/fingerprinting, but cannot become commands, extend
authority, affect policy, or enter Unified Logging. Existing developer
diagnostics may retain the user's finalized command under their documented
bounds, but do not append browser-returned titles, URLs, fingerprints, or
detailed bridge errors.

## Consequences

- The first Chrome slice is useful without Accessibility, Screen Recording,
  Apple Events, host permissions, page injection, or an LLM.
- The extension's `tabs` warning is unavoidable for bounded whole-tab listing;
  `activeTab` cannot support listing all open titles and URLs without a separate
  browser gesture.
- Chrome can return all regular-profile tabs to `tabs.query`; Topher bounds
  processing and output but cannot make Chrome's API itself return a limited
  count.
- The persistent native port keeps the MV3 service worker and helper available,
  but neither acquires tab data while idle. The app-side socket/token is created
  only for the first resolved Chrome request. A helper process may therefore be
  present while Chrome runs even when Topher has not started its relay.
- Unpacked installation and exact native-host registration remain explicit
  local dogfood steps. This decision does not claim Chrome Web Store packaging,
  notarized distribution, or live Chrome acceptance.
- DOM/page understanding, feed questions, summaries, tab closing, navigation,
  and conversational tab references remain separate future decisions.

## Rejected alternatives

- Accessibility or screen capture for tab metadata.
- AppleScript, remote debugging, generated JavaScript, or `executeScript`.
- `<all_urls>`, content scripts, host permissions, or page-body collection.
- Continuously mirroring tabs or persisting browser history in Topher.
- Fuzzy title activation, first-match activation, or retrying a mutation after a
  disconnect.
- A general browser-agent protocol before this narrow bridge is dogfooded.

Primary platform evidence is listed in
[the upstream evidence ledger](../evidence/upstream-sources.md).
