# Topher

Topher is a local-first macOS assistant. This repository currently contains
end-to-end voice-command and global-dictation paths: a native menu-bar UI, two
configurable global hold shortcuts, on-device English transcription,
deterministic typed command resolution, safe focused-field insertion, policy
validation, native application launching, bounded web navigation, and a first
structured Chrome context slice for active-tab identification, bounded tab
listing, exact-title activation, and an optional YouTube Home feed vertical
slice through a narrow MV3/native-messaging bridge. Capture is shared, but
command interpretation, context acquisition, browser mutation, and dictation
insertion remain separate request kinds and authority boundaries.

Topher is open source under the [MIT License](LICENSE). It is an early personal
project, not a notarized application release for general installation.

Status: the 0.5.2 Build 22 source makes the bounded YouTube feed flow a useful,
model-free conversational slice. It recognizes common feed questions, scopes
terse ordinals and exact-title answers to one visible 90-second session, asks a
specific question for “that video,” and refuses title/ordinal collisions instead
of guessing. Protocol v3 separates a visually bounded result from proof of title
uniqueness and revalidates the selected video rather than requiring an unrelated
dynamic recommendation to remain frozen. Setup now distinguishes local host
registration, extension connection, and optional YouTube permission. The
Release bundle continues to embed
the universal native Chrome host at `Contents/Helpers`.
The exact 0.5.0 Build 20 Release artifact remains the installed dogfood bundle;
Build 22 has not been installed or end-to-end live-tested. Direct Apple
`SpeechAnalyzer`/`SpeechTranscriber` is integrated as the provisional engine for
local dogfooding. A live Core Audio
callback-isolation failure was captured, fixed, and covered by an off-main
regression test. Accuracy, latency, permission-recovery, sleep/wake, and
repeated-session acceptance remain explicit post-merge dogfood gates; this
source merge is not evidence that those paths passed.
Read-only inspection confirmed the new semantic selector against the current
YouTube Home structure without recording feed strings, but live Topher → native
host → extension → YouTube command acceptance remains unverified.
The comparative speech benchmark is still open.

## Implemented in this slice

- A compact SwiftUI `MenuBarExtra` with visible ready, listening, transcribing,
  executing, success, and failure states; quick access to both shortcuts and
  permission recovery; and a deterministic 380 × 460 point panel whose scroll
  content cannot collapse behind the footer. Its latest three local dogfood
  records expose transcript and action/insertion ratings without opening Settings.
- A separate native settings window with General, Personalization, and
  Developer sections. Manual command execution, detailed local diagnostics,
  and vocabulary editing stay out of the everyday menu-bar surface.
- A user-recorded global shortcut. Key down starts microphone capture after
  permission and local assets are ready; key up stops capture and explicitly
  finalizes the transcript.
- A distinct user-recorded global dictation shortcut that works while another
  app is focused. Dictation bypasses the command resolver, conservatively
  formats the transcript, and replaces only the selection captured at key-down.
- Default-on, persisted, local repeated-speech cleanup for clear adjacent
  restarts such as “I I think.” This bounded synchronous pass adds no network
  or model wait, preserves ambiguous and intentional repetition, and can be
  disabled with **Clean repeated speech** for presentation-only transcription.
- Transient Apple word timing can conservatively join a short-pause fragment
  such as “code out. And dictate” without retaining timing or audio. Strong
  developer-token phrasing such as “UI slash UX” becomes `UI/UX` in dictation
  and bounded web-search payloads; broader punctuation and grammar rewriting
  remain out of scope. The original transcript remains unchanged in diagnostics.
- Dictation may use one Apple alternative to correct one or more known built-in
  or personal-vocabulary terms only when every changed lexical span is uniquely
  corroborated, such as `gidhub` versus `GitHub`, `Kodex` versus `Codex`, or
  `impending` versus `prepending`. Risky developer spoken forms used for
  dictation do not expand command vocabulary. Topher does not generally rerank
  or rewrite prose.
- An explicit Accessibility permission boundary for dictation. Topher rejects
  secure/protected fields before capture, revalidates focus, selection, nearby
  text, and secure state before insertion, never presses Return, and never
  submits or sends.
- Verified cross-app insertion: Topher treats an Accessibility setter as an
  attempt, not proof, and reports success only after bounded text readback. It
  uses the standard value attribute only for a small plain text field, an empty
  text area, or full-value text-area replacement; rich and ambiguous surfaces
  fall back without a second mutation attempt.
- A bounded web-composer adapter covers object-free plain text areas inside a
  web Accessibility tree. For nonempty web values it generally permits only a
  verified caret-at-end append; a Notion-only exception permits an unchanged
  start/middle caret in a short, single-line, uniformly presented value. It
  rejects placeholder-backed and other ambiguous selections and admits multiple
  attributed runs only when they differ by spellcheck metadata while their
  presentation remains uniform. Exposed links, mentions, attachments, list
  markers, styled/mixed/unknown attributes, native nonempty, and oversized
  surfaces still fail closed.
- Context-aware word and sentence-punctuation spacing at the insertion boundary,
  one guarded undo for the latest insertion, and a local review/copy fallback
  for editors Topher cannot safely mutate. After a verified whole-value web
  mutation, Topher may retry only caret placement and requires stable readback;
  it never repeats the text write. Clipboard writes happen only after pressing
  **Copy**.
- Live partial text in Topher and a transient, non-activating cross-app voice
  HUD for preparation, listening, finalization, execution, and outcomes.
- Mode-aware maximum holds: 30 seconds for assistant commands and 120 seconds
  for dictation. Reaching the limit finalizes the best transcript instead of
  discarding it; the 8-second finalization watchdog and physical-key release
  gate still prevent wedged or duplicate requests.
- Recoverable partial assistant speech returns to the manual command field
  without executing. Recoverable partial dictation stays in the local review
  preview without insertion; secure targets still discard it.
- Direct Apple on-device transcription for fixed `en_US`, with on-demand asset
  preparation, alternative hypotheses, confidence evidence, contextual
  vocabulary, and no raw-audio file writes.
- Manual execution for development without speech.
- A dedicated capture controller that owns permission, assets, microphone
  lifetime, finalization, timeouts, and cancellation while returning raw text
  without deciding what it means.
- A dedicated assistant-command processor that resolves, checks policy, and
  awaits exactly one registered capability.
- Typed, allowlisted commands for ChatGPT/Codex, Chrome, Notes, Notion, Safari,
  Visual Studio Code, and Xcode, including bounded phrasing such as “Navigate
  Chrome,” “Switch to Chrome,” and “Open Codex.”
- Launch-time discovery of apps in conventional macOS Applications directories.
  Discovered names resolve to typed bundle identities; execution asks macOS to
  resolve the bundle identifier again and never turns speech into a path,
  process argument, or arbitrary identifier.
- Typed, allowlisted navigation to Crunchyroll, eBay, Gmail, GitHub, Google,
  YouTube, Amazon, Ballislife, Hulu, Netflix, and the browser-owned Chrome Extensions
  route. Internal Chrome routes are
  delivered as URLs to Chrome even when it is already running.
- Entity-aware web phrasing: bare “Search/Open Crunchyroll” navigates to its
  known site, provider searches retain their provider, and unknown bare
  searches use Google in the default browser (Chrome in dogfood use).
- Browser-qualified Google phrasing such as “Search Chrome for Ball is Life”
  removes the browser words and searches only for the requested query.
- Explicit app/site precedence: “Open Netflix” prefers the known website,
  “Open Netflix app” requires an installed app, and “Open Netflix website”
  requires web navigation. An unfamiliar “Open X” opens an installed exact
  app match or visibly falls back to a Google search; Topher does not guess
  `x.com`.
- Exact known targets can be terse commands such as “Notes,” “VS Code,” and
  “YouTube.” Target-first query phrasing such as “YouTube dining with Derek”
  and “Go to YouTube, look for dining with Derek” is supported, and likely
  sentence-ending punctuation is removed only
  from the extracted command value while the raw transcript remains intact.
- Explicit navigation to validated public domains such as “Go to tnc.com” uses
  HTTPS only. Paths, credentials, ports, IP addresses, custom schemes, and
  local/reserved names fail closed.
- Voice requests with recognition hypotheses that disagree on an unfamiliar
  domain fail before browser handoff. Known recognition errors may narrow to a
  fixed canonical destination; exact manual domains keep their direct path.
- A per-user runtime lock ensures only the primary Topher process can construct
  runtime-owned services such as the global shortcut and Chrome relay,
  including when a second bundle process is forced manually.
- Fail-closed rejection of multiple executable actions in one request.
- A bounded local personal-vocabulary editor for developer and product terms.
  Canonical terms may bias on-device recognition; known mis-transcriptions stay
  in Topher's deterministic correction layer, which can only select an already
  allowlisted typed command.
- Native launch through `NSWorkspace`.
- Read-only “What app am I using?” support through
  `NSWorkspace.frontmostApplication`, without Accessibility or Screen
  Recording permission.
- On-demand “What is this Chrome tab?” and “What tabs do I have open?” support
  through typed, bounded regular-tab metadata from a minimal Chrome Manifest V3
  extension.
- “Switch to the Chrome tab titled X” using exact deterministic title matching,
  ambiguity and incomplete-observation refusal, a five-second fingerprinted
  snapshot, extension-side revalidation immediately before mutation, and one
  non-retried activation attempt.
- “What’s on my YouTube feed?”, “What’s YouTube recommending?”, and other
  reviewed feed/homepage/list variants using the active regular Chrome tab only.
  After explicit optional YouTube permission, a packaged isolated-world extractor
  returns at most 20 visible or nearby Home recommendations as strict video ID,
  bounded title, and bounded channel records. Topher shows a numbered,
  accessible, short-lived list in its menu while keeping the HUD concise.
- “Open the third one,” “Open video three,” “number three,” “the last one,”
  “Open the video called X,” and one bare exact listed title resolve only against
  the latest visible 90-second in-memory feed. Bare answers never become global
  conversational memory. Title matching is normalized exact and proceeds only
  when the extension's bounded candidate scan proves uniqueness, even if a
  missing channel or the 20-row presentation cap made the visible list bounded.
  Bounded on-device speech alternatives can recover a title only when they
  converge on one exact listed video; conflicting alternatives refuse.
  Before one non-retried tab navigation, the extension rechecks permission,
  active source tab/Home route, stable source identity, expiry, selected-item
  identity, and fresh title uniqueness when required. It constructs the watch
  URL from the validated video ID rather than trusting a page-provided URL.
- Each displayed recommendation is also an accessible button that sends only
  its observed ordinal through the same policy, revalidation, and exactly-once
  capability path. “Open that YouTube video,” “Open that video,” and “Open it”
  ask for a listed number or exact title when a feed session exists; without a
  session they ask the user to read the feed first and never fall through to web
  search. If the feed contains exactly one item, the pronoun is unambiguous and
  opens that item. Otherwise a clarification can be answered with a bare
  number/ordinal or one exact title. Topher does not ask a model to guess.
- A layered Chrome-and-YouTube readiness surface can explicitly register or safely
  repair the per-user native-host manifest for the current app bundle, open
  Chrome Extensions, reveal Topher's bundled stable-ID extension folder, report
  whether that extension is connected, and report the optional YouTube access
  bit without reading a tab or page.
  Setup never loads the extension or grants page access silently; the optional
  YouTube permission remains a separate grant/removal in Chrome's popup.
- A bundled native-messaging relay with a 64-KiB application protocol limit,
  launch-scoped same-user socket handshake, exact extension-origin registration,
  checked absolute helper path, typed cancellation, timeouts, concurrency limits,
  duplicate-response handling, version mismatch recovery, eager primary-process
  socket readiness with demand-driven page acquisition, and explicit unknown
  outcomes when a dispatched activation disconnects.
- A separate policy decision before execution.
- Safe rejection of malformed address-like input, ambiguous installed-app
  names, and explicitly requested applications that are not installed.
- A bounded developer trace for recent final command and non-secure dictation
  transcripts and typed outcomes. Local dogfood builds start with it on; an
  explicit off switch and **Clear Now** remain available at any time. Each
  retained request can be rated independently for transcript accuracy and
  action correctness. Failed action ratings can also carry a fixed issue tag,
  and insertion/capture failures carry typed reasons without framework errors.
- A checked-in sanitized manual dogfood corpus plus an explicit private export
  for recent observed commands. The private dataset is gitignored, bounded,
  owner-readable, excludes dictation by default, and is never written by the
  app automatically.
- XCTest coverage for parsing, policy, native capabilities, audio conversion,
  permission/assets, transcription, cancellation, and push-to-talk races.
- Dependency-free Node extension tests and Ruby native-host registration tests.

## Current interaction boundary

Topher's two global shortcuts work while another application is focused; the
menu does not need to be open. The **assistant command** hold sends finalized
speech through the typed resolver and policy. The **dictation** hold sends it
through conservative formatting and a narrow Accessibility capability that
replaces the captured selection without submitting. A setter result alone is
never reported as success; Topher verifies the resulting text and exposes an
explicit pending review when the host app cannot be observed reliably.

This is a safer cross-app dictation foundation, not yet a claim of broad
Wispr-style editor compatibility or benchmarked transcription quality. Live
Build 19 acceptance in ChatGPT/Codex, Notion, Chrome, and rich editors remains
pending. Build 19 keeps frontmost-application focus recovery strictly process-bound and
adds two bounded compatibility adapters. A Codex/ChatGPT caret-at-start value
may replace the exact observed app suggestion, or a value whose independent
text-marker or suggestion metadata proves logical emptiness; every fixed signal
is revalidated before one whole-value write. A short, single-line, uniformly
formatted Notion value may use verified whole-value insertion at its start or
middle caret as well as its end. Authored Codex text and multiline, styled,
linked, listed, mentioned, or object-bearing Notion content still fail closed.
After exact content readback, a bounded whole-value path reasserts only the
captured caret and confirms it remains stable before reporting caret verification.
Search-command payloads use the same narrow strong-token slash normalization as
dictation, without rewriting the retained raw transcript. Terminal remains a
review/copy fallback rather than a keystroke or paste target.
Live cross-app acceptance is still required.
Filler removal, grammar/tone rewriting, general context-aware punctuation,
general spoken-punctuation commands, multi-paragraph editing,
always-on wake listening, remote chat, general conversational follow-ups,
general browser-page reading, broader Accessibility context, and visual screen
understanding remain separate future work. The only implemented DOM-derived
context is the reviewed YouTube Home recommendation schema; there is no general
page-body, screenshot, OCR, comment, description, account, or browser-agent
capability. These remain separate modes and trust boundaries, not flags on the
command or dictation paths.

See [Interaction modes](docs/product/interaction-modes.md) and
[Request lifecycle and context](docs/architecture/request-lifecycle.md) for the
canonical product and architecture contracts.

## Where the AI is (and is not)

Speech recognition is now the first ML component in the live path, but there is
still no LLM deciding what Topher may do. The current grammar turns a transcript
into a typed command, passes an independent policy check, and reaches one narrow
native capability without giving a model arbitrary control of the Mac.

The intended layers are:

1. Deterministic commands for exact requests such as “Open Safari,” “Go to
   YouTube,” and “Search YouTube for local AI.” These do not need AI.
2. A future optional local model that interprets fuzzier phrasing into the same
   typed commands. It proposes; the policy layer still decides what can execute.
3. Read-only native application context supports “What app am I using?” and a
   narrow Chrome adapter supports tab identity/listing, exact-title tab
   activation, and the explicit typed YouTube Home feed slice without an LLM.
   Other page/DOM questions remain unimplemented.

## Build and run

Use full Xcode with the macOS 26 SDK selected:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcodebuild -version
swift test
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug build
```

Tests remain SwiftPM-owned in this slice. The `TopherApp` scheme has no Xcode
test target, so use `swift test` as the authoritative test command rather than
Cmd-U.

After producing a signed Release bundle, install it through the checked helper:

```sh
scripts/install_local_build.sh /path/to/Build/Products/Release/Topher.app
```

Ad-hoc local rebuilds receive a new code requirement. If Accessibility appears
enabled but Topher still reports it unavailable, explicitly reset only Topher's
stale grant while installing the new build:

```sh
scripts/install_local_build.sh --reset-accessibility \
  /path/to/Build/Products/Release/Topher.app
```

This removes only Topher's Accessibility decision; macOS must ask for explicit
approval again. The helper never resets it without the flag. A stable Apple
Development signature is the durable development fix.

The helper verifies the source and installed signatures, stops the previous
local build, launches once, and fails unless exactly one Topher process remains.

For normal app development, open `Topher.xcodeproj`, select the `TopherApp`
scheme, and Run. The separate SwiftPM `Topher` scheme builds a bare executable;
it is useful for compiler checks but is not the deployable app bundle.

On macOS 26, third-party status items are also controlled by **System Settings
→ Menu Bar → Allow in the Menu Bar**. If Topher is allowed and running but its
icon is absent, reveal the menu bar outside full screen and make room by hiding
or rearranging unused status items; a crowded MacBook menu bar can clip app
items behind the notch. Launch the app bundle through Xcode, Finder, or `open`
rather than invoking `Contents/MacOS/Topher` directly.

Chrome context requires Chrome to load Topher's unpacked extension and a
per-user native-host registration. Build and launch the app, open **Settings →
General → Chrome and YouTube**, press **Set Up**, then use **Open Chrome
Extensions** and **Show Extension Folder** for the guided Chrome steps. The
repository-owned public manifest key gives development builds one stable
extension ID; no copied ID or Terminal command is required. Setup does not
replace the user's `/Applications` build or grant YouTube page access. The
checked CLI install/uninstall path remains documented in
[the Chrome extension guide](ChromeExtension/README.md).

For an interactive smoke test:

1. Click Topher's sparkles icon in the menu bar. Confirm the compact panel shows
   both interaction modes, readiness, the diagnostics indicator, and up to three
   recent requests with transcript and action/insertion ratings.
2. Open **Settings** and verify the General, Personalization, and Developer
   sections. Record a normal modified assistant shortcut under General.
3. Hold it once. Grant microphone access if macOS asks, then let Topher prepare
   the local English speech asset. Release and hold again after Topher says it
   is ready.
4. Say “Open Safari,” release, and confirm the HUD changes from listening to
   finalizing before Safari opens exactly once.
5. Try “Notion,” “Open Figma” (or another installed app), “Open Netflix,”
   “Open Netflix app,” “What app am I using?”, “Open Chrome extensions,”
   “YouTube dining with Derek,” “Go to YouTube, look for dining with Derek,”
   “Go to eBay,” “eBay.com,” “Go to tnc.com,” “Search Crunchyroll,”
   “What is this Chrome tab?”, “What tabs do I have open?”, “Switch to the
   Chrome tab titled Example Domain,” and “YouTube for dining with Derek.”
   Chrome context commands require the separate setup above and an exact
   current tab title.
6. Under **Settings → General → Chrome and YouTube**, confirm Topher identifies
   an absent, current, moved, or conflicting native-host registration correctly.
   Press **Set Up** or **Repair** only when expected, load/reload the revealed
   unpacked extension in Chrome, then use its popup for page access.
7. In the extension popup, remove YouTube access and ask “What’s on my YouTube
   feed?” Confirm Topher gives grant instructions without inspecting the page.
   Grant access, make YouTube Home active, and ask again. Confirm Settings first
   reports the extension connection and permission separately, then a numbered
   list of at most 20 titles/channels appears in Topher. Click one row or say “Open
   the third one” and confirm one revalidated navigation. Repeat by an exact
   unique title. Ask “What’s YouTube recommending?”, then try “Open that video”
   followed by “number three.” Ask again and use one bare exact listed title.
   Also try “the last one.” Confirm a one-item feed accepts “open that video,”
   while a multi-item feed requests clarification without navigating. Duplicate,
   title/ordinal collision, stale target, expired, revoked, and non-Home states
   must refuse with actionable recovery. Confirm unrelated recommendation churn
   or a tab reorder does not invalidate an otherwise unchanged selected video.
8. Say “Open Acme Streaming” and confirm Topher visibly reports its Google
   fallback. Say a malformed address or an explicitly missing app and confirm
   it fails closed.
9. Open **Settings → Developer**, enter a manual command, and use **Run
   Command** as a development fallback. Confirm blank input cannot run.
10. Record a different hold-to-dictate shortcut, explicitly allow Topher under
   **Privacy & Security → Accessibility**, focus a normal editable field in
   another app, hold the dictation shortcut, say a sentence, and release.
   Confirm text is inserted once without Return being pressed. Repeat in an
   empty and nonempty ChatGPT/Codex composer, an existing plain single-line
   Notion block with the caret at its start, middle, and end, a Chrome search
   field, and Notes; then repeat with a
   mid-draft web caret, a visible editor suggestion/placeholder, a selection, a
   rich web draft, and a password field. Proven empty/end-append drafts should
   insert exactly once; ambiguous or rich drafts must remain unchanged and fall
   back for review. Use **Undo
   Dictation** before moving the caret only when Topher offers it. If an editor is not
   supported, review the pending text in Topher and press **Copy** explicitly.
   If Settings shows Topher enabled while the app still reports denial, quit
   Topher, select its stale row and click **−**, relaunch, and allow it again.
10. For a bounded-duration recovery check, keep holding dictation past its
   configured maximum. Confirm Topher finalizes and inserts or previews the
   best available text once, then does not start another request until the
   physical shortcut is released.

No default shortcut is claimed. This avoids silently overriding an existing
system or application shortcut.

## Voice privacy and permissions

Topher asks for microphone access only from an explicit voice action and asks
for Accessibility only from an explicit dictation action or **Enable** button.
Its app bundle contains `NSMicrophoneUsageDescription`; the Release signature
contains only the `com.apple.security.device.audio-input` entitlement needed
for capture. The direct `SpeechAnalyzer` path does not request legacy
`SFSpeechRecognizer` authorization. Topher does not request Automation/Apple
Events or Screen Recording access. Accessibility is used only for the focused
text element, selection, immediate text boundary, a bounded plain value and its
attributed representation when the safe web adapter needs structural evidence,
insertion, verification, and guarded undo. A plain value is limited to 16,384
UTF-16 units, and the web-composer path is limited to 4,096. Both exist
transiently in memory and are never separately logged or persisted.

Audio buffers are streamed from `AVAudioEngine` to the local analyzer and are
not written to disk. Partial transcripts exist transiently in process memory
and UI so the request can complete. A recoverable partial may remain in the
in-process manual field or dictation preview, but is never written to the
developer trace as transcript content. Ordinary logging never includes transcript
text. During local dogfooding, **Record final commands and dictation** defaults
on and retains the bounded final voice/manual command or non-secure dictation
described below; it can be turned off or cleared at any time. Dictation aimed
at a secure field is refused before capture, and a field that becomes secure
during a hold causes the transcript to be discarded without a preview or
developer record. Audio and partial transcripts are still never retained. Denied
microphone access links to the macOS Microphone privacy pane and is rechecked
when Topher becomes active again.

## Current macOS security posture

Hardened Runtime is enabled, while App Sandbox is currently disabled. These are
separate protections: the current local build must not be described as
sandboxed merely because Hardened Runtime is on. Debug and Release use local
ad-hoc signing; Debug also receives Xcode's development-only
`com.apple.security.get-task-allow` entitlement. There is no Developer ID
signature or notarized release.

The current web commands construct fixed allowlisted destinations, encode an
explicit fallback search, or accept an explicit public DNS host through the
bounded `HTTPSDomain` type, then hand the HTTPS URL to the user's default
browser through `NSWorkspace`. Browser-owned
internal routes are delivered only to their registered browser application.
Topher itself has no direct network client or embedded browser. Its Chrome
extension requires `tabs`, `nativeMessaging`, and `scripting`, excludes
incognito, and returns bounded regular-tab titles/URLs on demand. Its only host
permission is optional `https://www.youtube.com/*`, granted or removed through
an explicit extension-popup action. Scripting runs only the packaged YouTube
Home extractor in an isolated world. There are no content scripts, required
host permissions, screenshots, cookies, history, account data, comments,
descriptions, form data, file-URL access, arbitrary/page-authored script, or
browser snapshot persistence.
The bundled host relays bounded JSON only; it cannot execute commands. Topher's
Accessibility surface is limited to focused-field dictation; it has no general
Accessibility context provider or screen-capture implementation. The browser
performs external requests and maintains its normal history when the user
explicitly runs a search, navigation, or permitted tab-activation command.

Before Topher adds direct networking, another browser-content schema, broader
local data access, or distribution to other Macs, revisit the App Sandbox
decision, capability-specific entitlements, stable Developer ID signing,
notarization, and the corresponding permission and denial-recovery tests.

## Logs and diagnostics

Topher writes metadata-only events to macOS Unified Logging under subsystem
`dev.topher.app` and categories `control-path`, `voice-capture`,
`developer-diagnostics`, and `chrome-context`. It also emits payload-free
signpost intervals for voice preparation, capture, and finalization. Unified
Logging never receives the manual transcript, search query, browser-returned
tab title/URL, raw audio, application name, or detailed error text.

For local dogfooding, **Settings → Developer → Local diagnostics** can retain a
separate request trace, while the menu exposes the latest three records and
their ratings. Recording starts on for the current local-development phase,
preserves an explicit opt-out, and adds an orange dot to the menu-bar icon while
enabled. Re-enabling after an opt-out requires confirmation. Each
record contains the exact finalized voice/manual command or non-secure
dictation, the interpreted or inserted text when Topher used different text,
an available confidence summary, its source, an ephemeral launch-session ID, a
fixed typed outcome, fixed command/capability metadata, typed unsupported,
dictation-fallback, capture-failure, and conservative-cleanup reasons, the
fixed dictation insertion method, verification result, bounded application
family, selection/placeholder/attribute classification, content-free target
role/capability profile, and fixed whole-value eligibility or refusal reason,
plus fixed semantic suggestion-attribute, character-count, text-marker,
known-suggestion, and final-decision states when the Codex adapter is evaluated,
whether
the maximum duration auto-finalized the request, optional local
transcript/action ratings and fixed action-issue tags, capture-stage and
processing durations, and app version/build. It never contains raw audio,
partials, or content Topher separately captures from a page, screen, message,
or document. A user-authored exact-title follow-up may itself repeat a feed
title in this explicitly enabled content-bearing trace; the browser-returned
feed, channels, video IDs, source URLs, and constructed destinations are never
appended. Topher does not
append constructed destination URLs, Keychain/config values, or detailed
framework errors. Secure-field dictation is deliberately excluded, but other
user-authored text can itself contain a query, URL, pasted content, or secret.

The trace is stored at
`~/Library/Caches/dev.topher.app/TranscriptDiagnostics/transcript-diagnostics.json`.
Topher sets POSIX modes `0700` on its cache directories and `0600` on the file,
and excludes them from backup. Topher prunes records older than 24 hours, keeps
at most 200 records and 1 MiB total, and limits each transcript to 4 KiB.
Disabling invalidates previously issued trace tokens and prevents their queued
late records, but preserves recent records until expiry; **Clear Now** removes them
immediately. The cache is local plaintext, not an encrypted vault: the same
macOS account and system administrators can read it, and filesystem ACLs may
grant additional access. Do not paste it into a public issue or pull request
without reviewing and redacting it.

`scripts/summarize_dogfood_diagnostics.rb` prints metadata-only results for the
latest launch session first, then the full retained history, so an older build
does not obscure the current dogfood run.

The sanitized manual corpus lives at `dogfood/manual-corpus.json`. Validate or
list it without speaking:

```sh
ruby scripts/check_dogfood_corpus.rb
ruby scripts/check_dogfood_corpus.rb --list --mode assistant
```

To build a private local dataset from recent retained commands, run the export
explicitly:

```sh
ruby scripts/export_observed_queries.rb
```

The exporter writes `.topher-local/dogfood/observed-queries.json`, never runs
inside Topher, excludes dictation unless `--include-dictation` is supplied, and
keeps the result out of Git. The dataset is plaintext user content: review it
locally, clear it intentionally when no longer useful, and never attach it to a
public issue or pull request. See [Dogfood datasets](dogfood/README.md).

Stream new events while testing:

```sh
/usr/bin/log stream --style compact --level info \
  --predicate 'subsystem == "dev.topher.app"'
```

Inspect recently retained events:

```sh
/usr/bin/log show --last 1h --style compact --info \
  --predicate 'subsystem == "dev.topher.app"'
```

The operating system manages Unified Logging retention; Topher owns the bounded
developer-trace cleanup. See [Local diagnostics](docs/local-diagnostics.md) for
the event inventory, exact retention semantics, and the macOS-to-web-development
mental model.

## Read next

- [Documentation map](docs/README.md)
- [Product vision](docs/product/vision.md)
- [Build 8 application-awareness verification](docs/evidence/2026-07-15-build-8-application-awareness.md)
- [Build 9 global-dictation verification](docs/evidence/2026-07-15-build-9-global-dictation-foundation.md)
- [Build 10 dictation-resilience and dogfood-corpus verification](docs/evidence/2026-07-16-build-10-dictation-resilience-and-dogfood-corpus.md)
- [Build 11 fast dictation-polish verification](docs/evidence/2026-07-16-build-11-fast-dictation-polish.md)
- [Build 12 Accessibility-identity recovery verification](docs/evidence/2026-07-16-build-12-accessibility-identity-recovery.md)
- [Build 13 verified cross-app dictation verification](docs/evidence/2026-07-16-build-13-verified-cross-app-dictation.md)
- [UI/UX interaction-shell verification](docs/evidence/2026-07-16-ui-ux-interaction-shell.md)
- [Build 14 contextual dictation follow-up](docs/evidence/2026-07-16-build-14-contextual-dictation-followup.md)
- [Build 15 menu and web-composer recovery](docs/evidence/2026-07-16-build-15-menu-and-web-composer-recovery.md)
- [Latest developer transcript diagnostics verification](docs/evidence/2026-07-15-developer-transcript-diagnostics.md)
- [Installed-app resolution and fallback decision](docs/decisions/0012-installed-application-resolution-and-fallback.md)
- [Structured Chrome tab-context decision](docs/decisions/0013-structured-chrome-tab-context.md)
- [Safe focused-field dictation decision](docs/decisions/0014-safe-focused-field-dictation.md)
- [Bounded dictation recovery and dogfood-corpus decision](docs/decisions/0015-bounded-dictation-recovery-and-dogfood-corpora.md)
- [Latency-budgeted dictation-polish decision](docs/decisions/0016-layer-dictation-polish-under-a-latency-budget.md)
- [Verified Accessibility mutation decision](docs/decisions/0017-verify-accessibility-dictation-mutations.md)
- [Bounded contextual dictation follow-up decision](docs/decisions/0018-bounded-contextual-dictation-followup.md)
- [Bounded uniform web-composer insertion decision](docs/decisions/0019-bounded-uniform-web-composer-insertion.md)
- [Semantic web-append evidence decision](docs/decisions/0020-require-semantic-web-append-evidence.md)
- [Focus recovery and semantic empty-composer decision](docs/decisions/0021-recover-focus-and-require-semantic-empty-composer-proof.md)
- [Combined semantic-signal and Notion caret decision](docs/decisions/0022-combine-semantic-signals-and-bound-notion-caret-insertion.md)
- [Stable caret and shared technical-notation decision](docs/decisions/0023-stabilize-caret-and-share-technical-notation.md)
- [Bounded YouTube feed-context decision](docs/decisions/0024-bounded-youtube-feed-context.md)
- [Recoverable Chrome setup and explicit YouTube references](docs/decisions/0025-make-chrome-setup-recoverable-and-youtube-references-explicit.md)
- [Build 16 verification evidence](docs/evidence/2026-07-16-build-16-semantic-web-append-and-menu-feedback.md)
- [Build 17 verification evidence](docs/evidence/2026-07-18-build-17-focus-and-semantic-composer.md)
- [Build 18 verification evidence](docs/evidence/2026-07-18-build-18-semantic-signals-and-notion-caret.md)
- [Build 19 verification evidence](docs/evidence/2026-07-19-build-19-caret-composition-and-query-formatting.md)
- [Build 19 dictation and Chrome integration evidence](docs/evidence/2026-07-19-build-19-dictation-chrome-integration.md)
- [Chrome extension setup and manual acceptance](ChromeExtension/README.md)
- [Chrome context foundation verification](docs/evidence/2026-07-18-chrome-context-foundation.md)
- [Build 20 YouTube feed-context verification](docs/evidence/2026-07-19-build-20-youtube-feed-context.md)
- [Build 21 YouTube recovery verification](docs/evidence/2026-07-21-build-21-youtube-recovery.md)
- [Build 22 YouTube conversation verification](docs/evidence/2026-07-22-build-22-youtube-conversation.md)
- [Interaction modes](docs/product/interaction-modes.md)
- [Request lifecycle and context](docs/architecture/request-lifecycle.md)
- [Technical investigation](docs/technical-investigation.md)
- [Speech benchmark plan](docs/speech-benchmark.md)
- [Implementation plan](docs/implementation-plan.md)
- [Risk register](docs/risks.md)
- [Local diagnostics](docs/local-diagnostics.md)
- [Foundation verification](docs/evidence/2026-07-15-assistant-pipeline-foundation.md)
- [Speech pre-merge verification](docs/evidence/2026-07-15-pre-merge-hardening.md)
- [Decision records](docs/decisions/0001-native-macos-26.md)
- [Contributing and macOS development practices](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
