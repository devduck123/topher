# Focused technical investigation

Status: 2026-07-15

## Recommendation

Build Topher as one native Swift application targeting stable macOS 26. Use
SwiftUI `MenuBarExtra` for the persistent control and AppKit only at native
system boundaries (`NSWorkspace` now; a focused `NSPanel` overlay later). Use
`KeyboardShortcuts` for customizable global key-down/key-up activation. Keep
intent resolution deterministic until a command falls outside its grammar, and
allow only application-owned typed commands through policy into registered
native capabilities.

Apple `SpeechTranscriber` is the leading speech candidate because it is present,
local, and has the current English asset installed on this Mac. That is a
candidate, not a selection: accuracy and latency have not been measured with the
user's voice. Benchmark direct Apple integration (using AuralKit as a wrapper
comparison), FluidAudio, WhisperKit, and whisper.cpp before connecting speech to
the control path.

Do not use macOS 27 beta APIs in the baseline. Do not add Rust, C++, Python,
JavaScript, an LLM runtime, Accessibility, Screen Recording, or a browser
extension to the current slice.

## Environment findings

| Item | Confirmed local result |
|---|---|
| Repository baseline | Directory was empty and had no Git metadata |
| macOS | 26.5.2, build 25F84 |
| Architecture | arm64 |
| Hardware | MacBook Pro Mac16,1; Apple M4; 10 CPU cores; 10 GPU cores; 24 GB memory |
| Storage | About 688 GiB available during inspection |
| Xcode | 26.6, build 17F113 |
| Active developer directory | `/Applications/Xcode.app/Contents/Developer` |
| Swift | 6.3.3 (`swiftlang-6.3.3.1.3`) |
| Installed macOS SDK | 26.5 |
| Extra project generators | No XcodeGen or Tuist |
| Installed MVP applications | Safari, Google Chrome, and Visual Studio Code bundle IDs resolve locally |

The initial Command Line Tools limitation is resolved. At the 0.2.0 baseline,
full Xcode built the SwiftPM product with all 24 tests and produced Debug and
Release application bundles. That verified Release was a universal `Topher.app`
with fixed identifier `dev.topher.app`, `LSUIElement`, a hardened runtime, no
Release entitlements, and a valid local ad-hoc signature. Installation in
`/Applications`, launch, status-item creation, and process liveness were
verified.

The current 0.4.0 development tree defines 223 tests and still adds only the
Release audio-input entitlement required for microphone capture. Build 9 also
adds an explicit Accessibility TCC boundary for narrow focused-field dictation;
Accessibility does not add a code-signing entitlement. See the latest dated
evidence for normal, sanitizer, Xcode, and bundle results rather than treating
this evolving investigation as verification.
See the dated
[speech integration evidence](evidence/2026-07-14-speech-integration.md) for the
installed bundle and live callback verification, and the
[pre-merge hardening evidence](evidence/2026-07-15-pre-merge-hardening.md) for
the lifecycle and HUD checks, and the
[developer transcript diagnostics evidence](evidence/2026-07-15-developer-transcript-diagnostics.md)
for the current validation state.

Live framework probes, run outside the restricted build sandbox, returned:

```text
SystemLanguageModel.default.availability
→ unavailable(.appleIntelligenceNotEnabled)

SpeechTranscriber.isAvailable
→ true

Locale.current
→ en_US

SpeechTranscriber current locale supported / installed
→ true / true

SpeechTranscriber supported / installed locale counts
→ 30 / 9
```

The M4 is eligible hardware, but the runtime result is authoritative: Topher
cannot use the system language model in the current system configuration.

An AVFoundation probe returned microphone authorization `authorized` for the
host process. TCC grants are identity-specific, so this says nothing conclusive
about `dev.topher.app`. The fixed app bundle now exists, but Slice 1 has no
microphone or speech permission request to compare. There are still no valid
Apple code-signing identities; the current ad-hoc signature is appropriate for
local execution but not distribution or future TCC-persistence conclusions.

Exact commands and redacted outputs are in the
[local probe record](evidence/2026-07-14-local-probes.md) and
[Xcode app verification record](evidence/2026-07-14-xcode-app-verification.md);
official docs, package tags, and pinned revisions are in the
[upstream evidence ledger](evidence/upstream-sources.md).

## Platform and API availability

| Capability | Stable baseline | macOS 27 beta addition | Decision |
|---|---:|---:|---|
| SwiftUI [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra) | 13 | — | Use now; window style is sufficient for the small control panel. |
| [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer) and [`SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber) | 26 | — | Benchmark on 26. |
| Speech input plumbing | App-owned `AsyncSequence<AnalyzerInput>` on 26 | [`CaptureInputSequenceProvider`](https://developer.apple.com/documentation/speech/captureinputsequenceprovider), `AssetInputSequenceProvider`, and `AnalyzerInputConverter` on 27 | Keep 26 implementation; adopt conveniences later behind availability checks. |
| [`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel) and `LanguageModelSession` | 26 | Broader [`LanguageModel`](https://developer.apple.com/documentation/foundationmodels/languagemodel) protocol on 27 | Use the concrete system model only as an optional future fallback. |
| Native launch | [`NSWorkspace`](https://developer.apple.com/documentation/appkit/nsworkspace) | — | Use now. |
| Foreground application | `NSWorkspace.shared.frontmostApplication` | — | Add in the useful-command slice; no Accessibility permission. |

macOS 26 is the right deployment target for this one known M4 Mac. A lower
target would force Topher to own and distribute a third-party speech model only
to support systems the product does not target. macOS 27 is beta and its new
APIs reduce plumbing but do not unlock an essential MVP behavior.

## Application foundation

Use native Swift and SwiftUI in one process. `MenuBarExtra(.window)` is the
smallest adequate menu-bar foundation and supports standard controls. The Xcode
application target generates an Info.plist with `LSUIElement = true`; the AppKit
accessory activation policy is a matching defense in depth.

Do not introduce an `NSStatusItem` implementation unless testing finds a
specific `MenuBarExtra` limitation. Add a non-activating AppKit `NSPanel` only
when a result/listening overlay must remain visible while another app has focus.
Neither need justifies a second process or runtime.

The conventional Xcode macOS target now compiles the existing app sources and
links the local `TopherCore` package product plus pinned KeyboardShortcuts. Use
the shared `TopherApp` scheme for `.app` builds. The similarly named SwiftPM
executable remains a compiler/test convenience and does not replace bundle
validation.

### Current security and distribution posture

The Xcode target explicitly enables Hardened Runtime and disables App Sandbox.
Those settings are independent: Hardened Runtime constrains the signed process,
but the current application is not sandboxed. The Release signature is local
and ad hoc, with only `com.apple.security.device.audio-input`; Debug also has
Xcode's development-only `com.apple.security.get-task-allow`. Current TCC
requests are microphone access for held speech and Accessibility for explicitly
invoked focused-field dictation. There is no Automation/Apple Events, Screen
Recording, or legacy `SFSpeechRecognizer` authorization request.

Google/YouTube navigation uses validated fixed HTTPS destinations and delegates
them to the default browser through `NSWorkspace`. Topher has no direct network
client, embedded web view, browser extension/native-messaging host, or browser
page/tab capture implementation. The destination browser—not Topher—performs
the resulting network request.

This is a local-dogfood posture, not a distribution design. Revisit App Sandbox
and capability entitlements before adding direct network or browser-content
access. Adopt a stable Developer ID identity, verify permission persistence, and
notarize before distributing Topher to other Macs.

## Speech technology comparison

No candidate has been selected because no representative user recordings were
available. Upstream WER and real-time-factor claims are screening evidence, not
Topher acceptance results.

| Candidate | Strengths for Topher | Costs / uncertainties | Current disposition |
|---|---|---|---|
| Direct Apple `SpeechAnalyzer` / `SpeechTranscriber` | Stable on macOS 26; local; streaming partial/final results; locale assets managed by the OS; current locale is installed; supports analysis context and custom language models. | Apple publishes no Topher-specific accuracy, latency, energy, or asset-size data. App must own AVAudioEngine capture, conversion, finalization, route changes, and recovery. | Leading engine; build the smallest benchmark first. |
| [AuralKit 2.1.0](https://github.com/rryam/AuralKit) | Thin Swift wrapper over the same Apple engine; handles microphone capture, conversion, assets, finalization, cancellation, VAD, and route changes; exposes contextual strings. | Uses the same recognizer, but wrapper defaults, audio conversion, and context can still change observed results. It adds a young dependency. Its documented permission setup includes speech authorization even though Apple's pure `SpeechAnalyzer` path does not use the speech server permission. | Compare integration/reliability and run the same corpus to catch pipeline differences; it is not an independent model. |
| [FluidAudio 0.15.5](https://github.com/FluidInference/FluidAudio) / Parakeet | Native Swift/Core ML, fully local, Apple Silicon optimized, active; roughly 460 MiB current multilingual model. Separate true-streaming EOU model exists. | Standard Parakeet path is sliding-window near-real-time. Custom vocabulary support is path-specific. Model licensing metadata needs resolution. A learned EOU model adds little to push-to-talk because key-up is authoritative. | Strong independent fallback benchmark. |
| [WhisperKit / Argmax OSS Swift](https://github.com/argmaxinc/argmax-oss-swift) | Native Swift/Core ML, active, local, lower integration burden than C++; compressed turbo asset is roughly 626 MB. | Streaming repeatedly processes a growing buffer; energy VAD rather than semantic EOU; first-class custom vocabulary is not in the OSS tier. | Whisper-family benchmark control. |
| [whisper.cpp 1.9.1](https://github.com/ggml-org/whisper.cpp) | Mature, MIT, highly configurable, Metal/Core ML options, model sizes from about 75 MiB to multiple GiB. | Highest Swift packaging and C bridge burden; streaming example is repeated windows; the old community SPM wrapper is headed for archival. | Retain only if quantization/control proves measurably valuable. |

The measurement protocol and empty results table are in
[`speech-benchmark.md`](speech-benchmark.md). Selection is blocked on those
measurements, not on more architecture discussion.

## Shortcut and activation

Use [KeyboardShortcuts 3.0.1](https://github.com/sindresorhus/KeyboardShortcuts).
It exposes separate key-down and key-up handlers, a SwiftUI recorder, persistent
user choice, and global Carbon hotkeys without Accessibility or Input Monitoring
permission. It deliberately does not support modifier-only keys, Caps Lock, or
media keys. That limitation aligns with the MVP security and permission goals.

The first slice leaves the shortcut unset and makes configuration visible. This
avoids claiming a global chord that already belongs to the user or system.

## Reasoning and command security

The current control path is intentionally concrete:

```text
shortcut/manual input
  → AssistantCommandProcessor
    → deterministic CommandResolver
    → CommandResolution.resolved(TopherCommand) or unsupported
    → CommandPolicy
    → exactly one registered native capability
  → typed outcome and visible state
```

`ApplicationTarget` retains application-owned identities for important fixed
targets. Build 8 adds bounded launch-time discovery as
`InstalledApplicationTarget`: exact catalog names become typed bundle
identities, never paths or launch arguments, and `NSWorkspace` re-resolves the
identifier at execution. Explicitly missing or ambiguous apps remain
unsupported. Unknown generic navigation becomes a separately typed and visibly
labeled Google fallback rather than an invented application identity or domain.

Later resolution should remain layered:

1. Exact deterministic rules.
2. Parameterized deterministic rules with validated values.
3. Optional structured `SystemLanguageModel` interpretation when available.
4. An application-owned `TopherCommand` proposal.
5. Policy validation independent of the proposal source.
6. Capability execution.

Do not add a generic model-provider protocol now. There is only one possible
model and it is currently unavailable. If a model fallback is added, it should
produce a constrained `@Generable` proposal and never source code, shell,
AppleScript, browser JavaScript, or raw input events. Retrieved screen/web text
is untrusted data and must never share the user-instruction channel.

## Permissions

The 0.3.0 direct-Apple speech integration adds
`NSMicrophoneUsageDescription` and the Hardened Runtime
[`com.apple.security.device.audio-input`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input)
entitlement. Topher asks only on an explicit voice action; the privacy string
does not replace the resource-access entitlement. A focused permission manager
reports not-determined/authorized/denied/restricted state, handles the one
request, opens the Microphone settings pane, and refreshes on app activation.

The direct `SpeechAnalyzer`/`SpeechTranscriber` pipeline stays on device and does
not require `SFSpeechRecognizer` server authorization according to Apple's
[speech permission guidance](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition).
Accordingly, the current target has no `NSSpeechRecognitionUsageDescription`.
Add it only if a future selected implementation actually invokes
`SFSpeechRecognizer`. Focused-field dictation now requests Accessibility from
an explicit action and revalidates a narrow selected-text boundary. Do not add
Screen Recording usage descriptions before a corresponding capability exists.

## Context and browser path

The canonical cross-channel product contract is now documented in
[Interaction modes](product/interaction-modes.md), and the shared source,
context, policy, capability, and result design is in
[Request lifecycle and context](architecture/request-lifecycle.md). In
particular, global assistant commands, focused-field dictation, local wake
detection, and remote chat ingress are distinct modes. A source-aware boundary
routes each request kind before typed proposals converge on shared downstream
controls.

Do not create a general `ContextBroker` yet. Build 8's first context command
queries `NSWorkspace.frontmostApplication` directly behind a small read-only provider.
Introduce a broker only when at least two independently requested providers
exist and demand-driven selection has real behavior to coordinate.

The future Chrome adapter should be a Manifest V3 extension plus a native
messaging host. Its service worker can use
[`runtime.connectNative`](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging),
while an allowlisted packaged
[content script](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)
extracts typed page data and passes it through the service worker. Chrome's own
security guidance says content-script messages must be treated as attacker
controlled; Topher must validate every field again at the native boundary.

One weak assumption in the initial sketch is that `activeTab` automatically
provides minimal permission for a voice-triggered query. Chrome grants
[`activeTab`](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab)
only after an explicit extension user gesture. By inference from Chrome's
documented gesture requirement, a native-message request alone does not grant
it. Topher will therefore need either a narrow host permission such as YouTube,
an optional host permission granted through extension UI, or an extra user
click. It should not request `<all_urls>` merely for convenience.

Chrome also launches the registered native-messaging host as a process and only
allows the extension service worker/page—not a content script—to connect to it.
The likely adapter is therefore a very small Swift relay executable or a relay
mode of the Topher binary that forwards typed messages to the running app. That
is the first plausible justification for a helper process, but it is not an MVP
dependency and needs a separate lifecycle/security spike.

The adapter should return active-tab metadata and explicitly requested DOM data;
it should never accept model-generated JavaScript. Safari can remain a future
adapter. Accessibility, ScreenCaptureKit, Vision OCR, and raw input synthesis
stay below structured app/browser interfaces in the execution hierarchy.

## What exists now versus what waits

Authored, tested, and built now:

- `TopherCommand`, fixed and launch-time discovered application targets,
  deterministic resolver, policy, and an `AssistantCommandProcessor` that owns
  exactly-one dispatch.
- Fixed `WebsiteTarget`, `SearchProvider`, and bounded `SearchQuery` values.
- Native application-open, frontmost-application read, and web-navigation
  capabilities with risk/access metadata and small injected `NSWorkspace`
  facades.
- One observable presentation/routing model, with capture and command execution
  delegated to focused lifecycle components.
- Direct `SpeechAnalyzer`/`SpeechTranscriber`, `AVAudioEngine` capture,
  `AVAudioConverter`, runtime asset preparation, and microphone permission
  boundaries.
- Real push-to-talk start/partial/finalize/cancel behavior with mode-specific
  maximum-duration finalization, a finalization watchdog, generation guards,
  and preview-only recovery of usable partials.
- Payload-free preparation, capture, and finalization signpost intervals for
  local latency investigation.
- Menu-bar UI, transient non-activating voice HUD, manual transcript fallback,
  and typed outcome.
- Parser, query validation, policy, native capability, permission, asset,
  conversion, transcription-session, capture-controller, command-processor,
  and lifecycle-race tests. Injected facades keep unit tests from launching
  applications, opening a browser, or using a real microphone.

Waits for measured need:

- Comparative speech adapters and the measured user-voice corpus, context
  broker, capability registry collection, model-provider abstraction, browser
  page or tab adapter, accessibility/screen providers, wake word, and persistent
  history.
