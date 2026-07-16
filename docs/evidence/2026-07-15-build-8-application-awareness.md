# Build 8 application-awareness evidence

Date: 2026-07-15

## Scope

Build 8 adds:

- bounded launch-time discovery of installed macOS applications;
- exact typed installed-app commands with bundle-identifier revalidation;
- explicit app-versus-website precedence;
- a disclosed Google fallback for unknown generic navigation;
- fail-closed malformed addresses, ambiguous app names, and explicitly missing
  applications;
- a read-only frontmost-application capability;
- installed display names in bounded on-device recognition context; and
- latest-launch-session separation in the metadata-only dogfood summary.

The architecture and security contract is recorded in
[decision 0012](../decisions/0012-installed-application-resolution-and-fallback.md).

## Automated verification

The final normal suite passed:

```text
Executed 179 tests, with 0 failures (0 unexpected)
```

The same 179 tests passed under Thread Sanitizer with no sanitizer report.
Coverage added in this slice includes catalog depth, invalid bundle IDs,
symlink rejection, exact dynamic app matching, collision failure, app/site
precedence, malformed-address rejection, fallback query construction,
frontmost-app read behavior, policy metadata, catalog-provenance rejection,
and exactly-once dispatch.

Additional gates passed:

- `swift format lint --strict --recursive Sources Tests Package.swift`
- `ruby -c scripts/summarize_dogfood_diagnostics.rb`
- Xcode Debug build
- Xcode Release build
- Xcode Debug static analysis

The summary script was run against the retained local trace. It reported the
latest launch separately as version 0.3.0 build 7 with 4 records, followed by
all retained history with 69 records. It printed no transcript text or launch
session identifier.

## Release-bundle verification

The Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.3.0
CFBundleVersion = 8
LSUIElement = true
architectures = x86_64 arm64
```

Strict deep signature validation passed. Release entitlements contained only:

```text
com.apple.security.device.audio-input = true
```

No Accessibility, Screen Recording, Automation/Apple Events, or direct network
entitlement was added. Release remained a local ad-hoc Hardened Runtime build;
this is not distribution or notarization evidence.

## Installation and lifecycle

The checked installer atomically installed the verified Release bundle and
reported:

```text
Installed and launched Topher 0.3.0 (8) with one active process.
```

A forced second bundle launch was then attempted. The runtime lock rejected the
duplicate, and the process list still contained exactly one installed Topher
process.

## Remaining dogfood evidence

Automated validation proves the typed resolution and execution boundaries; it
does not prove live recognition quality or that every locally installed app has
the expected user-facing display name. The next user dogfood session should
include:

- several actually installed apps, including a developer tool and a consumer
  app;
- a known website that also has an app: generic, explicit `app`, and explicit
  `website` forms;
- an unknown generic target and confirmation that Topher visibly explains the
  Google fallback;
- an explicitly missing app and a malformed address, both of which should fail;
- “What app am I using?” while Topher's shortcut is used from another app; and
- transcript/action ratings for proper nouns that recognition gets wrong.

Installing or removing an application while Topher is already running requires
a Topher relaunch before the catalog changes. That is an intentional Build 8
session-determinism tradeoff, not a live-refresh claim.
