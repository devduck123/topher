# Topher

Topher is a local-first macOS assistant. This repository currently contains a
small but end-to-end voice-command path: a native menu-bar UI, configurable
global push-to-talk, on-device English transcription, deterministic typed
command resolution, policy validation, native application launching, and
allowlisted Google/YouTube navigation. It also contains a first structured
Chrome context slice for active-tab identification, bounded tab listing, and
exact-title tab activation through a narrow MV3/native-messaging bridge. The
capture and command-processing boundaries are now independent so later
dictation and context-aware requests can reuse capture without inheriting
command authority.

Topher is open source under the [MIT License](LICENSE). It is an early personal
project, not a notarized application release for general installation.

Status: the 0.4.0 build 9 development tree defines 210 Swift tests. The latest
complete normal and Thread Sanitizer runs passed all 210 tests. Xcode Debug,
universal Release, and static-analysis builds pass; the signed Release embeds
the universal native host at `Contents/Helpers`, and deep strict signature
validation passes. Direct Apple
`SpeechAnalyzer`/`SpeechTranscriber` is integrated as the provisional engine for
local dogfooding. Installation in `/Applications`, launch, and process liveness
were verified for the earlier 0.3.0 dogfood bundle; build 9 was deliberately not
installed or launched. A live Core Audio
callback-isolation failure was captured, fixed, and covered by an off-main
regression test. Accuracy, latency, permission-recovery, sleep/wake, and
repeated-session acceptance remain explicit post-merge dogfood gates; this
source merge is not evidence that those paths passed.
Live Chrome extension/native-host acceptance is also unverified. The
comparative speech benchmark is still open.

## Implemented in this slice

- A SwiftUI `MenuBarExtra` with visible ready, listening, transcribing,
  executing, success, and failure states.
- A user-recorded global shortcut. Key down starts microphone capture after
  permission and local assets are ready; key up stops capture and explicitly
  finalizes the transcript.
- Live partial text in Topher and a transient, non-activating cross-app voice
  HUD for preparation, listening, finalization, execution, and outcomes.
- A 30-second listening watchdog, an 8-second finalization watchdog, immediate
  stream-error recovery, and generation guards against late results.
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
- Typed, allowlisted navigation to Crunchyroll, Gmail, GitHub, Google, YouTube,
  Amazon, Ballislife, Hulu, Netflix, and the browser-owned Chrome Extensions
  route. Internal Chrome routes are
  delivered as URLs to Chrome even when it is already running.
- Entity-aware web phrasing: bare “Search/Open Crunchyroll” navigates to its
  known site, provider searches retain their provider, and unknown bare
  searches use Google in the default browser (Chrome in dogfood use).
- Explicit app/site precedence: “Open Netflix” prefers the known website,
  “Open Netflix app” requires an installed app, and “Open Netflix website”
  requires web navigation. An unfamiliar “Open X” opens an installed exact
  app match or visibly falls back to a Google search; Topher does not guess
  `x.com`.
- Exact known targets can be terse commands such as “Notes,” “VS Code,” and
  “YouTube.” Target-first query phrasing such as “YouTube for dining with
  Derek” is supported, and likely sentence-ending punctuation is removed only
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
- A bundled native-messaging relay with a 64-KiB application protocol limit,
  launch-scoped same-user socket handshake, exact extension-origin registration,
  checked absolute helper path, typed cancellation, timeouts, concurrency limits,
  duplicate-response handling, version mismatch recovery, demand-driven app-side
  startup, and explicit unknown outcomes when a dispatched activation disconnects.
- A separate policy decision before execution.
- Safe rejection of malformed address-like input, ambiguous installed-app
  names, and explicitly requested applications that are not installed.
- A bounded developer trace for recent final command
  transcripts and typed outcomes. Local dogfood builds start with it on; an
  explicit off switch and **Clear Now** remain available at any time. Each
  retained request can be rated independently for transcript accuracy and
  action correctness.
- XCTest coverage for parsing, policy, native capabilities, audio conversion,
  permission/assets, transcription, cancellation, and push-to-talk races.
- Dependency-free Node extension tests and Ruby native-host registration tests.

## Current interaction boundary

Topher's global shortcut already works while another application is focused;
the menu does not need to be open. The current hold is a **push-to-talk assistant
command**: release sends the finalized transcript through Topher's typed command
resolver and policy.

It is not yet general-purpose text dictation into the focused field. Always-on
wake listening, remote chat requests, conversational follow-ups, browser-page/DOM
reading, Accessibility context, and visual screen understanding are also not
implemented. They are separate modes and trust boundaries rather than flags on
the current command path.

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
   narrow Chrome adapter now supports tab identity/listing plus exact-title tab
   activation without an LLM. Page/DOM questions such as “What’s on my feed?”
   remain unimplemented.

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

Chrome context requires a separate unpacked extension and per-user native-host
registration. Build the app first, then follow the checked setup and uninstall
steps in [the Chrome extension guide](ChromeExtension/README.md). The repository
contains no fixed unpacked extension ID and setup does not need to replace the
user's `/Applications` build.

For an interactive smoke test:

1. Click Topher's sparkles icon in the menu bar.
2. Record a normal modified shortcut.
3. Hold it once. Grant microphone access if macOS asks, then let Topher prepare
   the local English speech asset. Release and hold again after Topher says it
   is ready.
4. Say “Open Safari,” release, and confirm the HUD changes from listening to
   finalizing before Safari opens exactly once.
5. Try “Notion,” “Open Figma” (or another installed app), “Open Netflix,”
   “Open Netflix app,” “What app am I using?”, “Open Chrome extensions,”
   “What is this Chrome tab?”, “What tabs do I have open?”, “Switch to the
   Chrome tab titled Example Domain,” “YouTube for dining with Derek,” “Go to
   tnc.com,” and “Search Crunchyroll.” Chrome context commands require the
   separate setup above and an exact current tab title.
6. Say “Open Acme Streaming” and confirm Topher visibly reports its Google
   fallback. Say a malformed address or an explicitly missing app and confirm
   it fails closed.
7. Use the manual transcript field and **Run** as a development fallback.

No default shortcut is claimed. This avoids silently overriding an existing
system or application shortcut.

## Voice privacy and permissions

Topher asks for microphone access only from an explicit voice action. Its app
bundle contains `NSMicrophoneUsageDescription`; the Release signature contains
only the `com.apple.security.device.audio-input` entitlement needed for capture.
The direct `SpeechAnalyzer` path does not request legacy `SFSpeechRecognizer`
authorization, Accessibility, Automation/Apple Events, or Screen Recording
access.

Audio buffers are streamed from `AVAudioEngine` to the local analyzer and are
not written to disk. Partial transcripts exist transiently in process memory
and UI so the requested command can run. Ordinary logging never includes
transcript text. During local dogfooding, **Record final command transcripts**
defaults on and retains the bounded final voice or manual text described below;
it can be turned off or cleared at any time. Audio and partial transcripts are
still never retained. Denied
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
extension requests exactly `tabs` and `nativeMessaging`, excludes incognito,
and returns only bounded regular-tab titles/URLs on demand. It has no host
permissions, content scripts, scripting, DOM/page-body extraction, screenshots,
cookies, history, form data, file-URL access, or browser snapshot persistence.
The bundled host relays bounded JSON only; it cannot execute commands. Topher
still has no Accessibility provider or screen-capture implementation. The
browser performs the external request and maintains its normal history when the
user explicitly runs a search or navigation command.

Before Topher adds direct networking, browser-content adapters, broader local
data access, or distribution to other Macs, revisit the App Sandbox decision,
capability-specific entitlements, stable Developer ID signing, notarization,
and the corresponding permission and denial-recovery tests.

## Logs and diagnostics

Topher writes metadata-only events to macOS Unified Logging under subsystem
`dev.topher.app` and categories `control-path`, `voice-capture`,
`developer-diagnostics`, and `chrome-context`. It also emits payload-free
signpost intervals for voice preparation, capture, and finalization. Unified
Logging never receives the manual transcript, search query, browser-returned
tab title/URL, raw audio, application name, or detailed error text.

For local dogfooding, the menu's **Developer diagnostics** section can retain a
separate command trace. Recording starts on for the current local-development
phase, preserves an explicit opt-out, and adds an orange dot to the menu-bar
icon while enabled. Re-enabling after an opt-out requires confirmation. Each
record contains the exact finalized voice or manual command, the interpreted
command and correction reason when Topher safely selected a different reading,
an available confidence summary, its source, an ephemeral launch-session ID, a
fixed typed outcome, fixed command/capability metadata, a typed unsupported
reason, optional local transcript/action ratings, capture-stage and processing
durations, and app version/build. It never contains raw audio, partials, or
content Topher separately captures from a browser, page, screen, message, or
document. Topher does not append constructed destination URLs, Keychain/config
values, or detailed framework errors. The user-authored command itself can
contain a query, URL, pasted content, or secret.

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
- [Latest developer transcript diagnostics verification](docs/evidence/2026-07-15-developer-transcript-diagnostics.md)
- [Installed-app resolution and fallback decision](docs/decisions/0012-installed-application-resolution-and-fallback.md)
- [Structured Chrome tab-context decision](docs/decisions/0013-structured-chrome-tab-context.md)
- [Chrome extension setup and manual acceptance](ChromeExtension/README.md)
- [Chrome context foundation verification](docs/evidence/2026-07-18-chrome-context-foundation.md)
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
