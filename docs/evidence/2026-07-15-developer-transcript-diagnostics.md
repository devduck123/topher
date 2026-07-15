# Developer transcript diagnostics verification

Date: 2026-07-15

Source base: `4cbbf3a`. This record travels with the implementation commit on
`feat/assistant-pipeline-foundation`; the PR history identifies the resulting
source revision.

This record covers the explicitly enabled local developer trace for recent
final voice/manual commands. It does not turn transcript text into ordinary
application logging, telemetry, conversation history, or model memory.

## Implemented contract

- Recording defaults off, requires a warning and confirmation, persists only
  the enabled boolean, and shows an orange menu-bar/diagnostics indicator while
  active.
- Only the trimmed final command is eligible. Partial speech, raw audio, and
  microphone buffers are never records. Each record also contains a fixed
  source, typed outcome, command kind/capability identifier when available,
  processing duration, timestamp, and app version/build.
- Topher does not separately append retrieved page/screen/message/document
  context, constructed URLs, Keychain/config values, detailed errors, or
  arbitrary failure payloads. The exact user-authored command can itself
  contain a query, URL, pasted content, credential, or other sensitive text.
- Records use disposable plaintext JSON in the user Caches domain. Directories
  are mode `0700`, the file is mode `0600`, both are excluded from backup, and
  unsafe symlinked, differently owned, non-regular, or multiply linked paths
  are rejected.
- All retention limits apply together: 24 hours, newest 200 records, 1 MiB
  encoded file, and 4 KiB valid UTF-8 per transcript. The per-record limit is
  re-applied when existing JSON is loaded, not only when Topher creates a new
  record.
- Cleanup runs on load, refresh, writes, setting changes, and hourly while the
  app runs. Disabling stops new/queued writes without deleting existing
  evidence; **Clear Now** invalidates queued writes and removes retained data.
- Failed new-record persistence rolls back that transcript. A later retry can
  restore only the previous record set or finish cleanup. Pending cleanup
  remains visible and clearable even after recording is disabled.
- Diagnostics storage failures do not change the assistant command outcome.
  Unified Logging receives only fixed metadata-only failure messages.

## XCTest coverage

The current tree defines 110 tests, including 15 focused
`DeveloperDiagnosticsStoreTests` and model-level integrations. The store cases
cover:

- opt-out/no-storage behavior and explicit enabling;
- private POSIX permissions and backup exclusion in the real user Caches
  domain;
- age, count, encoded-file, per-transcript, and Unicode-safe bounds;
- re-applying and persisting the transcript bound across reload;
- launch/reload pruning, corrupt documents, and unsafe symlink defense;
- disable/clear generation invalidation and queued late writes;
- concurrent writes under actor isolation;
- failed record rollback, pending-cleanup visibility, and recovery.

Model tests verify that only final voice text is retained, partial text is not,
successful manual commands carry manual source and typed success metadata, and
a diagnostics write failure never changes the user-visible command result.

## Executed validation

Before the final decoded-record normalization guard and its 110th test were
added, the production implementation passed:

- `swift test`: 109/109, zero failures.
- `swift test --disable-sandbox`: 109/109, zero failures, including backup
  exclusion in the user Caches domain.
- `swift test --sanitize=thread`: 109/109, zero failures and no reported data
  race.
- strict recursive `swift-format`, `git diff --check`, and dependency parity.

An earlier diagnostics candidate, before the pending-maintenance visibility and
decoded-record reload guards, also passed `TopherApp` Debug compilation, Xcode
analysis, and a signed universal Release app build. That artifact is stale and
is not the candidate to install or use as final bundle evidence.

For the final reload hardening in the current tree:

- `DeveloperDiagnosticsStore.swift` passed direct Swift 6 type checking.
- A focused executable smoke wrote an oversized valid record under a permissive
  policy, reloaded it under a 5-byte policy, verified Unicode-safe truncation
  plus the truncation marker, and verified the normalized document persisted
  across a second reload.
- Strict recursive formatting and `git diff --check` passed.
- A final independent diff review found no remaining code, privacy,
  concurrency, or documentation blocker.

The final decoded-record guard was added after the complete local runs above.
Therefore the full 110-test run and final `TopherApp` bundle build are still
required before this branch is merge-ready. Do not substitute the similarly
named SwiftPM `Topher` executable for the deployable `.app` bundle.

## Remaining publish gates

1. Run `swift test` and `swift test --sanitize=thread`; expect 110/110.
2. Run CI's `TopherApp` Release build and a fresh locally signed universal app
   build from the final source commit.
3. Inspect strict/deep signature validity, Hardened Runtime, `arm64` plus
   `x86_64`, bundle ID/version/build, `LSUIElement`, minimum macOS version, and
   the audio-input-only Release entitlement; record the final executable hash.
4. Install that exact candidate in `/Applications`, verify launch and process
   liveness, and retain a rollback copy.
5. Manually confirm enable warning/confirmation, orange indicator, final-only
   records, disable preservation, **Clear Now**, and hourly/next-launch cleanup.

Physical-microphone accuracy and the broader supported-command corpus remain
separate dogfood work; this diagnostics slice makes that future evidence much
easier to inspect without weakening ordinary-log privacy.
