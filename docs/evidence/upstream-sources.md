# Upstream evidence ledger

Retrieved 2026-07-14 and refreshed for Chrome context on 2026-07-19. Prefer
these primary sources when refreshing the investigation.

## Apple

- [Xcode system requirements](https://developer.apple.com/xcode/system-requirements/)
- [Xcode 26.6 release](https://developer.apple.com/news/releases/?id=06252026a)
- [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra)
- [`SpeechAnalyzer`](https://developer.apple.com/documentation/speech/speechanalyzer)
- [`SpeechTranscriber`](https://developer.apple.com/documentation/speech/speechtranscriber)
- [Speech framework updates](https://developer.apple.com/documentation/updates/speech)
- [`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [`LanguageModel` protocol](https://developer.apple.com/documentation/foundationmodels/languagemodel)
- [`NSWorkspace`](https://developer.apple.com/documentation/appkit/nsworkspace)
- [Speech authorization guidance](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition)
- [Requesting media-capture authorization on macOS](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos)
- [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input)
- [Configuring the Hardened Runtime](https://developer.apple.com/documentation/xcode/configuring-the-hardened-runtime)

The initial Command Line Tools macOS 26.2 SDK and the current Xcode macOS 26.5
SDK interfaces were inspected locally to confirm macOS 26 availability for
`SpeechAnalyzer`, `SpeechTranscriber`, and `SystemLanguageModel`. macOS 27
additions came from Apple's current online docs, because the local stable SDK
intentionally has no 27 declarations.

## Maintained repositories

- [KeyboardShortcuts 3.0.1](https://github.com/sindresorhus/KeyboardShortcuts),
  pinned by `Package.resolved` to revision
  `49c3fc04ea827f816df67843bfcc57286b47ff06`.
- [AuralKit 2.1.0](https://github.com/rryam/AuralKit).
- [FluidAudio 0.15.5](https://github.com/FluidInference/FluidAudio).
- [Argmax OSS Swift / WhisperKit 1.0.0](https://github.com/argmaxinc/argmax-oss-swift).
- [whisper.cpp 1.9.1](https://github.com/ggml-org/whisper.cpp).

## Chrome

- [Manifest format](https://developer.chrome.com/docs/extensions/reference/manifest)
- [`chrome.tabs`](https://developer.chrome.com/docs/extensions/reference/api/tabs)
- [Incognito manifest modes](https://developer.chrome.com/docs/extensions/reference/manifest/incognito)
- [Content scripts](https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts)
- [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
- [Extension message security](https://developer.chrome.com/docs/extensions/develop/concepts/messaging#security-considerations)
- [Extension service-worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle)
- [`chrome.permissions`](https://developer.chrome.com/docs/extensions/reference/api/permissions)
- [`chrome.scripting`](https://developer.chrome.com/docs/extensions/reference/api/scripting)
- [Declare optional permissions](https://developer.chrome.com/docs/extensions/develop/concepts/declare-permissions#optional_permissions)
