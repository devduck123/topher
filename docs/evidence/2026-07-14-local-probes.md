# Local probe evidence

Date: 2026-07-14, America/Los_Angeles

These probes were read-only. Framework probes were run with permission to use
the normal compiler/module caches outside Codex's restricted command sandbox.
Machine identifiers and serial numbers are intentionally omitted.

## Operating system and hardware

```sh
sw_vers
uname -m
system_profiler SPHardwareDataType SPDisplaysDataType
```

Relevant output:

```text
ProductVersion: 26.5.2
BuildVersion: 25F84
arm64
Model Name: MacBook Pro
Model Identifier: Mac16,1
Chip: Apple M4
Total Number of Cores: 10 (4 Performance and 6 Efficiency)
Memory: 24 GB
GPU Total Number of Cores: 10
```

## Developer tools

```sh
xcode-select -p
xcodebuild -version
swift --version
xcrun --sdk macosx --show-sdk-version
find /Applications "$HOME/Applications" -maxdepth 2 -name 'Xcode*.app' -print
```

Relevant output:

```text
/Library/Developer/CommandLineTools
xcode-select: error: tool 'xcodebuild' requires Xcode
Apple Swift version 6.2.3 (swiftlang-6.2.3.3.21 clang-1700.6.3.2)
Target: arm64-apple-macosx26.0
SDK: 26.2
No Xcode application found
```

## Foundation Models availability

```sh
swift -e 'import FoundationModels; print(SystemLanguageModel.default.availability)'
```

```text
unavailable(FoundationModels.SystemLanguageModel.Availability.UnavailableReason.appleIntelligenceNotEnabled)
```

## Speech availability and assets

```sh
swift -e 'import Speech; import Foundation; print("isAvailable=\(SpeechTranscriber.isAvailable)"); let supported = await SpeechTranscriber.supportedLocales; let installed = await SpeechTranscriber.installedLocales; print("current=\(Locale.current.identifier)"); print("supportedCurrent=\(supported.contains { $0.identifier == Locale.current.identifier })"); print("installedCurrent=\(installed.contains { $0.identifier == Locale.current.identifier })"); print("supportedCount=\(supported.count) installedCount=\(installed.count)")'
```

```text
isAvailable=true
current=en_US
supportedCurrent=true
installedCurrent=true
supportedCount=30 installedCount=9
```

## Host-process microphone status

```sh
swift -e 'import AVFoundation; print(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)'
```

```text
3
```

`3` is `authorized`. This grant belongs to the hosting process identity and is
not evidence that a future Topher app bundle is authorized.

## Installed MVP applications

```sh
swift -e 'import AppKit; for id in ["com.apple.Safari", "com.google.Chrome", "com.microsoft.VSCode"] { print("\(id)=\(NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? "missing")") }'
```

```text
com.apple.Safari=/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app
com.google.Chrome=/Applications/Google Chrome.app
com.microsoft.VSCode=/Applications/Visual Studio Code.app
```

## Initial CLT-only build verification

```sh
swift package dump-package
swift build --target TopherCore
swift test
swift build --product Topher
```

Results:

- Package manifest valid; macOS deployment target is 26.0.
- `TopherCore` builds successfully.
- A temporary dependency-free executable exercised recognized commands,
  embedded-command rejection, and policy allow/deny behavior successfully.
- `swift test` was blocked because this CLT installation had no XCTest or Swift
  Testing module.
- The GUI product was blocked because `KeyboardShortcuts` 3.0.1 uses SwiftUI
  macro plugins supplied by full Xcode (`SwiftUIMacros` and `PreviewsMacros`).
- App and test sources were separately type-checked against small compile-only
  stubs matching the inspected dependency/test APIs. This is not a substitute
  for an app-bundle build and runtime test.

These were the initial CLT-only results. Full Xcode later resolved both
blockers; see the
[Xcode application verification](2026-07-14-xcode-app-verification.md).
