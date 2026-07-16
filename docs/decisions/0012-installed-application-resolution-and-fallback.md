# 0012: Resolve installed applications by exact catalog identity

- Status: accepted
- Date: 2026-07-15

## Context

Topher's fixed application enum proved the typed capability path, but it could
not scale to ordinary requests such as “Open Figma” or “Open Spotify.” Treating
every unknown noun as an application name would require either a continuously
growing allowlist or a model-provided bundle identifier. Treating it as a
domain would incorrectly invent destinations such as `spotify.com`.

Some names legitimately describe both a native app and a website. The product
also needs useful behavior when no exact destination is known, without making a
silent guess that looks like successful intent understanding.

## Decision

Topher captures a deterministic installed-application catalog once at launch.
It scans only conventional macOS application roots and one child-directory
level, ignores symlinked app bundles, requires a valid bundle identifier, and
deduplicates identities. Installed display names are supplied to on-device
speech recognition as bounded contextual terms.

The resolver accepts normalized exact aliases only. A discovered application
command carries its display name and bundle identifier, not an application
path or launch arguments. `ApplicationOpenCapability` re-resolves the bundle
identifier through `NSWorkspace` immediately before opening the app. The
independent `CommandPolicy` also requires the exact catalog-issued target
identity from the same launch; reconstructing a value with the same public
bundle identifier is still denied before capability execution.

Precedence is deterministic:

1. `app`, `application`, or `desktop app` explicitly requests a unique installed
   application and fails clearly when none exists.
2. `site` or `website` explicitly requests web behavior.
3. Generic known website brands win over similarly named installed apps.
4. Other unique installed-app names open natively.
5. An unknown generic navigation target becomes a typed Google-search fallback
   with a visible explanation; Topher never guesses a domain.

Malformed address-shaped values and ambiguous installed application aliases do
not use the fallback. They remain unsupported.

The first native context command, “What app am I using?”, is a separate
read-only capability backed by `NSWorkspace.frontmostApplication`. It does not
request Accessibility or Screen Recording permission and does not expose
windows, tabs, or screen contents.

## Consequences

- Common installed apps work without per-app source changes or an LLM.
- A model cannot turn output into a path, process argument, or arbitrary
  application launch through this resolver.
- Website/app collisions have predictable user-controllable behavior.
- Unknown navigation remains useful but explicitly distinguishable from an
  understood app or website action.
- Installing or removing an app while Topher is running takes effect after the
  next Topher launch; this preserves session determinism and avoids a catalog
  watcher before there is evidence one is needed.
- Exact matching may miss colloquial or mis-transcribed app names. Personal
  vocabulary, speech alternatives, and later constrained interpretation can
  improve phrasing while preserving the same typed catalog boundary.
