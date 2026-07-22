# Ordered implementation plan

Every slice ends with a runnable application. Deterministic browser navigation
may move forward when it uses fixed endpoints and native APIs. A narrow,
independently guarded permission feature may proceed without pretending the
speech reliability gate is closed; broad browser-page reading, general
Accessibility context, screen capture, and wake-word work still wait for their
own measured safety and reliability gates.

## Prerequisite: reproducible native build — complete

1. Xcode 26.6 is installed and selected with `xcode-select`.
2. The Build 21 tree defines 341 Swift tests, 30 extension tests, 43
   registration-helper assertions, and 47 sanitized dogfood cases. Normal and
   Thread Sanitizer suites, Xcode
   Debug and universal Release builds, static analysis, signature, entitlement,
   and architecture checks are captured in its evidence record. Installation,
   process, live dictation, and live Chrome/YouTube checks remain separate
   manual gates.
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
- Complete: 30-second assistant maximum duration, 8-second finalization
  watchdog, immediate stream-failure recovery, stale-generation rejection, and
  regression tests for key-up/cancellation races. Reaching the assistant
  maximum finalizes rather than discards; a recoverable partial returns to the
  manual field without execution.
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
  cancellation, concurrency and duplicate handling, explicit completeness for
  bounded matching, fresh fingerprints, and no activation retry after dispatch.
- Complete in build 9: start the app-side relay only for a primary-process Chrome
  request; refuse activation when the bound cannot prove global uniqueness; and
  classify a disconnected dispatched mutation as an unknown outcome.
- Complete in build 9: cover resolver, policy, provider, protocol, registration,
  ambiguity, staleness, timeout, disconnect, version mismatch, and exactly-once
  behavior in Swift, Node, and Ruby tests. Live Chrome profile acceptance remains
  a separate named dogfood gate.
- Complete in build 20: bump the Chrome protocol to version 2 and add
  deterministic feed-read plus ordinal/exact-title commands; optional
  `https://www.youtube.com/*` access with popup grant/remove/state UX; a fixed
  packaged isolated-world YouTube Home extractor; at most 20 bounded typed
  items; a visible 90-second in-memory session; and one revalidated,
  application-constructed watch navigation with no post-dispatch retry.
- Complete in build 20: add sanitized DOM/protocol fixtures and Swift/Node/manual
  corpora for permission denial/revocation, unsupported routes, hostile and
  oversized data, truncation, ambiguity, expiry, DOM drift, restart/disconnect,
  cancellation/timeout, version mismatch, and exactly-once/unknown outcomes.
  Live Chrome/YouTube acceptance remains a separate named gate.
- Complete in build 21: give the unpacked development extension one packaged
  public-key identity; bundle its reviewed source with the app; add explicit
  per-user native-host Set Up/Repair readiness UX; reveal the bundle and open
  Chrome Extensions through fixed actions; and refuse unsafe or conflicting
  registrations. Setup performs no silent extension load or host grant.
- Complete in build 21: update the isolated extractor for current semantic
  `yt-content-metadata-view-model` channel attribution while keeping the legacy
  fixture seam; make listed rows accessible typed actions; and turn “Open that
  YouTube video” into a deterministic number/title clarification instead of a
  guessed effect. No LLM is required for context, selection, or execution.
- Build 21 automated gates and a content-free live selector-structure check are
  recorded separately. Installing the build, registering/loading the extension,
  granting/removing permission, and completing the real command round trip in
  the user's Chrome profile remain explicit manual acceptance.

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
  voice/manual command or non-secure dictation plus fixed typed outcome,
  capability kind, timing, and
  app version. Enforce 24-hour, 200-record, 1-MiB, and 4-KiB-per-transcript
  bounds; reject unsafe storage paths; invalidate previously issued tokens and
  prevent queued late records on disable or clear; never include audio,
  partials, retrieved context, constructed URLs, or detailed errors appended by
  Topher. Treat finalized user-authored request text as sensitive because it can
  itself contain those strings.
- Complete: default that trace on during local dogfooding while preserving a
  persistent explicit opt-out, confirmation before re-enabling, and immediate
  deletion.
- Complete: when interpretation or dictation formatting changes text, retain
  bounded raw and final text, a fixed reason when applicable, and a confidence
  summary without retaining the
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
- Complete in build 10: retain typed dictation-fallback, capture-failure, and
  user-selected action-issue reasons; identify maximum-duration automatic
  finalization; keep capture-failure records content-free even when a partial is
  available for in-process review.
- Complete in build 10: add a sanitized checked-in manual request corpus and an
  explicit private, gitignored observed-query exporter. Exclude dictation by
  default, enforce file/count/content bounds and owner-only paths, and never run
  the durable export automatically from Topher.
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

### Global text dictation — foundation complete in build 9, acceptance pending

- Complete: use a distinct shortcut and explicit request route, never the
  command resolver. Per-shortcut ownership prevents one shortcut's key-up from
  finalizing the other's capture.
- Complete: request Accessibility only from an explicit dictation hold or
  **Enable** action and refresh trust after app activation.
- Complete: refuse secure fields before capture; revalidate focus, selection,
  nearby text, and secure state before insertion; never press Return, submit,
  send, or synthesize arbitrary keyboard input.
- Complete: conservatively normalize spacing/line endings without inventing
  punctuation or semantic rewrites; add only the word-boundary spaces required
  to avoid joining adjacent words.
- Complete: add guarded one-step undo and a pending local preview for unsupported
  or changed targets. Clipboard mutation requires an explicit **Copy** click.
- Complete: record raw versus formatted/inserted dictation as a distinct bounded
  diagnostic source/outcome, but discard late-secure-field text without a
  preview or diagnostic record.
- Complete in build 10: extend dictation's maximum to 120 seconds and
  automatically finalize its best transcript rather than losing the utterance.
  Preserve physical-key ownership until release so automatic finalization and a
  late key-up cannot insert twice.
- Complete in build 10: recover a usable partial after a non-secure stream or
  finalization failure into the local preview without insertion. Discard it if
  the target became secure, and persist only a fixed content-free failure
  reason.
- Complete in build 11: remove only high-confidence adjacent spoken restarts in
  a bounded synchronous local pass. Preserve ambiguous/intentional repetition,
  keep recovered partials unpolished, retain raw versus polished diagnostics,
  and provide a persisted presentation-only switch.
- Complete in build 12: detect a changed installed code requirement, warn about
  stale Accessibility consent, provide an explicit Topher-only reset during
  checked installation, and show removal/relaunch guidance when the Settings
  row looks enabled but macOS still denies the current binary.
- Complete in build 13: stop treating an Accessibility setter result as proof
  of insertion; capture a fixed target role/capability profile, choose exactly
  one bounded insertion method, revalidate process identity, verify content and
  caret with at most 30 ms of retry, and retain typed uncertain results for
  review. Add a 16,384-UTF-16-unit whole-value adapter only for plain text
  fields, empty text areas, and full-value text-area replacement.
- Complete in build 14: parse “Search Chrome for X” as a Google search for X;
  pass Apple alternatives into a dictation-only selector that accepts only a
  unique configured-vocabulary equivalence; use transient Apple word timing
  for a fixed short-pause “. And” continuation rule; and normalize spoken
  `slash` only between strong developer tokens such as `UI` and `UX`.
- Complete in build 14: extend whole-value insertion only to an append-only
  caret at the end of a single-line, object-free, web-descendant text area of
  at most 4,096 UTF-16 units. Keep multiline/native rich surfaces fail-closed,
  choose one mutation before writing, verify exact content/caret, and extend
  ambiguous-host polling from 30 to a cumulative 150 ms without delaying an
  immediate success.
- Complete in build 15: recover the current Codex/ChatGPT plain-composer shape
  by finding a cycle-free web ancestor up to 32 parents away and admitting one
  whole-value mutation for a bounded, object-free, uniformly attributed plain
  value at any valid selection, including multiline drafts. Revalidate the
  role, value, web ancestry, and uniform attributes immediately before the
  write; keep native and rich surfaces fail-closed; expose the fixed adapter
  decision in local diagnostics; and give the menu popover a deterministic
  readable height instead of allowing its scroll content to collapse.
- Complete in build 16 source: close the live Codex suggestion-text corruption
  path by refusing placeholder-backed values and non-end selections before any
  web whole-value write. Replace font-only classification with a bounded
  attributed-run classifier that accepts uniform presentation and transient
  spellcheck differences but rejects semantic, unknown, styled, linked, listed,
  attached, or mixed content. Retain only a fixed app family plus structural
  selection/placeholder/attribute evidence, and restore the latest three
  requests with transcript/action ratings in the menu. Live Codex/ChatGPT and
  Notion acceptance remains pending.
- Complete in build 17 source: recover a focused element from the frontmost
  application only when the system-wide Accessibility lookup is unavailable,
  with process identity revalidated before every mutation and undo. Recognize
  Terminal and Visual Studio Code as fixed app families and retain content-free
  preparation source/failure evidence. For Codex/ChatGPT only, replace a
  nonempty-looking caret-at-start value with the transcript alone when the full
  value is proven suggestion-only or independent character-count and web
  text-marker evidence both prove an empty logical editor. Re-read that proof
  before exactly one whole-value write; keep authored, mixed, marked, missing,
  or inconsistent evidence fail-closed. Extend the dictation alternative
  selector to correct multiple uniquely corroborated known developer terms in
  one utterance without exposing their risky spoken forms to command routing.
  Terminal remains an explicit non-mutating review/copy fallback. Live app
  acceptance remains pending.
- Complete in build 18 source: evaluate Codex/ChatGPT suggestion attributes,
  character count, full web text-marker state, and the exact observed
  app-owned suggestion as separate content-free signals instead of treating a
  positive character count as an early authored-content verdict. Revalidate
  the identical signal bundle before replacing the suggestion and require
  authored-content evidence after the write. Extend the Notion adapter only to
  unchanged start/middle carets in bounded, single-line, object-free, uniformly
  presented text; multiline and rich blocks remain fail-closed. Allow `get` to
  become `git` only from one exact Apple alternative, and retain the new fixed
  semantic states in local diagnostics. Live app acceptance remains pending.
- Complete in build 19 source: address Build 18 dogfood findings by adding
  punctuation-aware insertion-boundary spacing; after exact whole-value content
  readback, retry only caret placement and confirm it after a bounded delay;
  share the existing strong-token spoken-slash formatter with web-search query
  payloads while retaining the raw transcript; and admit `Kodex` → `Codex` and
  `impending` → `prepending` only when one Apple alternative corroborates the
  entire lexical change. Keep authored Codex start/middle content unchanged and
  explain its review/copy fallback instead of widening whole-value mutation to
  ambiguous or rich content. Live Build 19 acceptance remains pending.
- Pending: benchmark a separately optional smart-formatting tier using the full
  finalized utterance and typed destination-app identity. Precommit a deadline,
  fall back to the fast tier on timeout or uncertainty, retain raw text and
  typed changes, and do not acquire screen content solely for prose formatting.
- Pending live gate: run the app compatibility matrix across native AppKit
  fields, Chrome form controls/contenteditable, ChatGPT/Codex, Notion, editors,
  multiline fields, selected replacement, and unsupported/secure surfaces.
  Check fixed method/verification/role diagnostics whenever visible insertion
  differs from Topher's outcome.
- Pending: benchmark punctuation, endpointing, proper nouns, developer terms,
  insertion latency, undo, and repeated sessions using the speech corpus.

### Structured browser context

- Complete for build 9: add a narrow Chrome adapter that returns typed active
  and bounded regular-tab metadata and activates one revalidated exact-title
  match.
- Complete for build 9: treat extension/tab messages as untrusted; never execute
  arbitrary JavaScript from a model or page; keep incognito, file URLs, DOM/page
  bodies, and browser-history persistence out of the slice.
- Complete for build 9: prefer browser tab data before Accessibility or
  screenshots.
- Complete for build 20: add the separately approved YouTube Home schema behind
  optional exact-origin access and a fixed packaged extractor. Keep it
  demand-driven, content-bounded, in-memory, explicitly clearable, and isolated
  from general DOM automation.
- Complete for build 21 source: add explicit native-host readiness and safe
  setup/repair, bundle a stable-ID unpacked extension, and update the isolated
  selector seam for current YouTube Home channel metadata.
- Future: prove live extension/native-host/YouTube round-trip acceptance, then require
  another permission and privacy decision before any additional DOM/page
  context schema.

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

### Interaction shell and in-use feedback — in progress

- Complete in the first UI slice: keep the menu-bar control as the fast,
  glanceable surface: show the active mode, readiness, the configured shortcut,
  and the one recovery action that matters now. A separate native settings
  window now moves manual development input, vocabulary maintenance, and
  detailed diagnostics into General, Personalization, and Developer sections
  without hiding the persistent diagnostics-on state.
- Pending: add a deliberate first-launch and relaunch experience so opening
  Topher never appears to do nothing when the app has no Dock icon, the menu-bar
  item is disabled, or the menu bar is crowded. Explain where Topher lives, how
  to invoke each implemented mode, why each permission is needed, and how to
  quit.
- In progress: define one presentation model for command and dictation phases
  so the menu-bar symbol, control panel, and passive HUD use consistent names,
  symbols, colors, timing, and recovery actions without collapsing the modes
  into one authority path.
- Pending: refine the passive HUD for preparation, listening, finalization,
  execution or insertion, success, and failure. Keep it non-activating and
  privacy-safe; verify placement across display arrangements and Dock positions,
  readable result duration, long or empty text, and no focus theft.
- Complete in the first UI slice: require an explicit manual command before
  enabling **Run Command**. The manual field now starts empty, trims its input,
  and has no window-wide Return shortcut that can run while another control has
  focus.
- Complete in the first UI slice: use native macOS controls and semantic
  materials, a bounded scrolling menu, and text or shape in addition to color
  for every primary state. Isolated light/dark renders cover the compact menu
  and all settings sections at their production minimum widths, including
  keyboard focus through personalization fields. Pending installed-app
  verification covers increased contrast, reduced transparency, reduced
  motion, VoiceOver, larger text, and short displays.
- Complete in the first UI slice: add a deterministic regression test for blank
  manual input and rerun the full model suite. Pending: add render or snapshot
  coverage for high-value states and complete a manual matrix for first launch,
  menu-bar visibility, permission grant/denial/recovery, command and dictation
  holds, failures, multiple displays, Dock positions, and accessibility
  appearances.

Exit: a first-time user can find Topher, understand its current modes and
permissions, complete or recover from an interaction without opening developer
tools, and use the interface without focus theft, clipped content, accidental
execution, or color- and motion-only feedback.

### Topher visual identity and Dock presence — planned

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
- Record an explicit lifecycle decision before changing `LSUIElement`. The
  recommended default remains menu-bar-only; offer a Dock mode only if its icon
  opens a useful control or settings window, and test activation, application
  switching, relaunch, duplicate ownership, and quit behavior in both modes.
  Do not add a permanent Dock presence as an accidental side effect of
  installing the new app icon.
- Keep source artwork and exported assets in the repository, document the
  export process, and check licensing/originality before shipping.

Exit: Topher has a distinctive car-plus-spark identity that is legible in the
menu bar, polished everywhere macOS displays its app icon, accessible across
states and appearances, and preserves the documented menu-bar-only lifecycle;
any Dock mode is separately intentional and tested.
