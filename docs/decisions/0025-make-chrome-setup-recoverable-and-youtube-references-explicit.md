# 0025: Make Chrome setup recoverable and YouTube references explicit

- Status: accepted
- Date: 2026-07-21

## Context

Decision 0024 established the correct privacy and authority boundary for a
YouTube Home feed, but Build 20 did not provide a complete user journey. The
native-host registration still required a developer to copy an unpacked
extension ID into a command-line helper, the extension was not bundled with the
app, and Topher had no readiness or repair surface. A user could therefore ask a
supported question and receive only a disconnected-bridge failure. Separately,
YouTube's current Home markup moved channel attribution into
`yt-content-metadata-view-model`, so the packaged extractor skipped otherwise
valid modern cards.

The result list also needs an honest interaction contract. “Open the third one”
and an exact title bind to a typed observed item. “Open that YouTube video” does
not identify one item when several recommendations are visible. An LLM cannot
recover information the user did not supply; allowing one to guess would weaken
the exact-target and exactly-once invariants.

Chrome's current documentation requires a macOS native-host manifest at the
per-user or system host location, an absolute native executable path, and an
exact extension origin in `allowed_origins`. Optional host permission requests
must occur from an extension user gesture. `chrome.scripting` requires both the
API permission and host access, and can run a packaged file in the isolated
world. A manifest `key` can provide a stable development extension ID.

## Decision

Give the unpacked development extension one repository-owned stable identity by
committing only its public manifest key. The corresponding extension ID is an
application-owned constant shared by Core, the registration controller, the
Ruby helper, and protocol tests. Never commit or distribute the private key; it
is unnecessary for loading the unpacked extension. Keep `allowed_origins` to
that one exact packaged origin.

Bundle the reviewed `ChromeExtension` directory as a read-only app resource.
Expose a Chrome-and-YouTube readiness card in the menu and General settings.
The app may inspect readiness at launch or activation, but it writes external
registration state only after the user presses **Set Up** or **Repair**. That
action creates or repairs only the exact per-user Topher native-host manifest,
with an absolute checked helper path and mode `0600`. It may repair an old
Topher path or pre-stable-ID Topher origin only when the existing manifest is a
secure current-user regular file with the same host name, `stdio` type, one
syntactically valid extension origin, and a path ending in Topher's exact app
helper layout. Symlinks, insecure modes, malformed data, multiple origins, and
non-Topher helper paths are refused rather than overwritten.

Topher does not silently install an extension, enable Chrome Developer mode,
or grant YouTube access. It provides fixed actions to open Chrome Extensions
and reveal the bundled extension folder, followed by three plain-language
steps. Optional YouTube access remains a separate explicit grant/removal in the
extension popup. Moving to a different Topher bundle path produces a repairable
readiness state.

Keep all extraction inside the existing fixed packaged file. Extend its
isolated channel selector seam with the current semantic metadata view-model
forms while retaining fixture-tested legacy selectors. Incomplete cards are
skipped and mark the bounded observation truncated; Topher does not widen the
schema or collect fallback text.

Make every displayed recommendation row an accessible application-owned button.
The button sends only its bounded ordinal through the same policy and registered
capability path as speech; it does not manufacture a transcript or bypass
revalidation. Voice and manual commands continue to support a listed ordinal or
one normalized exact title. Recognize the bare “that YouTube video” phrase, but
clarify that a number or exact title is required and preserve the current list.
Never guess a referent, use page content as instructions, or ask a model to
choose.

Do not add an LLM for this recovery. Deterministic parsing is sufficient for the
bounded intents and produces lower latency, no network disclosure, and an
auditable authority path. A future optional interpreter may propose an existing
typed command for fuzzier phrasing only after a measured corpus demonstrates a
material benefit. It still may not acquire page context, create a referent,
resolve ambiguity, grant permission, construct a URL, authorize policy, or
execute an effect.

## Consequences

- A built Topher app contains one discoverable extension folder and can safely
  establish or repair its own native-host registration without copied IDs or
  Terminal commands.
- Chrome still requires the user to load or reload the unpacked extension, and
  the user separately controls optional YouTube access. Topher's readiness row
  describes registration, not proof that Chrome has loaded the extension or
  granted page access.
- The public manifest key deliberately makes the unpacked development ID
  reproducible. It is identity, not a secret or publisher signature. A future
  Chrome Web Store distribution must use its own protected signing and release
  process.
- Current and legacy channel markup are covered by sanitized structural
  fixtures. Future YouTube DOM drift should fail as an incomplete/empty bounded
  observation rather than trigger a broader scrape.
- “That” is an explicit clarification path, not general conversational memory.
  Direct row actions and ordinal/title speech make the useful choice fast while
  preserving deterministic target binding.
- No screenshots, OCR, Accessibility page traversal, new origin, content
  persistence, model dependency, or browser-agent authority is introduced.

## Rejected alternatives

- Automatic Chrome extension installation, silent permission prompts, broad
  origin access, or registration during app launch.
- Asking users to discover and copy an unpacked extension ID for every build.
- Overwriting any manifest with a conflicting origin or unsafe ownership/mode.
- Generalized selectors, page-body fallback, remote debugging, screenshots, or
  model-generated extraction code when YouTube markup changes.
- Letting an LLM choose which listed item “that” means, using fuzzy title
  matching, or opening the first result.
- A model-first command router for an intent already handled by a bounded
  deterministic grammar.

## Relationship to earlier decisions

This decision completes the user-facing setup and recovery path around
decisions 0013 and 0024 without changing their protocol, privacy, permission,
staleness, or exactly-once boundaries. It adds no new page schema or browser
authority.

Primary platform evidence is listed in
[the upstream evidence ledger](../evidence/upstream-sources.md).
