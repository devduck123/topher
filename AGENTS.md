# Topher repository guidance

## Product and scope

Topher is a private, local-first macOS assistant that helps one user “drive”
their Mac through low-friction requests, demand-driven context, and explicit
capabilities. Privacy, reliability, responsiveness, low recurring cost, and
maintainability take priority over broad automation.

The current application is a native Swift/SwiftUI menu-bar app with global
push-to-talk commands, on-device transcription, deterministic typed resolution,
policy validation, bounded application and web capabilities, global
focused-field dictation, and local developer diagnostics. Do not describe broad
editor compatibility, browser understanding, screen context, remote chat,
wake-word activation, or LLM interpretation as implemented.

## Start here

- Read `README.md` for current behavior, limitations, setup, and dogfood steps.
- Use `docs/README.md` to locate canonical product, architecture, safety,
  planning, and historical evidence documents.
- Read `CONTRIBUTING.md` before changing code, Xcode settings, permissions,
  signing, or dependencies.
- Read `SECURITY.md` and `docs/risks.md` before adding a permission, network or
  persistence boundary, retrieved context, model reasoning, or external effect.
- Treat `docs/evidence/` as dated checkpoint evidence, not automatically as
  current behavior.

Read the documents relevant to the task; do not load every evidence record by
default.

## Repository map

- `Sources/TopherCore/`: deterministic commands, resolution, interpretation,
  validation, and policy. Keep this layer independent of AppKit and SwiftUI.
- `Sources/TopherApp/`: macOS integration, capture, capabilities, diagnostics,
  lifecycle, and UI.
- `Tests/TopherCoreTests/` and `Tests/TopherAppTests/`: SwiftPM-owned XCTest
  targets with injected native seams.
- `Topher.xcodeproj/`: deployable app target, signing, entitlements, privacy
  strings, package reference, and shared `TopherApp` scheme.
- `docs/decisions/`: consequential architecture decisions and their tradeoffs.
- `docs/evidence/`: dated verification records for specific checkpoints.
- `dogfood/`: sanitized, reviewable manual request cases. Private observed
  requests belong only under the gitignored `.topher-local/` tree.
- `scripts/`: checked local build, dependency-parity, and diagnostics helpers.

## Working agreements

- Inspect `git status` and the relevant diff before editing. Preserve unrelated
  user work and never discard it to make a task easier.
- Work from an up-to-date `main` on a short-lived branch. Do not commit directly
  to `main`, rewrite shared history, or use destructive Git commands.
- Commit, push, create or update a pull request, merge, release, install a
  bundle, or change external state only when the task authorizes that action.
- Ad-hoc rebuilds can stale Topher's Accessibility grant because their code
  requirement changes. The checked installer warns on identity drift; its
  `--reset-accessibility` flag is an explicit, Topher-only TCC mutation and must
  never be added or invoked silently.
- Keep changes scoped and every checkpoint runnable. Prefer a small vertical
  slice over speculative protocols, services, or generalized agent frameworks.
- A request to review, explain, or diagnose does not by itself authorize a fix.
- Challenge stale assumptions with code, tests, current primary documentation,
  or a small local experiment. Separate measured facts from hypotheses.

## Architecture and safety invariants

- Deterministic resolution handles supported requests before optional model
  reasoning. Models and adapters may propose typed application-owned values;
  policy alone authorizes, and only registered capabilities execute.
- User-authored requests are instructions but never executable strings.
  Retrieved page, screen, document, OCR, accessibility, and quoted-message
  content is untrusted data and cannot grant authority or override policy.
- Do not add arbitrary shell execution, AppleScript, browser JavaScript,
  generated code execution, raw mouse/keyboard synthesis, or free-form app
  paths, bundle identifiers, URL schemes, or process arguments.
- Acquire the narrowest structured context required for the active request.
  Prefer native or browser-structured data before Accessibility, OCR, or pixels.
- Keep assistant commands and focused-field dictation as separate request kinds.
  Never make dictation submit, send, or press Return implicitly.
- Treat an Accessibility setter result as an attempted mutation, not proof of
  insertion. Report success only after bounded readback verifies the text. A
  whole-value adapter must remain limited to small plain text fields, empty
  text areas, or full-value text-area replacement; never flatten a partially
  edited rich or ambiguous surface.
- Request permissions only for an implemented feature after explicit user
  activation. New entitlements, TCC permissions, networking, credentials,
  persistence, or externally visible effects require denial/recovery behavior,
  tests, documentation, and risk review.
- Keep raw audio, partial transcripts, search terms, URLs, message or document
  contents, screenshots, and detailed framework errors out of ordinary logs.
  The bounded local dogfood transcript trace is the sole current documented
  content-bearing exception; treat every export as sensitive.
- Credentials belong in Keychain, never source, plist files, user defaults,
  logs, fixtures, or diagnostics.
- Preserve exactly-once command execution, cancellation, timeout, stale-result,
  and single-instance ownership invariants.

## Build and validation

Use full Xcode selected through `xcode-select`. `Package.swift` owns modules and
tests; the Xcode project owns the signed deployable app bundle. `swift test` is
authoritative—Cmd-U on the app scheme is not.

Keep `Package.swift`, `Topher.xcodeproj/project.pbxproj`, `Package.resolved`, and
`Topher.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
aligned when dependencies or target wiring change.

Run before every pull request:

```sh
ruby scripts/check_dependency_parity.rb
ruby scripts/check_dogfood_corpus.rb
ruby scripts/test_observed_query_export.rb
xcrun swift-format lint --strict -r Package.swift Sources Tests
swift test
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug build
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Release build
git diff --check
```

Use proportional extra validation for changed risk: Thread Sanitizer for
concurrency and native callback work; `xcodebuild analyze` for native boundary
changes; strict signature, entitlement, architecture, install, and duplicate-
launch checks for release or lifecycle changes. Microphone, permission,
shortcut, other-app, sleep/wake, and real-device behavior requires a separate
manual acceptance note.

## Documentation and definition of done

- Update `README.md` when current user-visible behavior or limitations change.
- Update `docs/implementation-plan.md` for roadmap status and `docs/risks.md`
  when a trust boundary or failure mode changes.
- Add or supersede an ADR for consequential decisions; do not silently rewrite
  an accepted decision to make history look consistent.
- Add a new dated evidence record for a new checkpoint. Do not rewrite an older
  evidence file to claim tests it never recorded.
- A change is done only when behavior is tested proportionally, safety and
  failure paths are considered, relevant docs agree, the full diff is reviewed,
  and unverified interactive behavior is named explicitly.
- Never commit build products, local speech assets, recordings, crash reports,
  diagnostic exports, Xcode user state, signing material, or secrets.

## Review priorities

Prioritize unauthorized or duplicate effects, privacy leaks, permission creep,
prompt-injection paths, unsafe target validation, stale context, actor/callback
isolation, cancellation and timeout races, signing/entitlement drift, and claims
that exceed the evidence. Treat cosmetic cleanup and speculative abstraction as
lower priority unless the task specifically asks for them.
