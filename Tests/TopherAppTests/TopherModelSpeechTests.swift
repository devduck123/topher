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
    voice.yield(.final("Summarize this page"))

    await waitUntil {
      diagnostics.records.count == 1
        && model.phase
          == .failure(
            "Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”"
          )
    }

    let record = try XCTUnwrap(diagnostics.records.first)
    XCTAssertEqual(record.transcript, "Summarize this page")
    XCTAssertFalse(record.transcript.contains("Summarize this\n"))
    XCTAssertEqual(record.source, .voice)
    XCTAssertEqual(record.outcome, .unsupported)
    XCTAssertNil(record.commandKind)

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
          == "Couldn’t save the latest transcript diagnostic. The command still ran; Clear Now can retry cleanup."
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

  func testListeningTimeoutCancelsTranscription() async {
    let voice = VoiceHarness()
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      listeningTimeout: .milliseconds(20)
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }

    await waitUntil {
      model.phase == .failure("Listening timed out. Try the shortcut again.")
    }
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
    XCTAssertEqual(voice.finishCount, 0)
    XCTAssertEqual(voice.cancelCount, 1)
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

  func testKeyUpDuringSuspendedTimeoutCleanupDoesNotFinishOrOverwriteFailure() async {
    let voice = VoiceHarness(suspendCancel: true)
    let model = makeModel(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      listeningTimeout: .milliseconds(20)
    )

    model.beginPushToTalk()
    await waitUntil { model.phase == .listening("") }
    await waitUntil {
      model.phase == .failure("Listening timed out. Try the shortcut again.")
        && voice.cancelCount == 1
    }

    model.endPushToTalk()
    model.runManually()
    model.beginPushToTalk()
    await Task.yield()

    XCTAssertEqual(model.phase, .failure("Listening timed out. Try the shortcut again."))
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
    XCTAssertEqual(voice.finishCount, 0)
    voice.resumeCancel()
  }

  private func makeModel(
    microphonePermission: MicrophonePermissionClient,
    speechAssets: SpeechAssetPreparationClient,
    voice: VoiceHarness,
    applicationOpener: ApplicationOpenCapability? = nil,
    webOpener: WebOpenCapability? = nil,
    listeningTimeout: Duration = .seconds(1),
    finalizationTimeout: Duration = .seconds(1),
    voiceFeedbackResultDuration: Duration = .seconds(1),
    developerDiagnostics: DeveloperDiagnosticsController? = nil
  ) -> TopherModel {
    TopherModel(
      applicationOpener: applicationOpener ?? inertApplicationOpener(),
      webOpener: webOpener ?? inertWebOpener(),
      microphonePermission: microphonePermission,
      speechAssets: speechAssets,
      voiceTranscription: voice.client,
      listeningTimeout: listeningTimeout,
      finalizationTimeout: finalizationTimeout,
      voiceFeedbackResultDuration: voiceFeedbackResultDuration,
      developerDiagnostics: developerDiagnostics,
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
