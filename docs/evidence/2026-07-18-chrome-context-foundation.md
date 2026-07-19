# Chrome context foundation evidence

Date: 2026-07-18

## Scope

This checkpoint adds the first structured Chrome context vertical slice:

- active regular-tab identification;
- bounded regular-tab listing;
- deterministic exact-title activation with ambiguity and staleness refusal;
- a Manifest V3 extension with only `tabs` and `nativeMessaging`;
- a bundled native-messaging relay and exact checked user registration helper;
- typed versioned protocol values, bounds, timeouts, cancellation, disconnect,
  and no-retry mutation behavior; and
- metadata-only bridge logging with no browser-returned content retention.

The trust and permission decision is recorded in
[decision 0013](../decisions/0013-structured-chrome-tab-context.md).

## Automated evidence

Focused Swift suites passed while the slice was implemented. They cover Core
title/URL/protocol validation, deterministic resolution and policy, provider and
capability behavior, exact matching, ambiguity, timeout, cancellation,
concurrency, stale snapshots, mismatched IDs/versions, native-host registration,
and processor exactly-once dispatch.

The complete Swift suite passed 206 tests normally and under Thread Sanitizer
with no sanitizer report. This includes an authenticated Unix-socket relay test
that rejects the wrong extension origin before exchanging framed data with the
exact registered origin and launch token.

The extension's dependency-free Node tests passed 11 tests covering manifest
permissions, URL/message validation, the composed 64-KiB response cap, bounded
listing, incognito and scheme exclusion, active-tab reads, fingerprint
revalidation, stale targets, duplicate activation IDs, and unknown outcomes
after mutation dispatch. The Ruby registration-helper suite passed 5 tests and
40 assertions covering exact install/check/uninstall behavior and symlink,
origin, extension-ID, path, ownership-mode, and replacement refusal.

Dependency parity, strict Swift formatting, Xcode Debug and universal Release
builds, Xcode static analysis, `git diff --check`, and a high-confidence staged
credential and sensitive-filename scan passed. The signed `0.4.0` build 9
Release contains:

```text
Topher.app/Contents/Helpers/TopherChromeBridgeHost
```

Both the app and helper are universal `arm64`/`x86_64` Mach-O executables. Deep
strict app-signature and strict helper-signature validation passed. The Release
app retains only its audio-input entitlement; the helper adds no browser,
network, Automation, Accessibility, Screen Recording, or App Sandbox
entitlement. A temporary-path install/check/uninstall round trip validated the
registration helper against the built bundle without changing the user's
Library. Executing the built host with an invalid caller produced only the
fixed `invalidCallerOrigin` failure and exited nonzero.

## Privacy and permission evidence

The checked extension manifest contains exactly `tabs` and `nativeMessaging`,
sets `incognito` to `not_allowed`, and has no host permissions, content scripts,
external messaging, storage permission, or fixed extension key. The app target
adds no Accessibility, Screen Recording, Automation/Apple Events, or network
entitlement. Tab titles, URLs, fingerprints, and detailed protocol errors are
absent from ordinary logging and are not appended to developer transcript
diagnostics.

## Unverified live acceptance

No unpacked extension was loaded into the user's Chrome profile, no native-host
manifest was installed in the user's Library, and no `/Applications` Topher
bundle was installed or changed during this checkpoint. Therefore this record
does not claim live Chrome service-worker/native-host connectivity, real tab
listing, real tab activation, Chrome restart recovery, or manual log inspection.

Use the focused checklist in
[`ChromeExtension/README.md`](../../ChromeExtension/README.md) for that separate
user-controlled acceptance pass.
