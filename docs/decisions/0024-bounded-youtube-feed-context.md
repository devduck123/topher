# 0024: Add bounded YouTube feed context behind optional origin access

- Status: accepted
- Date: 2026-07-19

## Context

The metadata-only Chrome foundation can identify and activate tabs, but cannot
answer the useful screen-context request “What’s on my YouTube feed?” A generic
DOM bridge, screenshot/OCR pipeline, Accessibility fallback, or browser agent
would expose substantially more content and authority than this request needs.
Chrome requires both `scripting` and host access to inject a packaged extractor.
Optional host permission must be requested from an extension user gesture, not
silently from Topher's voice-command path.

Recommendations are sensitive and untrusted. YouTube's DOM can drift or lazy
load; Manifest V3 service workers can suspend or restart; permission can be
denied or revoked; and the page can change between observation and a follow-up.
An ordinal or title reference must therefore carry bounded provenance and must
not turn page data into navigation authority.

## Decision

Extend the Chrome protocol to version 2 and add exactly two registered
capabilities: read the active YouTube Home feed and open one item from the
latest feed. Deterministic resolution handles only the reviewed feed phrases,
ordinals 1 through 20, and an explicit “YouTube video titled X” form. No model
is required or allowed to authorize either capability.

Add required `scripting` and only optional
`https://www.youtube.com/*`. Chrome's host-pattern model cannot express one
path, so the service worker separately accepts only the exact HTTPS
`www.youtube.com` Home route. The extension action popup explains the fields,
checks current permission, and offers explicit grant and removal controls.
Only its buttons call `chrome.permissions.request` or `.remove`; denied,
revoked, and missing permission states return a fixed actionable failure.

Run only the reviewed packaged `youtube_feed_extractor.js` with
`chrome.scripting.executeScript`, in the isolated world and top frame. Never
execute a string or function supplied by the user, page, app response, or
model. The extractor scans a fixed bounded card set with isolated semantic
selectors and returns at most 20 visible or nearby records. Each record crosses
the bridge only as a strict 11-character video ID, bounded normalized-whitespace
title, bounded channel, ordered position, and SHA-256 observation ID. The
snapshot also carries capture/expiry times, source tab/window, strict Home URL,
source fingerprint, feed observation ID, and explicit truncation/completeness.
Malformed, duplicate, empty, oversized, credential-bearing, unsupported, or
control-character data fails closed.

Keep one feed snapshot in app memory for no more than 90 seconds and show it as
an accessible numbered menu card with an explicit clear action. Do not write it
to extension storage, UserDefaults, ordinary logs, exports, or developer
diagnostics. The existing explicitly enabled dogfood trace may retain the
user-authored command, including a title the user repeats, but never appends the
browser-returned snapshot or destination. Expiry, clear, failed refresh, or a
dispatched open removes the session.

Ordinal selection resolves only to a displayed position. Title selection uses
normalized exact matching, refuses zero or multiple matches, and refuses any
truncated observation because unseen duplicates cannot be excluded. Before one
mutation, the extension rechecks optional permission, current time, active
source tab/window, exact Home route, source fingerprint, and selected
video/observation presence in a fresh extraction. It constructs
`https://www.youtube.com/watch?v=VIDEO_ID` itself and calls
`tabs.update` exactly once. Page-provided URLs never cross the mutation
boundary. The app consumes the session before dispatch; timeout, native-host
disconnect, or Chrome failure after dispatch is an unknown outcome and is
never automatically retried.

No state required to authorize an open lives in the MV3 service worker. Its
bounded duplicate cache may disappear on suspension, so exactly-once behavior
does not depend on restart persistence: the app uses unique IDs, does not replay
a dispatched mutation, and requires a new feed after any unknown outcome.

## Consequences

- Topher gains useful screen-aware assistance without Screen Recording,
  Accessibility page traversal, OCR, cookies, history, or a general DOM API.
- The required `scripting` warning applies to the extension, while actual page
  access remains an explicit removable exact-origin permission.
- YouTube DOM changes can make reads unavailable. Selector coupling is isolated
  in one fixture-tested file, and failure asks the user to let Home load or try
  again rather than widening access.
- A 90-second session is deliberately shorter and less capable than general
  conversational memory. It can open only one observed YouTube item and cannot
  authorize another command or URL.
- Live Chrome/YouTube permission, lazy-load, restart, and DOM acceptance remains
  a manual gate; automated fixtures are not evidence of the user's current
  feed.

## Rejected alternatives

- `<all_urls>`, required YouTube host access, broader YouTube origins, or a
  persistent content script.
- `activeTab` alone: the voice request is not an extension action user gesture,
  and it would not provide understandable durable grant/revoke state.
- Screenshot, OCR, Screen Recording, Accessibility, or remote-debugging
  extraction.
- Page-authored, user-authored, or model-generated JavaScript; arbitrary CSS
  selector requests; or a generic DOM protocol.
- Returning page-provided watch URLs, opening the first fuzzy title match, or
  allowing a truncated title match.
- Persisting feed data, continuously mirroring the page, or sending it to a
  model/cloud provider.
- Retrying navigation after a timeout, disconnect, service-worker restart, or
  ambiguous Chrome API outcome.

## Relationship to earlier decisions

This is a deliberate permission and context expansion from decision 0013. It
preserves that decision's native-host authentication, message bounds,
primary-process relay ownership, typed cancellation, sensitive logging rules,
and non-retried mutation invariant. Decision 0013 remains the historical record
for the metadata-only protocol version 1 boundary.

Primary platform evidence is listed in
[the upstream evidence ledger](../evidence/upstream-sources.md).
