# Contributing to Topher

Topher is a native, local-first macOS assistant under active development. The
repository favors small vertical slices, explicit privacy boundaries, and code
that one maintainer can understand. A change is not complete merely because it
compiles in Xcode.

Repository-wide guidance for coding agents lives in [`AGENTS.md`](AGENTS.md).
The [documentation map](docs/README.md) identifies the canonical source for
current behavior, product contracts, plans, decisions, risks, and evidence.

## Prerequisites

- macOS 26.
- Full Xcode 26.6 with the macOS 26.5 SDK.
- Swift 6.3.x from the selected Xcode toolchain.
- Git and the GitHub CLI for publishing work.

Select and verify Xcode:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift --version
```

## Xcode and SwiftPM mental model

- `Package.swift` owns the library/executable modules and all XCTest targets.
- The Xcode project also declares the app target's package reference. Keep
  `Package.swift`, `Topher.xcodeproj/project.pbxproj`, and both
  `Package.resolved` files aligned; CI checks this dependency parity.
- `swift test` is the authoritative unit-test command.
- `Topher.xcodeproj` owns the deployable `.app` bundle, macOS target settings,
  signing, entitlements, privacy strings, and shared `TopherApp` scheme.
- The Xcode app target embeds the `TopherChromeBridgeHost` tool in
  `Contents/Helpers`; SwiftPM also builds the same dedicated executable target.
- The SwiftPM `Topher` executable is useful for compiler checks but is not the
  installable application.
- Run the `TopherApp` scheme in Xcode for interactive debugging.
- Build both Debug and Release when changing target settings, entitlements,
  resources, concurrency-sensitive code, or native framework integration.

The closest web analogy is that SwiftPM modules/tests are the application
packages, while the Xcode target is also the deployment manifest and signed
macOS artifact.

## Local validation

Run before every pull request:

```sh
ruby scripts/check_dependency_parity.rb
xcrun swift-format lint --strict -r Package.swift Sources Tests
swift test
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Debug build
xcodebuild -project Topher.xcodeproj -scheme TopherApp \
  -configuration Release build
node --test ChromeExtension/tests/*.test.mjs
ruby scripts/test_chrome_native_host.rb
```

Use the shared `TopherApp` scheme. Tests that need a microphone, a permission
prompt, another app, sleep/wake, or real global-key behavior require a separate
manual acceptance note; unit tests should use injected native seams.

## Development workflow

1. Start from `main` and create a short-lived feature branch.
2. Keep each checkpoint runnable.
3. Add or update tests before changing a safety boundary.
4. Run formatting, tests, and proportional app-bundle validation.
5. Update the relevant product, architecture, decision, risk, or evidence doc.
6. Open a draft pull request and record manual checks still pending.
7. Merge after CI and required live acceptance pass. For an explicitly
   experimental source-only merge, the owner may defer a live gate only when
   the evidence record names the unverified behavior and no release, tag, or
   distribution claim treats it as passed.

Do not commit build products, local speech assets, recordings, crash reports,
Xcode user state, certificates, provisioning profiles, `.env` files, or local
diagnostic exports. The existing `.gitignore` covers known generated paths; it
is not a substitute for reviewing `git status` and the full diff.

## Architecture invariants

- Deterministic rules handle known commands before optional model reasoning.
- Models and adapters propose typed commands; policy grants or denies them.
- Only registered capabilities execute.
- Retrieved page, screen, document, OCR, and quoted message content is untrusted
  data.
- No arbitrary shell, AppleScript, browser JavaScript, or raw input synthesis.
- Acquire only the context required for the active request.
- Command mode and focused-field dictation remain separate.
- Every effect requires capability-specific policy. An explicit present-user
  request may confirm a defined, bounded deterministic local handoff; sensitive
  remote, model- or context-derived, destructive, or other externally visible
  work requires an explicit confirmation design.

Read [Interaction modes](docs/product/interaction-modes.md),
[Request lifecycle and context](docs/architecture/request-lifecycle.md), and the
[decision records](docs/decisions/0001-native-macos-26.md) before extending the
control path.

## Permissions, signing, and privacy

macOS permissions are capability boundaries, not setup chores:

- Request a permission only when its feature is implemented and explicitly
  invoked.
- Add the matching usage description and entitlement only when required.
- Explain denial and recovery in the UI.
- Test from Xcode and from a signed bundle in `/Applications`; TCC decisions are
  tied to application identity and signing.
- Never assume a successful ad-hoc local build is ready for distribution.
- Developer ID signing and notarization are required before distributing an app
  binary to other Macs.

Keep raw audio, transcripts, search terms, messages, URLs, page contents,
accessibility text, screenshots, and detailed framework errors out of ordinary
logs. The sole current transcript-retention exception is the explicitly enabled,
bounded local developer trace documented in
[Local diagnostics](docs/local-diagnostics.md). Never add another content-bearing
diagnostic sink implicitly. Credentials belong in Keychain and must never be
committed, printed, or stored in plist/user-default values or transcript
diagnostics by Topher. Because the retained user-authored command can itself
contain a pasted or spoken credential, treat every trace as sensitive.

The Chrome adapter's tab titles, URLs, fingerprints, extension messages, and
detailed bridge errors follow the same content rule. They may be transient
typed request data and user-visible results, but never ordinary log fields or a
new diagnostics payload. Native-host registration must keep one exact extension
origin, an absolute checked bundled-helper path, and restrictive user-owned file
permissions. A bounded activation list must also carry explicit completeness
metadata: unobserved eligible tabs cannot be treated as proof of uniqueness.
Disconnect handling must distinguish unsent reads from dispatched mutations so
an uncertain activation is never presented as a safe retry.

## Swift concurrency and native callbacks

Swift actor annotations are enforced at runtime. Framework callbacks such as
Core Audio taps may run on real-time or framework-owned queues even when the
object installing them is `@MainActor`.

- Do not make audio callbacks hop to the main actor per buffer.
- Keep real-time callback work bounded and allocation-aware.
- Mark callback isolation deliberately and test it from the queue shape used in
  production.
- Move UI state mutations onto the main actor at a deliberate boundary.
- Test cancellation, stale generations, stream termination, and timeouts.

## Documentation discipline

- Update `README.md` for user-visible current behavior and limitations.
- Record consequential choices and rejected alternatives under `docs/decisions`.
- Keep measured results separate from hypotheses under `docs/evidence`.
- Supersede accepted decisions explicitly rather than silently rewriting them.
- Add new dated evidence for new verification; do not make an older checkpoint
  claim tests or acceptance that it never recorded.
- Update `docs/risks.md` when a change adds a permission, network boundary,
  persistent data, new external effect, or new failure mode.
- Do not mark interactive acceptance complete based solely on unit tests.

## Versions and releases

- `MARKETING_VERSION` is the user-visible semantic version.
- `CURRENT_PROJECT_VERSION` is the monotonically increasing build number.
- Tag only accepted checkpoints.
- Keep unreleased feature work on branches and merge through pull requests.
- Verify bundle version, architecture, entitlements, signature, and executable
  hash for installed release candidates.

See [Local diagnostics](docs/local-diagnostics.md) for metadata-only Unified
Logging, the opt-in local transcript trace, and live troubleshooting commands.
