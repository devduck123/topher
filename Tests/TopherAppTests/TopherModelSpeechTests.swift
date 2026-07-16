import AVFoundation
import Foundation
import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class TopherModelSpeechTests: XCTestCase {
  func testFirstPushToTalkRequestsPermissionAndPreparesWithoutRecording() async {
    var requestCount = 0
    let permission = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { .notDetermined },
        requestAccess: {
          requestCount += 1
          return true
        }
      )
    )
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission,
      speechAssets: readySpeechAssets(),
      voice: voice
    )

    XCTAssertEqual(model.voiceReadiness, .needsPermission)

    model.beginPushToTalk()
    XCTAssertEqual(model.voiceFeedback, .preparing("Checking microphone access…"))

    await waitUntil {
      model.phase == .success("Voice input is ready. Hold your shortcut again to speak.")
    }
    XCTAssertEqual(model.voiceReadiness, .ready)
    XCTAssertEqual(requestCount, 1)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
    XCTAssertEqual(voice.finishCount, 0)
    XCTAssertEqual(voice.cancelCount, 0)
    XCTAssertEqual(
      model.voiceFeedback,
      .success("Voice input is ready. Hold your shortcut again to speak.")
    )
  }

  func testAuthorizedPushToTalkShowsPartialAndExecutesFinalCommandOnce() async {
    let voice = VoiceHarness()
    var applicationOpenCount = 0
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { bundleIdentifier in
            XCTAssertEqual(bundleIdentifier, ApplicationTarget.safari.bundleIdentifier)
            return URL(fileURLWithPath: "/Applications/Safari.app")
          },
          openApplication: { _ in applicationOpenCount += 1 }
        )
      )
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    XCTAssertEqual(model.voiceFeedback, .listening(""))

    voice.yield(.partial("Open Saf"))
    await waitUntil { model.phase == .listening("Open Saf") }
    XCTAssertEqual(model.voiceFeedback, .listening("Open Saf"))

    voice.yield(.final("Open Safari."))
    model.endPushToTalk()
    model.endPushToTalk()

    await waitUntil { model.phase == .success("Opened Safari.") }
    XCTAssertEqual(applicationOpenCount, 1)
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
    XCTAssertEqual(voice.finishCount, 1)
    XCTAssertEqual(voice.cancelCount, 0)
    XCTAssertEqual(model.voiceFeedback, .success("Opened Safari."))
  }

  func testGlobalDictationUsesSeparateRouteAndInsertsWithoutExecutingACommand() async {
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "hello",
      selection: FocusedTextRange(location: 5, length: 0)
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    XCTAssertEqual(model.voiceFeedback, .dictationListening(""))

    voice.yield(.final("world"))
    model.endDictation()

    await waitUntil { model.phase == .success("Inserted dictation.") }
    XCTAssertEqual(field.content, "hello world")
    XCTAssertTrue(model.canUndoDictation)
    XCTAssertNil(model.pendingDictationText)
    XCTAssertEqual(model.voiceFeedback, .success("Inserted dictation."))
  }

  func testDisabledDictationPolishPreservesRepeatedSpeech() async {
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "",
      selection: FocusedTextRange(location: 0, length: 0)
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      dictationPolishEnabled: false,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.final("I I think this should stay raw"))
    model.endDictation()

    await waitUntil { model.phase == .success("Inserted dictation.") }
    XCTAssertEqual(field.content, "I I think this should stay raw")
    XCTAssertFalse(model.isDictationPolishEnabled)
  }

  func testUnverifiedDictationMutationNeverReportsSuccessfulInsertion() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherUnverifiedMutationDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "",
      selection: FocusedTextRange(location: 0, length: 0)
    )
    field.selectedTextMutationSucceeds = false
    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL: temporaryRoot.appendingPathComponent(
          "TranscriptDiagnostics",
          isDirectory: true
        ),
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      developerDiagnostics: diagnostics,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.final("keep this pending"))
    model.endDictation()

    await waitUntil { model.pendingDictationText == "keep this pending" }
    await waitUntil { diagnostics.records.count == 1 }
    XCTAssertEqual(field.content, "")
    XCTAssertEqual(diagnostics.records[0].outcome, .dictationFallback)
    XCTAssertEqual(diagnostics.records[0].dictationFailureReason, .mutationUnverified)
    XCTAssertEqual(
      diagnostics.records[0].dictationInsertionEvidence,
      FocusedTextInsertionEvidence(
        method: .selectedText,
        verification: .unavailable,
        target: field.profile
      )
    )
  }

  func testWholeValueAdapterInsertsIntoEmptyCompatibleSurface() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherWholeValueDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "",
      selection: FocusedTextRange(location: 0, length: 0)
    )
    field.selectedTextMutationSucceeds = false
    field.exposesValue = true
    field.canSetValue = true
    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL: temporaryRoot.appendingPathComponent(
          "TranscriptDiagnostics",
          isDirectory: true
        ),
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      developerDiagnostics: diagnostics,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.final("verified value insertion"))
    model.endDictation()

    await waitUntil { model.phase == .success("Inserted dictation.") }
    await waitUntil { diagnostics.records.count == 1 }
    XCTAssertEqual(field.content, "verified value insertion")
    XCTAssertFalse(model.canUndoDictation)
    XCTAssertEqual(diagnostics.records[0].outcome, .dictationInserted)
    XCTAssertEqual(diagnostics.records[0].dictationInsertionEvidence?.method, .wholeValue)
    XCTAssertEqual(
      diagnostics.records[0].dictationInsertionEvidence?.verification,
      .contentAndCaret
    )
  }

  func testDictationPermissionPromptIsExplicitAndStopsBeforeMicrophoneCapture() async {
    var promptCount = 0
    let accessibility = AccessibilityPermissionClient(
      environment: AccessibilityPermissionEnvironment(
        isProcessTrusted: { false },
        promptForTrust: {
          promptCount += 1
          return false
        }
      )
    )
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      accessibilityPermission: accessibility
    )

    XCTAssertEqual(promptCount, 0)
    model.beginDictation()
    await Task.yield()

    XCTAssertEqual(promptCount, 1)
    XCTAssertEqual(model.accessibilityPermissionState, .notAuthorized)
    guard case .failure(let message) = model.phase else {
      return XCTFail("Expected Accessibility recovery guidance")
    }
    XCTAssertTrue(message.contains("remove the existing Topher row with the − button"))
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
  }

  func testSecureFieldRefusesDictationBeforeCaptureOrTextRead() async {
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "secret",
      selection: FocusedTextRange(location: 6, length: 0)
    )
    field.isSecure = true
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await Task.yield()

    XCTAssertEqual(model.phase, .failure("Dictation is disabled in secure text fields."))
    XCTAssertEqual(field.selectedTextReadCount, 0)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
  }

  func testUnsupportedTargetKeepsPreviewUntilExplicitCopy() async {
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "",
      selection: FocusedTextRange(location: 0, length: 0)
    )
    field.canSetSelectedText = false
    var clipboardWrites: [String] = []
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment),
      dictationClipboard: DictationClipboardCapability(
        environment: DictationClipboardEnvironment(writeString: {
          clipboardWrites.append($0)
          return true
        })
      )
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.final("GraphQL   URLSession"))
    model.endDictation()

    await waitUntil { model.pendingDictationText == "GraphQL URLSession" }
    XCTAssertTrue(clipboardWrites.isEmpty)
    XCTAssertEqual(field.content, "")

    model.copyPendingDictation()
    XCTAssertEqual(clipboardWrites, ["GraphQL URLSession"])
    XCTAssertEqual(model.phase, .success("Copied dictation. Paste it where you want it."))
  }

  func testDictationStreamFailurePreservesPartialForReviewWithoutInsertion() async throws {
    struct StreamFailure: Error {}

    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherDictationRecoveryDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL:
          temporaryRoot
          .appendingPathComponent("dev.topher.app", isDirectory: true)
          .appendingPathComponent("TranscriptDiagnostics", isDirectory: true),
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "Before",
      selection: FocusedTextRange(location: 6, length: 0)
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      developerDiagnostics: diagnostics,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.partial("I I need to recover this unfinished dictation"))
    await waitUntil {
      model.phase == .listening("I I need to recover this unfinished dictation")
    }
    voice.fail(StreamFailure())

    await waitUntil {
      model.pendingDictationText == "I I need to recover this unfinished dictation"
    }
    XCTAssertEqual(field.content, "Before")
    XCTAssertEqual(
      model.phase,
      .failure(
        "Transcription stopped before finalizing. Open Topher to review or copy the recovered text."
      )
    )
    await waitUntil { diagnostics.records.count == 1 }
    XCTAssertEqual(diagnostics.records[0].transcript, "")
    XCTAssertEqual(diagnostics.records[0].source, .dictation)
    XCTAssertEqual(diagnostics.records[0].outcome, .captureFailed)
    XCTAssertEqual(diagnostics.records[0].captureFailureReason, .resultStreamFailed)
  }

  func testAssistantStreamFailureReturnsPartialToManualFieldWithoutExecution() async {
    struct StreamFailure: Error {}

    let voice = VoiceHarness()
    var applicationOpenCount = 0
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
          openApplication: { _ in applicationOpenCount += 1 }
        )
      )
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.partial("Open Safari"))
    await waitUntil { model.phase == .listening("Open Safari") }
    voice.fail(StreamFailure())

    await waitUntil { model.manualTranscript == "Open Safari" }
    XCTAssertEqual(applicationOpenCount, 0)
    XCTAssertEqual(voice.finishCount, 0)
    XCTAssertEqual(voice.cancelCount, 1)
    XCTAssertEqual(
      model.phase,
      .failure(
        "Transcription stopped before finalizing. Open Topher to review the recovered text; it was not executed."
      )
    )
  }

  func testDictationDiagnosticsSeparateRawSpeechFromInsertedText() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherDictationDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL:
          temporaryRoot
          .appendingPathComponent("dev.topher.app", isDirectory: true)
          .appendingPathComponent("TranscriptDiagnostics", isDirectory: true),
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "",
      selection: FocusedTextRange(location: 0, length: 0)
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      developerDiagnostics: diagnostics,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.final("I I use GraphQL   URLSession"))
    model.endDictation()

    await waitUntil { diagnostics.records.count == 1 }
    let record = try XCTUnwrap(diagnostics.records.first)
    XCTAssertEqual(record.source, .dictation)
    XCTAssertEqual(record.transcript, "I I use GraphQL   URLSession")
    XCTAssertEqual(record.interpretedTranscript, "I use GraphQL URLSession")
    XCTAssertEqual(record.interpretationReason, .dictationDisfluencyCleanup)
    XCTAssertEqual(field.content, "I use GraphQL URLSession")
    XCTAssertEqual(record.outcome, .dictationInserted)
    XCTAssertEqual(
      record.capabilityIdentifier,
      FocusedTextInsertionCapability.descriptor.identifier
    )
  }

  func testDictationBecomingSecureIsDiscardedWithoutDiagnosticRetention() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherSecureDictationDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL:
          temporaryRoot
          .appendingPathComponent("dev.topher.app", isDirectory: true)
          .appendingPathComponent("TranscriptDiagnostics", isDirectory: true),
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "",
      selection: FocusedTextRange(location: 0, length: 0)
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      developerDiagnostics: diagnostics,
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    field.isSecure = true
    voice.yield(.final("sensitive secret"))
    model.endDictation()

    await waitUntil {
      model.phase
        == .failure("The target became secure, so Topher discarded the dictation.")
    }
    try? await Task.sleep(for: .milliseconds(20))
    XCTAssertNil(model.pendingDictationText)
    XCTAssertTrue(diagnostics.records.isEmpty)
  }

  func testMismatchedShortcutReleaseCannotEndAnotherShortcutsCapture() async {
    let voice = VoiceHarness(finishBehavior: .keepStreamOpen)
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      accessibilityPermission: authorizedAccessibilityPermission()
    )

    model.handleShortcutDown(.assistantCommand)
    await waitUntil { model.phase == .listening("") }

    model.handleShortcutDown(.dictation)
    model.handleShortcutUp(.dictation)
    await Task.yield()

    XCTAssertEqual(model.phase, .listening(""))
    XCTAssertEqual(voice.finishCount, 0)

    model.handleShortcutUp(.assistantCommand)
    await waitUntil { voice.finishCount == 1 }
    voice.completeStream()
  }

  func testCanonicalInstalledLocaleStartsOnFirstAuthorizedHold() async {
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(localeIdentifier: "en-US"),
      voice: voice
    )

    model.beginPushToTalk()

    await waitUntil { model.phase == .listening("") }
    XCTAssertEqual(model.voiceReadiness, .ready)
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
    XCTAssertEqual(voice.cancelCount, 0)
  }

  func testRepeatedBeginRequiresReleaseAfterPermissionAndAssetPreparation() async {
    var authorizationStatus = AVAuthorizationStatus.notDetermined
    var permissionRequestCount = 0
    let permission = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { authorizationStatus },
        requestAccess: {
          permissionRequestCount += 1
          authorizationStatus = .authorized
          return true
        }
      )
    )
    var inventoryStatus = SpeechAssetInventoryStatus.supported
    var installCount = 0
    let assets = SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: { true },
        supportedLocaleIdentifier: { _ in "en-US" },
        inventoryStatus: { _ in inventoryStatus },
        installAssets: { _, reportProgress in
          installCount += 1
          reportProgress(1)
          inventoryStatus = .installed
          return true
        }
      )
    )
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission,
      speechAssets: assets,
      voice: voice
    )

    model.beginPushToTalk()
    await waitUntil {
      model.phase == .success("Voice input is ready. Hold your shortcut again to speak.")
    }

    model.beginPushToTalk()
    await Task.yield()
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)

    model.endPushToTalk()
    model.beginPushToTalk()

    await waitUntil { model.phase == .listening("") }
    XCTAssertEqual(permissionRequestCount, 1)
    XCTAssertEqual(installCount, 1)
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
  }

  func testWhitespaceOnlyFinalTranscriptFailsWithoutExecuting() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherEmptyTranscriptDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }
    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL:
          temporaryRoot
          .appendingPathComponent("dev.topher.app", isDirectory: true)
          .appendingPathComponent("TranscriptDiagnostics", isDirectory: true),
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    let voice = VoiceHarness()
    var applicationOpenCount = 0
    var webOpenCount = 0
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
          openApplication: { _ in applicationOpenCount += 1 }
        )
      ),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { _ in webOpenCount += 1 })
      ),
      developerDiagnostics: diagnostics
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }

    voice.yield(.final(" \n\t "))
    model.endPushToTalk()

    await waitUntil {
      model.phase == .failure("I didn’t hear a command. Hold the shortcut and try again.")
        && diagnostics.records.count == 1
    }
    XCTAssertEqual(applicationOpenCount, 0)
    XCTAssertEqual(webOpenCount, 0)
    XCTAssertEqual(voice.finishCount, 1)
    let record = try XCTUnwrap(diagnostics.records.first)
    XCTAssertEqual(record.transcript, "")
    XCTAssertEqual(record.outcome, .noUsableSpeech)
  }

  func testDeniedMicrophonePermissionDoesNotStartTranscription() async {
    var didCheckAssets = false
    let voice = VoiceHarness()
    let assets = SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: {
          didCheckAssets = true
          return true
        },
        supportedLocaleIdentifier: { _ in
          XCTFail("Denied permission must stop before checking speech locales")
          return "en_US"
        },
        inventoryStatus: { _ in
          XCTFail("Denied permission must stop before checking speech assets")
          return .installed
        },
        installAssets: { _, _ in
          XCTFail("Denied permission must not install speech assets")
          return false
        }
      )
    )
    let model = makeModel(
      microphonePermission: permission(.denied),
      speechAssets: assets,
      voice: voice
    )

    model.beginPushToTalk()

    let deniedMessage = "Microphone denied. Open Topher’s menu to open Microphone Settings."
    await waitUntil { model.phase == .failure(deniedMessage) }
    XCTAssertEqual(model.voiceReadiness, .denied)
    XCTAssertFalse(didCheckAssets)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
    XCTAssertEqual(voice.finishCount, 0)
    XCTAssertEqual(voice.cancelCount, 0)
    XCTAssertEqual(model.voiceFeedback, .failure(deniedMessage))
  }

  func testFinalTranscriptReplacesStalePartialInFinalizingFeedback() async {
    let voice = VoiceHarness(finishBehavior: .keepStreamOpen)
    var openedTarget: String?
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { bundleIdentifier in
            openedTarget = bundleIdentifier
            return URL(fileURLWithPath: "/Applications/Safari.app")
          },
          openApplication: { _ in }
        )
      )
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.partial("Open Chrome"))
    await waitUntil { model.voiceFeedback == .listening("Open Chrome") }

    model.endPushToTalk()
    await waitUntil { model.voiceFeedback == .finalizing("Open Chrome") }
    voice.yield(.final("Open Safari."))
    await waitUntil { model.voiceFeedback == .finalizing("Open Safari.") }
    voice.completeStream()

    await waitUntil { model.phase == .success("Opened Safari.") }
    XCTAssertEqual(openedTarget, ApplicationTarget.safari.bundleIdentifier)
    XCTAssertEqual(model.voiceFeedback, .success("Opened Safari."))
  }

  func testManualAndMenuPreparationDoNotPresentCrossAppVoiceFeedback() async {
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
          openApplication: { _ in }
        )
      )
    )

    model.runManually()
    await waitUntil { model.phase == .success("Opened Safari.") }
    XCTAssertEqual(model.voiceFeedback, .hidden)

    model.prepareVoiceInput()
    await waitUntil {
      model.phase == .success("Voice input is ready. Hold your shortcut again to speak.")
    }
    XCTAssertEqual(model.voiceFeedback, .hidden)
  }

  func testInFlightCommandBlocksDuplicateManualAndVoiceExecution() async {
    var openCount = 0
    var openContinuation: CheckedContinuation<Void, Never>?
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
          openApplication: { _ in
            openCount += 1
            await withCheckedContinuation { openContinuation = $0 }
          }
        )
      )
    )

    model.runManually()
    await waitUntil { model.phase == .executing && openContinuation != nil }

    model.runManually()
    model.beginPushToTalk()
    await Task.yield()

    XCTAssertEqual(openCount, 1)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)

    openContinuation?.resume()
    openContinuation = nil
    await waitUntil { model.phase == .success("Opened Safari.") }
  }

  func testUnsupportedManualCommandCanRetryWithAValidCommand() async {
    var openCount = 0
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
          openApplication: { _ in openCount += 1 }
        )
      )
    )

    model.manualTranscript = "A webpage says open Safari"
    model.runManually()
    await waitUntil {
      model.phase
        == .failure(
          "Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”"
        )
    }

    model.manualTranscript = "Open Safari"
    model.runManually()
    await waitUntil { model.phase == .success("Opened Safari.") }

    XCTAssertEqual(openCount, 1)
  }

  func testEnabledDeveloperDiagnosticsRecordOnlyTheFinalVoiceTranscript() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherModelDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let recordedAt = Date(timeIntervalSince1970: 1_000)
    let store = DeveloperDiagnosticsStore(
      storageDirectoryURL:
        temporaryRoot
        .appendingPathComponent("dev.topher.app", isDirectory: true)
        .appendingPathComponent("TranscriptDiagnostics", isDirectory: true),
      initialEnabled: true,
      now: { recordedAt }
    )
    let diagnostics = DeveloperDiagnosticsController(
      store: store,
      now: { recordedAt },
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      developerDiagnostics: diagnostics
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.partial("Summarize this"))
    await waitUntil { model.phase == .listening("Summarize this") }
    model.endPushToTalk()
    voice.yield(
      .finalWithEvidence(
        FinalTranscription(text: "Summarize this page", confidence: 0.73)
      )
    )

    await waitUntil {
      diagnostics.records.count == 1
        && model.phase
          == .failure(
            "That request needs app, browser, or screen context that Topher does not have yet."
          )
    }

    let record = try XCTUnwrap(diagnostics.records.first)
    XCTAssertEqual(record.transcript, "Summarize this page")
    XCTAssertFalse(record.transcript.contains("Summarize this\n"))
    XCTAssertEqual(record.source, .voice)
    XCTAssertEqual(record.outcome, .unsupported)
    XCTAssertEqual(record.unsupportedReason, .contextRequired)
    XCTAssertNil(record.commandKind)
    XCTAssertEqual(record.transcriptionConfidence, 0.73)
    XCTAssertNotNil(record.holdToListeningMilliseconds)
    XCTAssertNotNil(record.listeningToFirstTranscriptMilliseconds)
    XCTAssertNotNil(record.keyUpToFinalMilliseconds)

    model.endPushToTalk()
    await Task.yield()
    XCTAssertEqual(diagnostics.records.count, 1)
  }

  func testEnabledDeveloperDiagnosticsRecordSuccessfulManualCommand() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherManualDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL:
          temporaryRoot
          .appendingPathComponent("dev.topher.app", isDirectory: true)
          .appendingPathComponent("TranscriptDiagnostics", isDirectory: true),
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    var openCount = 0
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
          openApplication: { _ in openCount += 1 }
        )
      ),
      developerDiagnostics: diagnostics
    )
    model.manualTranscript = "  Open Safari  "

    model.runManually()

    await waitUntil {
      model.phase == .success("Opened Safari.") && diagnostics.records.count == 1
    }
    let record = try XCTUnwrap(diagnostics.records.first)
    XCTAssertEqual(openCount, 1)
    XCTAssertEqual(record.transcript, "Open Safari")
    XCTAssertEqual(record.source, .manual)
    XCTAssertEqual(record.outcome, .capabilitySucceeded)
    XCTAssertEqual(record.commandKind, .openApplication)
    XCTAssertEqual(
      record.capabilityIdentifier,
      ApplicationOpenCapability.descriptor.identifier
    )
  }

  func testDeveloperDiagnosticsFailureDoesNotChangeCommandOutcome() async throws {
    let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherModelDiagnosticsFailureTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporaryRoot) }

    let appDirectory = temporaryRoot.appendingPathComponent("dev.topher.app", isDirectory: true)
    let outsideDirectory = temporaryRoot.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: false)
    try FileManager.default.createDirectory(
      at: outsideDirectory, withIntermediateDirectories: false)
    let storageDirectory = appDirectory.appendingPathComponent(
      "TranscriptDiagnostics",
      isDirectory: true
    )
    try FileManager.default.createSymbolicLink(
      at: storageDirectory,
      withDestinationURL: outsideDirectory
    )

    let diagnostics = DeveloperDiagnosticsController(
      store: DeveloperDiagnosticsStore(
        storageDirectoryURL: storageDirectory,
        initialEnabled: true
      ),
      appVersion: "test",
      appBuild: "1",
      maintenanceInterval: nil
    )
    var openCount = 0
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
          openApplication: { _ in openCount += 1 }
        )
      ),
      developerDiagnostics: diagnostics
    )
    model.manualTranscript = "Open Safari"

    model.runManually()

    await waitUntil {
      model.phase == .success("Opened Safari.")
        && diagnostics.errorMessage
          == "Couldn’t save the latest transcript diagnostic. The request still completed; Clear Now can retry cleanup."
        && diagnostics.hasPendingStorageMaintenance
    }
    XCTAssertEqual(openCount, 1)
    XCTAssertTrue(diagnostics.records.isEmpty)
  }

  func testModelDeinitShutsDownActiveVoiceCapture() async {
    let voice = VoiceHarness()
    var model: TopherModel? = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice
    )

    model?.beginPushToTalk()
    await waitUntil { model?.phase == .listening("") }

    model = nil

    await waitUntil { voice.cancelCount == 1 }
    XCTAssertEqual(voice.finishCount, 0)
  }

  func testDeniedPermissionRecoversCoherentlyAfterSettingsGrant() async {
    var authorizationStatus = AVAuthorizationStatus.denied
    let permission = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { authorizationStatus },
        requestAccess: {
          XCTFail("A recorded permission decision must not display a prompt")
          return false
        }
      )
    )
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission,
      speechAssets: readySpeechAssets(),
      voice: voice
    )

    model.beginPushToTalk()
    let deniedMessage = "Microphone denied. Open Topher’s menu to open Microphone Settings."
    await waitUntil { model.phase == .failure(deniedMessage) }
    XCTAssertEqual(model.voiceFeedback, .failure(deniedMessage))

    authorizationStatus = .authorized
    model.refreshVoiceReadiness()

    await waitUntil { model.voiceReadiness == .ready }
    XCTAssertEqual(model.phase, .idle)
    XCTAssertEqual(model.voiceFeedback, .hidden)
  }

  func testAcceptedPreparationClearsStalePermissionFailureBeforeLaterRefresh() async {
    var authorizationStatus = AVAuthorizationStatus.denied
    let permission = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { authorizationStatus },
        requestAccess: {
          XCTFail("A recorded permission decision must not display a prompt")
          return false
        }
      )
    )
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission,
      speechAssets: readySpeechAssets(),
      voice: voice
    )

    model.beginPushToTalk()
    let deniedMessage = "Microphone denied. Open Topher’s menu to open Microphone Settings."
    await waitUntil { model.phase == .failure(deniedMessage) }
    model.endPushToTalk()

    authorizationStatus = .authorized
    model.prepareVoiceInput()
    let readyMessage = "Voice input is ready. Hold your shortcut again to speak."
    await waitUntil { model.phase == .success(readyMessage) }

    model.refreshVoiceReadiness()
    await waitUntil { model.voiceReadiness == .ready }

    XCTAssertEqual(model.phase, .success(readyMessage))
    XCTAssertEqual(model.voiceFeedback, .hidden)
  }

  func testRestrictedPermissionExplainsPolicyWithoutSettingsRecovery() async {
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.restricted),
      speechAssets: readySpeechAssets(),
      voice: voice
    )

    model.beginPushToTalk()

    let message = "Microphone access is restricted by this Mac’s administrator or policy."
    await waitUntil { model.phase == .failure(message) }
    XCTAssertEqual(model.voiceReadiness, .restricted)
    XCTAssertFalse(model.voiceReadiness.needsSettings)
    XCTAssertEqual(model.voiceFeedback, .failure(message))
  }

  func testStaleReadinessCompletionCannotOverwriteNewPermissionState() async {
    var authorizationStatus = AVAuthorizationStatus.authorized
    let assets = SuspendedSpeechAssets()
    let permission = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { authorizationStatus },
        requestAccess: {
          XCTFail("A recorded permission decision must not display a prompt")
          return false
        }
      )
    )
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission,
      speechAssets: assets.client,
      voice: voice
    )
    await waitUntil { assets.isReadinessSuspended }

    authorizationStatus = .denied
    model.refreshVoiceReadiness()
    XCTAssertEqual(model.voiceReadiness, .denied)

    assets.resumeReadiness(with: "en_US")
    await Task.yield()

    XCTAssertEqual(model.voiceReadiness, .denied)
    XCTAssertEqual(
      model.phase,
      .failure("Allow Topher in System Settings → Privacy & Security → Microphone.")
    )
  }

  func testVoiceResultFeedbackDismissesWithoutChangingMenuOutcome() async {
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.denied),
      speechAssets: readySpeechAssets(),
      voice: voice,
      voiceFeedbackResultDuration: .milliseconds(20)
    )

    model.beginPushToTalk()
    let message = "Microphone denied. Open Topher’s menu to open Microphone Settings."
    await waitUntil { model.voiceFeedback == .failure(message) }
    await waitUntil { model.voiceFeedback == .hidden }

    XCTAssertEqual(model.phase, .failure(message))
    XCTAssertEqual(model.voiceReadiness, .denied)
  }

  func testDictationMaximumDurationFinalizesAndInsertsInsteadOfDiscarding() async {
    let voice = VoiceHarness()
    let field = ModelFocusedTextHarness(
      content: "Before ",
      selection: FocusedTextRange(location: 7, length: 0)
    )
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      listeningTimeout: .seconds(1),
      dictationListeningTimeout: .milliseconds(20),
      accessibilityPermission: authorizedAccessibilityPermission(),
      focusedTextInsertion: FocusedTextInsertionCapability(environment: field.environment)
    )

    model.beginDictation()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.final("preserved text"))

    await waitUntil {
      model.phase == .success("Inserted dictation.")
    }
    model.endDictation()
    await Task.yield()

    XCTAssertEqual(field.content, "Before preserved text")
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
    XCTAssertEqual(voice.finishCount, 1)
    XCTAssertEqual(voice.cancelCount, 0)
  }

  func testResultStreamFailureWhileListeningFailsAndCancelsImmediately() async {
    struct StreamFailure: Error {}

    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }

    voice.fail(StreamFailure())

    await waitUntil {
      model.phase == .failure("Voice transcription failed. Try the shortcut again.")
        && voice.cancelCount == 1
    }
    XCTAssertEqual(voice.finishCount, 0)
  }

  func testFinalizationTimesOutWhenFinishNeverCompletes() async {
    let voice = VoiceHarness(finishBehavior: .suspendUntilCancel)
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      finalizationTimeout: .milliseconds(20)
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    model.endPushToTalk()

    await waitUntil {
      model.phase == .failure("Voice finalization timed out. Try the shortcut again.")
        && voice.cancelCount == 1
    }
    XCTAssertEqual(voice.finishCount, 1)
  }

  func testFinalizationTimesOutWhenFinishReturnsButResultStreamStaysOpen() async {
    let voice = VoiceHarness(finishBehavior: .keepStreamOpen)
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      finalizationTimeout: .milliseconds(20)
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    model.endPushToTalk()

    await waitUntil {
      model.phase == .failure("Voice finalization timed out. Try the shortcut again.")
        && voice.cancelCount == 1
    }
    XCTAssertEqual(voice.finishCount, 1)
  }

  func testLateKeyUpAfterAutomaticFinalizationDoesNotDuplicateCompletion() async {
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      listeningTimeout: .milliseconds(20)
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    voice.yield(.final("Unsupported recovered phrase"))
    await waitUntil {
      model.phase
        == .failure(
          "Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”"
        )
    }

    model.endPushToTalk()
    await Task.yield()

    XCTAssertEqual(
      model.phase,
      .failure("Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”")
    )
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
    XCTAssertEqual(voice.finishCount, 1)
    XCTAssertEqual(voice.cancelCount, 0)
  }

  private func makeModel(
    microphonePermission: MicrophonePermissionClient,
    speechAssets: SpeechAssetPreparationClient,
    voice: VoiceHarness,
    applicationOpener: ApplicationOpenCapability? = nil,
    webOpener: WebOpenCapability? = nil,
    listeningTimeout: Duration = .seconds(1),
    dictationListeningTimeout: Duration? = nil,
    dictationPolishEnabled: Bool = true,
    finalizationTimeout: Duration = .seconds(1),
    voiceFeedbackResultDuration: Duration = .seconds(1),
    developerDiagnostics: DeveloperDiagnosticsController? = nil,
    accessibilityPermission: AccessibilityPermissionClient? = nil,
    focusedTextInsertion: FocusedTextInsertionCapability? = nil,
    dictationClipboard: DictationClipboardCapability? = nil
  ) -> TopherModel {
    TopherModel(
      applicationOpener: applicationOpener ?? inertApplicationOpener(),
      webOpener: webOpener ?? inertWebOpener(),
      microphonePermission: microphonePermission,
      speechAssets: speechAssets,
      voiceTranscription: voice.client,
      listeningTimeout: listeningTimeout,
      dictationListeningTimeout: dictationListeningTimeout ?? listeningTimeout,
      dictationPolishEnabled: dictationPolishEnabled,
      finalizationTimeout: finalizationTimeout,
      voiceFeedbackResultDuration: voiceFeedbackResultDuration,
      developerDiagnostics: developerDiagnostics,
      accessibilityPermission: accessibilityPermission,
      focusedTextInsertion: focusedTextInsertion,
      dictationClipboard: dictationClipboard,
      listenForShortcutEvents: false
    )
  }

  private func permission(_ status: AVAuthorizationStatus) -> MicrophonePermissionClient {
    MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { status },
        requestAccess: {
          XCTFail("A recorded permission decision must not display a prompt")
          return false
        }
      )
    )
  }

  private func authorizedAccessibilityPermission() -> AccessibilityPermissionClient {
    AccessibilityPermissionClient(
      environment: AccessibilityPermissionEnvironment(
        isProcessTrusted: { true },
        promptForTrust: {
          XCTFail("An authorized accessibility state must not prompt")
          return false
        }
      )
    )
  }

  private func readySpeechAssets(
    localeIdentifier: String = "en_US"
  ) -> SpeechAssetPreparationClient {
    SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: { true },
        supportedLocaleIdentifier: { _ in localeIdentifier },
        inventoryStatus: { _ in .installed },
        installAssets: { _, _ in
          XCTFail("Installed assets must not start an installation")
          return false
        }
      )
    )
  }

  private func inertApplicationOpener() -> ApplicationOpenCapability {
    ApplicationOpenCapability(
      workspace: ApplicationWorkspace(
        applicationURL: { _ in nil },
        openApplication: { _ in XCTFail("This test must not open an application") }
      )
    )
  }

  private func inertWebOpener() -> WebOpenCapability {
    WebOpenCapability(
      workspace: WebWorkspace(open: { _ in
        XCTFail("This test must not open a web URL")
      })
    )
  }

  private func waitUntil(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping @MainActor () -> Bool
  ) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !condition(), clock.now < deadline {
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(1))
    }

    XCTAssertTrue(condition(), "Condition was not satisfied before timeout", file: file, line: line)
  }
}

@MainActor
private final class ModelFocusedTextHarness {
  let element = FocusedTextElementID()
  var content: String
  var selection: FocusedTextRange
  var isSecure = false
  var role: FocusedTextTargetRole = .textArea
  var canSetSelectedText = true
  var canSetValue = false
  var exposesValue = false
  var selectedTextMutationSucceeds = true
  var valueMutationSucceeds = true
  var selectedTextReadCount = 0

  init(content: String, selection: FocusedTextRange) {
    self.content = content
    self.selection = selection
  }

  var profile: FocusedTextTargetProfile {
    FocusedTextTargetProfile(
      role: role,
      canSetSelectedText: canSetSelectedText,
      canSetSelectedRange: true,
      canSetValue: canSetValue
    )
  }

  var environment: FocusedTextInsertionEnvironment {
    FocusedTextInsertionEnvironment(
      focusedElement: { [weak self] in self?.element },
      sameElement: { $0 == $1 },
      processIdentifier: { _ in 1001 },
      isSecure: { [weak self] _ in self?.isSecure ?? true },
      role: { [weak self] _ in self?.role ?? .other },
      selectedText: { [weak self] _ in
        guard let self else { return nil }
        selectedTextReadCount += 1
        return (content as NSString).substring(
          with: NSRange(location: selection.location, length: selection.length)
        )
      },
      selectedRange: { [weak self] _ in self?.selection },
      value: { [weak self] _ in
        guard let self, exposesValue else { return nil }
        return content
      },
      text: { [weak self] _, range in
        guard let self else { return nil }
        let value = content as NSString
        guard range.endLocation <= value.length else { return nil }
        return value.substring(with: range.nsRange)
      },
      textContext: { [weak self] _, range in
        guard let self else { return FocusedTextContext() }
        let value = content as NSString
        let precedingLocation = max(0, range.location - 2)
        let followingLength = min(2, max(0, value.length - range.endLocation))
        return FocusedTextContext(
          precedingText: value.substring(
            with: NSRange(
              location: precedingLocation,
              length: range.location - precedingLocation
            )
          ),
          followingText: value.substring(
            with: NSRange(location: range.endLocation, length: followingLength)
          )
        )
      },
      canSetSelectedText: { [weak self] _ in self?.canSetSelectedText ?? false },
      canSetSelectedRange: { _ in true },
      canSetValue: { [weak self] _ in self?.canSetValue ?? false },
      setSelectedText: { [weak self] _, text in
        guard let self, canSetSelectedText else { return false }
        if selectedTextMutationSucceeds {
          content = (content as NSString).replacingCharacters(
            in: NSRange(location: selection.location, length: selection.length),
            with: text
          )
        }
        return true
      },
      setSelectedRange: { [weak self] _, range in
        self?.selection = range
        return self != nil
      },
      setValue: { [weak self] _, value in
        guard let self, canSetValue else { return false }
        if valueMutationSucceeds {
          content = value
        }
        return true
      },
      waitForMutation: { _ in },
      release: { _ in }
    )
  }
}

@MainActor
private final class VoiceHarness {
  enum FinishBehavior {
    case finishStream
    case keepStreamOpen
    case suspendUntilCancel
  }

  private let stream: AsyncThrowingStream<TranscriptionEvent, any Error>
  private let continuation: AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation
  private let finishBehavior: FinishBehavior
  private let suspendCancel: Bool
  private var finishWaiter: CheckedContinuation<Void, Never>?
  private var cancelWaiter: CheckedContinuation<Void, Never>?

  private(set) var prepareCount = 0
  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var cancelCount = 0

  init(
    finishBehavior: FinishBehavior = .finishStream,
    suspendCancel: Bool = false
  ) {
    (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self)
    self.finishBehavior = finishBehavior
    self.suspendCancel = suspendCancel
  }

  var client: VoiceTranscriptionClient {
    VoiceTranscriptionClient(
      prepare: { [weak self] in self?.prepareCount += 1 },
      start: { [weak self] in
        guard let self else { throw HarnessError.deallocated }
        startCount += 1
        return stream
      },
      finish: { [weak self] in
        guard let self else { return }
        finishCount += 1
        switch finishBehavior {
        case .finishStream:
          continuation.finish()
        case .keepStreamOpen:
          break
        case .suspendUntilCancel:
          await withCheckedContinuation { finishWaiter = $0 }
        }
      },
      cancel: { [weak self] in
        guard let self else { return }
        cancelCount += 1
        finishWaiter?.resume()
        finishWaiter = nil
        if suspendCancel {
          await withCheckedContinuation { cancelWaiter = $0 }
        }
        continuation.finish()
      }
    )
  }

  func yield(_ event: TranscriptionEvent) {
    continuation.yield(event)
  }

  func fail(_ error: any Error) {
    continuation.finish(throwing: error)
  }

  func completeStream() {
    continuation.finish()
  }

  func resumeCancel() {
    guard let cancelWaiter else {
      XCTFail("Cancel is not suspended")
      return
    }
    self.cancelWaiter = nil
    cancelWaiter.resume()
  }

  private enum HarnessError: Error {
    case deallocated
  }
}

@MainActor
private final class SuspendedSpeechAssets {
  private var readinessContinuation: CheckedContinuation<String?, Never>?

  var isReadinessSuspended: Bool {
    readinessContinuation != nil
  }

  var client: SpeechAssetPreparationClient {
    SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: { true },
        supportedLocaleIdentifier: { [weak self] _ in
          guard let self else { return nil }
          return await withCheckedContinuation { continuation in
            readinessContinuation = continuation
          }
        },
        inventoryStatus: { _ in .installed },
        installAssets: { _, _ in
          XCTFail("Installed assets must not start an installation")
          return false
        }
      )
    )
  }

  func resumeReadiness(with localeIdentifier: String?) {
    let continuation = readinessContinuation
    readinessContinuation = nil
    continuation?.resume(returning: localeIdentifier)
  }
}
