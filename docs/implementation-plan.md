# Ordered implementation plan

Every slice ends with a runnable application. Deterministic browser navigation
may move forward when it uses fixed endpoints and native APIs. Do not start
browser page reading, Accessibility, screen capture, or wake-word work until the
speech-to-action loop survives the reliability slice.

## Prerequisite: reproducible native build — complete

1. Xcode 26.6 is installed and selected with `xcode-select`.
2. The tree defines 206 Swift tests. Build 9 passed normal and Thread Sanitizer
   suites, Xcode Debug and universal Release builds, static analysis, signature,
   entitlement, architecture, extension, and registration-helper checks.
   Installation, process, and live Chrome checks remain separate manual gates.
3. The conventional Xcode macOS application target uses fixed bundle ID
   `dev.topher.app`, `LSUIElement`, local signing, and the existing local core.
4. Debug and Release bundles build. The tightened Release bundle is installed
   in `/Applications`; strict signature validation, launch as a UI element,
   status-item creation, and process liveness were verified.

The original 0.2.0 installed bundle completed the no-permission matrix. The
microphone-specific Xcode-versus-`/Applications` matrix remains part of the
0.3.0 acceptance gate.

## Slice 1: control path without speech — complete

- Menu-bar presence and configurable global shortcut.
- Key-down/listening and key-up/transcribing lifecycle using mock text.
- Deterministic typed `openApplication` command.
- Policy validation and native `NSWorkspace` execution.
- Visible success/failure and unit tests.

Automated evidence covers parsing, policy, native capability outcomes,
Debug/Release compilation, bundle metadata, signing, installation, process
liveness, and status-item creation. The user manually confirmed that Safari,
Chrome, and Visual Studio Code execute from the panel, unknown input fails
closed, and the key-down/up lifecycle works as expected.

## Slice 2: isolated speech benchmark — pending measured corpus

- Build separate direct-Apple, AuralKit, FluidAudio, WhisperKit, and (if still
  justified) whisper.cpp adapters in the benchmark harness.
- Record the user's corpus with consent.
- Capture accuracy, latency, resources, assets, partial/final behavior, and
  recovery results in `speech-benchmark.md`.
- Select one engine. Delete temporary raw recordings.

Exit: a measured decision record names one engine and its fallback behavior;
the main app remains runnable without speech.

## Slice 3: speech-connected command loop — implemented, acceptance in progress

Topher now integrates the direct Apple candidate for dogfooding before the
comparative benchmark closes. This makes the real loop testable without
pretending the permanent engine decision has been made.

- Complete: direct `SpeechAnalyzer`/`SpeechTranscriber`, `AVAudioEngine`
  capture, explicit audio conversion, asset preparation, and a focused
  microphone permission manager.
- Complete: `NSMicrophoneUsageDescription` and only the Hardened Runtime
  `com.apple.security.device.audio-input` entitlement needed by capture.
  Hardened Runtime is enabled; App Sandbox is currently disabled and must be
  revisited before broader capabilities or distribution.
- Complete: the manager names the feature and reason, exposes authorization
  state, requests only from a user voice action, explains denied/restricted
  recovery, provides a verified route to the correct System Settings pane,
  and refreshes state when Topher becomes active.
- Complete: no speech-recognition authorization because the current direct path
  does not use `SFSpeechRecognizer`.
- Complete: hotkey down starts capture and key-up explicitly finalizes it. A
  voice-only cross-app HUD covers preparation, listening, finalization,
  execution, and transient outcomes; finalized text replaces stale partials.
- Complete: 30-second listening and 8-second finalization watchdogs, immediate
  stream failure recovery, stale-generation rejection, and regression tests for
  key-up/cancellation races.
- Complete: capture lifecycle is isolated in `PushToTalkCaptureController` and
  returns raw final text without selecting command versus dictation behavior.
- Complete: payload-free signpost intervals measure voice preparation, capture,
  and finalization without recording speech or transcript content.
- Complete: manual transcript fallback remains available.
- Complete: raw audio is never written and transcript text never enters
  Unified Logging. Final command text is persisted only in the explicitly
  enabled, bounded developer trace described in the diagnostics slice.
- Complete: install the hardened 0.3.0 Release in `/Applications`, exercise the
  live global hold, capture the initial Core Audio actor-isolation crash, fix it,
  and add an off-main callback regression test.
- Pending: complete the grant/denial/settings recovery matrix, measure the
  seven-command corpus, and exercise sleep/wake, audio-route changes, and 100
  repeated holds on the user's microphone and voice.
- Complete in the personalization slice: request Apple alternative hypotheses
  and confidence attributes, apply a bounded contextual vocabulary, and carry
  the final evidence without persisting raw audio or the full hypothesis list.

Exit: the seven-command corpus reaches the accepted local bar without a network
dependency, and installed-app denial/error recovery is verified.

## Slice 4: useful deterministic command set — in progress

- Complete in 0.2.0: allowlisted Google/YouTube home navigation plus Google,
  general web, and YouTube search through fixed HTTPS endpoints.
- Complete in this foundation slice: an allowlisted Notion target verified as
  bundle identifier `notion.id`; bounded variants including “Navigate Chrome,”
  “Switch to Chrome,” and “Pull up YouTube”; negative parsing cases remain
  fail-closed.
- Complete in this foundation slice: `CommandResolution` separates unsupported
  input from executable `TopherCommand`, and `AssistantCommandProcessor` owns
  resolution, policy, and exactly-one capability dispatch.
- Complete in the personalization slice: add GitHub and Crunchyroll web
  destinations; target-specific bare search/navigation semantics; general
  `Search <query>` fallback to Google; and observed-phrase regression tests.
- Complete in the personalization slice: add a local, bounded personal
  vocabulary and conservative transcript interpreter. A correction executes
  only when it selects one uniquely allowlisted typed command.
- Complete in the dogfood follow-up: separate canonical Apple recognition
  context from known ASR correction aliases; preserve already-resolved target
  wording; add installed ChatGPT/Codex (`com.openai.codex`) and Xcode
  (`com.apple.dt.Xcode`) targets.
- Complete in build 5: add Notes and Gmail; model Chrome Extensions as a typed
  browser-owned route; support target-specific Google/YouTube query phrasing;
  reject independently executable compound actions; and retain typed reasons
  for unsupported requests.
- Complete in build 6: deliver Chrome-owned routes through targeted URL handoff
  rather than launch-only arguments; accept exact bare known targets and
  destination-first provider searches; normalize sentence punctuation only in
  extracted command values; and add bounded explicit HTTPS domain navigation.
- Complete in build 7: add canonical Amazon, Ballislife, Hulu, and Netflix web
  destinations; bias recognition toward the observed proper nouns; safely
  narrow known `grock` and `ballaslive` recognition errors; and reject an
  unfamiliar voice domain before execution when Apple supplies conflicting
  host hypotheses. Manual exact domains retain their existing behavior.
- Complete in build 8: discover applications at launch from bounded conventional
  macOS application directories; resolve exact names to typed bundle identities;
  re-resolve the bundle identifier through `NSWorkspace` at execution; and bias
  on-device recognition toward installed display names. Speech never becomes an
  application path, process argument, or free-form bundle identifier.
- Complete in build 8: make target precedence explicit. Known websites win for
  generic phrases, `app`/`application` requires an installed app,
  `site`/`website` requires web behavior, and unfamiliar generic navigation
  transparently searches Google instead of guessing a `.com`. Malformed
  address-shaped values, ambiguous app names, and explicitly missing apps fail
  closed.
- Complete in build 8: add the read-only `frontmostApplication` capability for
  bounded variants of “What app am I using?” through `NSWorkspace`, with no
  Accessibility or Screen Recording permission.
- Complete in build 8: expand parser, policy, catalog, symlink-boundary,
  capability, exactly-once dispatch, and fallback URL tests.
- Complete in build 9: add deterministic active-Chrome-tab and bounded-tab-list
  questions plus explicit “Switch to the Chrome tab titled X” resolution. Keep
  tab activation behind policy as one separately registered low-risk mutation.
- Complete in build 9: add a minimal Manifest V3 extension with exactly `tabs`
  and `nativeMessaging`, explicit incognito exclusion, no host permissions or
  page injection, and no continuous or persistent browser snapshot.
- Complete in build 9: embed a dedicated native-messaging relay; register one
  exact extension origin to its checked absolute bundle path; use a typed
  versioned 64-KiB protocol, bounded tab/title/URL values, timeouts,
  cancellation, concurrency and duplicate handling, fresh fingerprints, and
  no activation retry after dispatch.
- Complete in build 9: cover resolver, policy, provider, protocol, registration,
  ambiguity, staleness, timeout, disconnect, version mismatch, and exactly-once
  behavior in Swift, Node, and Ruby tests. Live Chrome profile acceptance remains
  a separate named dogfood gate.

Exit: every proposed MVP command works without an LLM, Accessibility, or Screen
Recording.

## Slice 5: optional structured interpretation

- Recheck `SystemLanguageModel.default.availability` and locale support.
- Add constrained structured output only for deterministic misses.
- Evaluate against a held-out command corpus and adversarial retrieved text.
- Keep deterministic behavior identical when Apple Intelligence is disabled.

Exit: fuzzy phrasing improves without increasing unauthorized action rate; if
it does not, remove the model path.

## Slice 6: reliability and local diagnostics

- Exercise 100 repeated sessions, cancellation, timeouts, sleep/wake, and audio
  device changes.
- Complete: add a bounded local developer trace for the exact finalized
  voice/manual command plus fixed typed outcome, capability kind, timing, and
  app version. Enforce 24-hour, 200-record, 1-MiB, and 4-KiB-per-transcript
  bounds; reject unsafe storage paths; invalidate previously issued tokens and
  prevent queued late records on disable or clear; never include audio,
  partials, retrieved context, constructed URLs, or detailed errors appended by
  Topher. Treat the finalized user-authored command as sensitive because it can
  itself contain those strings.
- Complete: default that trace on during local dogfooding while preserving a
  persistent explicit opt-out, confirmation before re-enabling, and immediate
  deletion.
- Complete: when interpretation changes a command, retain the bounded raw and
  interpreted text, fixed reason, and confidence summary without retaining the
  complete alternative list.
- Complete: retain bounded monotonic hold-to-listening,
  listening-to-first-transcript, and key-up-to-final durations for evidence
  carrying voice requests. Keep these distinct from final-to-action command
  processing duration.
- Complete in build 5: let the user independently rate retained transcript
  accuracy and action correctness, and provide a metadata-only summary script.
  Do not infer speech accuracy from capability outcomes or confidence alone.
- Add richer metadata-only lifecycle events only when a measured reliability
  question requires them.
- Complete in build 7: retain an ephemeral launch-session identifier with each
  new developer record so accidental concurrent app instances are detectable
  without collecting more user content.
- Complete in build 7: acquire a per-user runtime lock before global-shortcut
  registration, reject unsafe lock paths, and provide one verified local
  install-and-launch script that asserts exactly one Topher process.
- Complete in build 8: make the metadata-only dogfood summary show the latest
  launch session separately before retained cross-build history.
- Test shortcut conflicts and launch-at-login only if daily use warrants it.

Exit: the core loop recovers without restarting Topher and meets the measured
latency/resource bar.

## Future interaction and context gates

These are documented now so their trust boundaries remain clear, but they are
not parallel implementation projects. The canonical contracts are
[Interaction modes](product/interaction-modes.md) and
[Request lifecycle and context](architecture/request-lifecycle.md).

### First context slice — native app identity complete

- Complete in build 8: add a read-only active-application provider for “What
  app am I using?”
- Complete in build 8: request no Accessibility or Screen Recording permission.
- Introduce a shared context coordinator only after a second provider creates
  real freshness, selection, or cancellation behavior to coordinate.

### Global text dictation

- Use a distinct shortcut or explicit mode, never the command shortcut.
- Benchmark punctuation, endpointing, insertion, undo, and app compatibility.
- Request Accessibility only when direct focused-field insertion is enabled.
- Never press Return, submit, or send automatically.

### Structured browser context

- Complete for build 9: add a narrow Chrome adapter that returns typed active
  and bounded regular-tab metadata and activates one revalidated exact-title
  match.
- Complete for build 9: treat extension/tab messages as untrusted; never execute
  arbitrary JavaScript from a model or page; keep incognito, file URLs, DOM/page
  bodies, and browser-history persistence out of the slice.
- Complete for build 9: prefer browser tab data before Accessibility or
  screenshots.
- Future: prove live extension/native-host recovery, then design DOM/page
  context as a separate permission and privacy decision.

### Remote chat ingress

- Normalize one read-only adapter into a source-aware request envelope.
- Store provider credentials in Keychain and authenticate/allowlist identities.
- Add expiry, replay protection, rate limiting, and source-aware policy.
- Require preview and confirmation before sending or other remote mutation.

### Local wake phrase

- Evaluate only after the core loop meets reliability and idle-resource gates.
- Continuously detect only the local wake phrase, not ambient transcription.
- Keep only the detector's bounded in-memory rolling audio, continuously discard
  it, and never persist, log, transmit, or transcribe it before a confirmed wake.
- Provide a persistent enabled indicator and kill switch.

## Product polish backlog

### Topher visual identity: the assistant that helps drive your Mac

- Design a small, friendly car combined with Topher's existing spark motif.
  The character should feel like a capable little copilot rather than a generic
  automobile or navigation app.
- Produce two related assets instead of scaling one image everywhere:
  - a simple single-color macOS template symbol that remains recognizable at
    menu-bar size and works in both light and dark appearances;
  - a full-color macOS app icon for Finder, Spotlight, permissions, About, and
    any future Dock presence, following the current macOS icon shape, safe-area,
    and resolution requirements.
- Preserve clear listening, processing, success, and failure state feedback
  without making the base logo visually noisy. Prefer small state treatments
  around the car/spark silhouette over entirely different icons.
- Verify the menu-bar symbol at native scale, standard and increased display
  scaling, light/dark mode, and with transcript diagnostics enabled. Include an
  accessible label; never communicate state through color alone.
- Decide explicitly whether Topher remains an `LSUIElement` menu-bar-only app
  or offers an intentional Dock mode. Do not add a permanent Dock presence as
  an accidental side effect of installing the new app icon.
- Keep source artwork and exported assets in the repository, document the
  export process, and check licensing/originality before shipping.

Exit: Topher has a distinctive car-plus-spark identity that is legible in the
menu bar, polished everywhere macOS displays its app icon, accessible across
states and appearances, and does not change menu-bar-only lifecycle behavior.
