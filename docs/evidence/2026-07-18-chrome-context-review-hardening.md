# Chrome context review hardening evidence

Date: 2026-07-18

This checkpoint records the post-review hardening of the structured Chrome tab
vertical slice. It supplements rather than rewrites the original Chrome context
foundation evidence.

## Review findings addressed

1. A secondary Topher process could construct its Chrome relay before
   single-instance ownership was known, allowing it to replace the primary
   process's launch-scoped socket or token.
2. Activation matching considered only the returned bounded tab list. A second
   otherwise eligible matching tab beyond that bound could therefore be missed.
3. A native-host disconnect after an activation request was dispatched was
   reported as ordinary bridge unavailability even though the activation
   outcome could no longer be known safely.

The app now constructs the live Chrome runtime only for the primary process and
starts its relay lazily on the first Chrome request. The versioned list response
contains explicit observation-completeness metadata; activation refuses before
mutation when eligible supported tabs existed beyond the returned bound.
Unsupported or incognito tabs inspected by the bounded scan do not make the
supported observation incomplete, and the extension does not fingerprint titles
or URLs that it will not return. If the scan itself reaches its safety cap, the
extension conservatively reports an incomplete observation.
The extension also rechecks snapshot age immediately before mutation. The
broker retains operation and dispatch state so a post-dispatch activation
disconnect becomes a fixed unknown-outcome refusal rather than a retryable
availability error.

## Automated validation

The hardened tree passed:

- `swift test`: 210 tests.
- Thread Sanitizer `swift test`: 210 tests with no sanitizer report.
- dependency-free extension protocol tests: 13 tests.
- native-host registration helper tests: 5 runs and 40 assertions.
- dependency parity and strict recursive Swift formatting checks.
- Xcode Debug build, universal Release build, and static analysis.
- `git diff --check`.

The Release app and bundled helper are universal `arm64`/`x86_64` Mach-O
executables. Deep strict app-signature and strict helper-signature validation
passed. The app retains only its audio-input entitlement; the helper has only
the empty application-identifier entry produced by the local development
signature and adds no browser, network, Automation, Accessibility, Screen
Recording, or App Sandbox entitlement.

An isolated `/tmp` native-host install/check/uninstall round trip validated the
exact extension origin and absolute bundled-helper path without changing the
user's Library. Running the helper with an invalid caller produced only the
fixed `invalidCallerOrigin` failure and exited nonzero.

The installed `/Applications/Topher.app` was already the primary process. A
single launch of the isolated `/tmp` Release app exited as the secondary; a
process check confirmed that the original installed app remained the sole
Topher process. The installed app was not stopped, replaced, or modified.

## Still requires manual Chrome acceptance

This checkpoint did not install or enable the unpacked extension, register a
host in the user's Library, or exercise real Chrome tabs. Manual acceptance is
still required for active-tab description, bounded tab listing, unique tab
activation, ambiguity refusal, more-than-50 eligible-tab refusal, stale-snapshot
refusal, extension disconnect and recovery, and incognito exclusion. No live
Chrome acceptance is claimed.

See [ADR 0013](../decisions/0013-structured-chrome-tab-context.md) for the trust,
permission, and protocol boundary.
