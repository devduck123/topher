import AVFoundation
import Dispatch
import Foundation
import XCTest

@testable import TopherApp

@MainActor
final class PushToTalkCaptureControllerTests: XCTestCase {
  func testFirstPermissionGrantPreparesWithoutRecordingAndRequiresPhysicalRelease() async {
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
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission,
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertEqual(controller.readiness, .needsPermission)
    XCTAssertTrue(controller.beginHold())

    await waitUntil { recorder.events.contains(.readyForNextHold) }

    XCTAssertEqual(permissionRequestCount, 1)
    XCTAssertEqual(controller.readiness, .ready)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
    XCTAssertFalse(controller.beginHold(), "The original hold must end before capture can start")

    controller.endHold()
    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }

    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)

    voice.yield(.final("Open Safari."))
    controller.endHold()
    await waitUntil { recorder.events.contains(.completed("Open Safari.")) }
  }

  func testAssetInstallationPreparesWithoutRecordingAndRequiresAnotherHold() async {
    var inventoryStatus = SpeechAssetInventoryStatus.supported
    var installCount = 0
    let assets = SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: { true },
        supportedLocaleIdentifier: { _ in "en-US" },
        inventoryStatus: { _ in inventoryStatus },
        installAssets: { _, reportProgress in
          installCount += 1
          reportProgress(0.5)
          reportProgress(1)
          inventoryStatus = .installed
          return true
        }
      )
    )
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: assets,
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.readyForNextHold) }

    XCTAssertEqual(installCount, 1)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
    XCTAssertTrue(
      recorder.events.contains(
        .stateChanged(.preparing(.speechAssets(.preparing(progress: 0.5))))
      )
    )
    XCTAssertFalse(controller.beginHold())

    controller.endHold()
    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }

    voice.yield(.final("Ready"))
    controller.endHold()
    await waitUntil { recorder.events.contains(.completed("Ready")) }
  }

  func testMenuPreparationNeverStartsTranscriptionAndClearsStaleHeldGate() async {
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    voice.fail(CaptureHarnessError.streamFailed)
    await waitUntil { recorder.events.contains(.failed(.resultStreamFailed)) }
    await waitUntil { !controller.isBusy }

    XCTAssertTrue(controller.prepareForUse())
    await waitUntil {
      recorder.events.filter { $0 == .readyForNextHold }.count == 1
    }

    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 1)
  }

  func testReleaseWhileTranscriptionPreparationIsSuspendedNeverStartsMicrophone() async {
    let voice = CaptureVoiceHarness(prepareBehavior: .suspend)
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { voice.isPrepareSuspended }

    controller.endHold()
    voice.resumePrepare()

    await waitUntil { recorder.events.contains(.releasedBeforeListening) }
    XCTAssertEqual(voice.prepareCount, 1)
    XCTAssertEqual(voice.startCount, 0)
    XCTAssertEqual(voice.cancelCount, 1)
    XCTAssertFalse(controller.isBusy)
  }

  func testLateFinalReplacesPartialAndCompletionPreservesRawText() async {
    let voice = CaptureVoiceHarness(finishBehavior: .keepStreamOpen)
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }

    voice.yield(.partial("Open Chrome"))
    await waitUntil { recorder.events.contains(.stateChanged(.listening("Open Chrome"))) }

    controller.endHold()
    controller.endHold()
    await waitUntil { recorder.events.contains(.stateChanged(.finalizing("Open Chrome"))) }

    let rawFinal = "  Open Safari.  \n"
    voice.yield(.final(rawFinal))
    await waitUntil { recorder.events.contains(.stateChanged(.finalizing(rawFinal))) }
    voice.completeStream()

    await waitUntil { recorder.events.contains(.completed(rawFinal)) }
    XCTAssertEqual(voice.finishCount, 1)
    XCTAssertEqual(voice.cancelCount, 0)
    XCTAssertFalse(controller.isBusy)
  }

  func testWhitespaceFinalIsReturnedUnchangedForConsumerSpecificHandling() async {
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )
    let whitespace = " \n\t "

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    voice.yield(.final(whitespace))
    controller.endHold()

    await waitUntil { recorder.events.contains(.completed(whitespace)) }
  }

  func testCompletionCarriesMeasuredCaptureStageTimings() async throws {
    let voice = CaptureVoiceHarness(
      prepareBehavior: .suspend,
      finishBehavior: .keepStreamOpen
    )
    let recorder = CaptureEventRecorder()
    let uptime = UptimeBox(0)
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder,
      uptimeNanoseconds: { uptime.value }
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { voice.isPrepareSuspended }
    uptime.value = 10_000_000
    voice.resumePrepare()
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }

    uptime.value = 60_000_000
    voice.yield(.partial("Open Codex"))
    await waitUntil { recorder.events.contains(.stateChanged(.listening("Open Codex"))) }

    uptime.value = 100_000_000
    controller.endHold()
    await waitUntil { recorder.events.contains(.stateChanged(.finalizing("Open Codex"))) }

    uptime.value = 140_000_000
    voice.yield(
      .finalWithEvidence(
        FinalTranscription(text: "Open Codex", confidence: 0.8)
      )
    )
    voice.completeStream()

    await waitUntil {
      recorder.events.contains { event in
        guard case .completedWithEvidence = event else { return false }
        return true
      }
    }
    let completion = try XCTUnwrap(
      recorder.events.compactMap { event -> FinalTranscription? in
        guard case .completedWithEvidence(let transcription) = event else { return nil }
        return transcription
      }.last
    )
    XCTAssertEqual(
      completion.captureMetrics,
      VoiceCaptureMetrics(
        holdToListeningMilliseconds: 10,
        listeningToFirstTranscriptMilliseconds: 50,
        keyUpToFinalMilliseconds: 40
      )
    )
  }

  func testNormalResultStreamEndWhileListeningFailsAndCancels() async {
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    voice.completeStream()

    await waitUntil {
      recorder.events.contains(.failed(.resultStreamEnded)) && voice.cancelCount == 1
    }
    XCTAssertEqual(voice.finishCount, 0)
    XCTAssertFalse(controller.isBusy)
  }

  func testResultStreamFailureFailsAndCancelsImmediately() async {
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    voice.fail(CaptureHarnessError.streamFailed)

    await waitUntil {
      recorder.events.contains(.failed(.resultStreamFailed)) && voice.cancelCount == 1
    }
    XCTAssertEqual(voice.finishCount, 0)
    XCTAssertFalse(controller.isBusy)
  }

  func testMaximumDurationFinalizesExactlyOnceAndRequiresPhysicalRelease() async {
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder,
      listeningTimeout: .milliseconds(20)
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    voice.yield(
      .finalWithEvidence(
        FinalTranscription(text: "Preserve this dictation.", confidence: 0.9)
      )
    )
    await waitUntil {
      recorder.events.contains(.maximumDurationReached("Preserve this dictation."))
        && recorder.events.contains { event in
          guard case .completedWithEvidence(let transcription) = event else { return false }
          return transcription.primary.text == "Preserve this dictation."
            && transcription.captureMetrics?.maximumDurationReached == true
        }
    }

    XCTAssertEqual(voice.finishCount, 1)
    XCTAssertEqual(voice.cancelCount, 0)
    XCTAssertFalse(controller.beginHold(), "The physical key must still be released")
    controller.endHold()
    XCTAssertTrue(controller.beginHold())
  }

  func testFinalizationTimesOutWhenFinishNeverReturns() async {
    let voice = CaptureVoiceHarness(finishBehavior: .suspendUntilCancel)
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder,
      finalizationTimeout: .milliseconds(20)
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    controller.endHold()

    await waitUntil {
      recorder.events.contains(.failed(.finalizationTimedOut)) && voice.cancelCount == 1
    }
    XCTAssertEqual(voice.finishCount, 1)
    XCTAssertFalse(controller.isBusy)
  }

  func testFinalizationTimesOutWhenFinishReturnsButResultStreamStaysOpen() async {
    let voice = CaptureVoiceHarness(finishBehavior: .keepStreamOpen)
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder,
      finalizationTimeout: .milliseconds(20)
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    controller.endHold()

    await waitUntil {
      recorder.events.contains(.failed(.finalizationTimedOut)) && voice.cancelCount == 1
    }
    XCTAssertEqual(voice.finishCount, 1)
    XCTAssertFalse(controller.isBusy)
  }

  func testFinalizationFailureIsDistinctFromTimeoutAndCancels() async {
    let voice = CaptureVoiceHarness(finishBehavior: .fail)
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }
    voice.yield(.partial("Recover this partial"))
    await waitUntil {
      recorder.events.contains(.stateChanged(.listening("Recover this partial")))
    }
    controller.endHold()

    await waitUntil {
      recorder.events.contains(
        .failedWithRecovery(.finalizationFailed, transcript: "Recover this partial")
      ) && voice.cancelCount == 1
    }
    XCTAssertFalse(recorder.events.contains(.failed(.finalizationTimedOut)))
  }

  func testStartFailureCancelsButStillRequiresKeyReleaseBeforeRetry() async {
    let voice = CaptureVoiceHarness(startBehavior: .fail)
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil {
      recorder.events.contains(.failed(.startFailed)) && voice.cancelCount == 1
    }

    XCTAssertFalse(controller.isBusy)
    XCTAssertFalse(controller.beginHold(), "Start failure preserves the physical held-key gate")
    controller.endHold()
    XCTAssertTrue(controller.beginHold())
  }

  func testDeniedPermissionStopsBeforeAssetOrTranscriptionWork() async {
    var didCheckAssets = false
    let assets = SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: {
          didCheckAssets = true
          return true
        },
        supportedLocaleIdentifier: { _ in
          XCTFail("Denied permission must stop before locale lookup")
          return nil
        },
        inventoryStatus: { _ in
          XCTFail("Denied permission must stop before inventory lookup")
          return .unsupported
        },
        installAssets: { _, _ in
          XCTFail("Denied permission must not install assets")
          return false
        }
      )
    )
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.denied),
      speechAssets: assets,
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.failed(.microphoneDenied)) }

    XCTAssertEqual(controller.readiness, .denied)
    XCTAssertFalse(didCheckAssets)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
    XCTAssertEqual(voice.cancelCount, 0)
  }

  func testRestrictedPermissionPublishesDistinctFailure() async {
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.restricted),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.failed(.microphoneRestricted)) }

    XCTAssertEqual(controller.readiness, .restricted)
    XCTAssertTrue(
      recorder.events.contains(.readinessChanged(.restricted, permission: .restricted))
    )
  }

  func testAssetPreparationFailureIsVisibleAndDoesNotStartTranscription() async {
    let assets = SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: { true },
        supportedLocaleIdentifier: { _ in "en_US" },
        inventoryStatus: { _ in .supported },
        installAssets: { _, _ in throw CaptureHarnessError.assetInstallFailed }
      )
    )
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: assets,
      voice: voice,
      recorder: recorder
    )

    XCTAssertTrue(controller.beginHold())
    await waitUntil { recorder.events.contains(.failed(.speechAssetPreparationFailed)) }

    XCTAssertEqual(controller.readiness, .needsAssets)
    XCTAssertEqual(voice.prepareCount, 0)
    XCTAssertEqual(voice.startCount, 0)
  }

  func testStaleReadinessCompletionCannotOverwriteNewPermissionState() async {
    var authorizationStatus = AVAuthorizationStatus.authorized
    let assets = SuspendedCaptureSpeechAssets()
    let permission = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { authorizationStatus },
        requestAccess: {
          XCTFail("Recorded authorization must not prompt")
          return false
        }
      )
    )
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    let controller = makeController(
      microphonePermission: permission,
      speechAssets: assets.client,
      voice: voice,
      recorder: recorder
    )

    controller.refreshReadiness()
    await waitUntil { assets.isReadinessSuspended }

    authorizationStatus = .denied
    controller.refreshReadiness()
    XCTAssertEqual(controller.readiness, .denied)

    assets.resumeReadiness(with: "en_US")
    await Task.yield()

    XCTAssertEqual(controller.readiness, .denied)
    XCTAssertEqual(
      recorder.events.last,
      .readinessChanged(.denied, permission: .denied)
    )
  }

  func testShutdownCancelsActiveCaptureAndReleasesTheController() async {
    let voice = CaptureVoiceHarness()
    let recorder = CaptureEventRecorder()
    var controller: PushToTalkCaptureController? = makeController(
      microphonePermission: permission(.authorized),
      speechAssets: readySpeechAssets(),
      voice: voice,
      recorder: recorder
    )
    weak let weakController = controller

    XCTAssertTrue(controller?.beginHold() == true)
    await waitUntil { recorder.events.contains(.stateChanged(.listening(""))) }

    controller?.shutdown()
    controller = nil

    await waitUntil { voice.cancelCount == 1 && weakController == nil }
    XCTAssertEqual(voice.finishCount, 0)
  }

  private func makeController(
    microphonePermission: MicrophonePermissionClient,
    speechAssets: SpeechAssetPreparationClient,
    voice: CaptureVoiceHarness,
    recorder: CaptureEventRecorder,
    listeningTimeout: Duration = .seconds(1),
    finalizationTimeout: Duration = .seconds(1),
    uptimeNanoseconds: @escaping @MainActor () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) -> PushToTalkCaptureController {
    let controller = PushToTalkCaptureController(
      microphonePermission: microphonePermission,
      speechAssets: speechAssets,
      transcription: voice.client,
      listeningTimeout: listeningTimeout,
      finalizationTimeout: finalizationTimeout,
      uptimeNanoseconds: uptimeNanoseconds
    )
    controller.onEvent = { [weak recorder] event in
      recorder?.events.append(event)
    }
    return controller
  }

  private func permission(_ status: AVAuthorizationStatus) -> MicrophonePermissionClient {
    MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { status },
        requestAccess: {
          XCTFail("Recorded authorization must not prompt")
          return false
        }
      )
    )
  }

  private func readySpeechAssets() -> SpeechAssetPreparationClient {
    SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: { true },
        supportedLocaleIdentifier: { _ in "en_US" },
        inventoryStatus: { _ in .installed },
        installAssets: { _, _ in
          XCTFail("Installed assets must not start installation")
          return false
        }
      )
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
private final class CaptureEventRecorder {
  var events: [PushToTalkCaptureEvent] = []
}

@MainActor
private final class UptimeBox {
  var value: UInt64

  init(_ value: UInt64) {
    self.value = value
  }
}

@MainActor
private final class CaptureVoiceHarness {
  enum PrepareBehavior: Equatable {
    case immediate
    case suspend
  }

  enum StartBehavior: Equatable {
    case immediate
    case fail
  }

  enum FinishBehavior {
    case finishStream
    case keepStreamOpen
    case suspendUntilCancel
    case fail
  }

  private let stream: AsyncThrowingStream<TranscriptionEvent, any Error>
  private let continuation: AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation
  private let prepareBehavior: PrepareBehavior
  private let startBehavior: StartBehavior
  private let finishBehavior: FinishBehavior
  private let suspendCancel: Bool
  private var prepareWaiter: CheckedContinuation<Void, Never>?
  private var finishWaiter: CheckedContinuation<Void, Never>?
  private var cancelWaiter: CheckedContinuation<Void, Never>?

  private(set) var prepareCount = 0
  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var cancelCount = 0

  init(
    prepareBehavior: PrepareBehavior = .immediate,
    startBehavior: StartBehavior = .immediate,
    finishBehavior: FinishBehavior = .finishStream,
    suspendCancel: Bool = false
  ) {
    (stream, continuation) = AsyncThrowingStream.makeStream(of: TranscriptionEvent.self)
    self.prepareBehavior = prepareBehavior
    self.startBehavior = startBehavior
    self.finishBehavior = finishBehavior
    self.suspendCancel = suspendCancel
  }

  var isPrepareSuspended: Bool { prepareWaiter != nil }

  var client: VoiceTranscriptionClient {
    VoiceTranscriptionClient(
      prepare: { [weak self] in
        guard let self else { throw CaptureHarnessError.deallocated }
        prepareCount += 1
        if prepareBehavior == .suspend {
          await withCheckedContinuation { prepareWaiter = $0 }
        }
      },
      start: { [weak self] in
        guard let self else { throw CaptureHarnessError.deallocated }
        startCount += 1
        if startBehavior == .fail {
          throw CaptureHarnessError.startFailed
        }
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
        case .fail:
          throw CaptureHarnessError.finishFailed
        }
      },
      cancel: { [weak self] in
        guard let self else { return }
        cancelCount += 1
        prepareWaiter?.resume()
        prepareWaiter = nil
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

  func resumePrepare() {
    guard let prepareWaiter else {
      XCTFail("Prepare is not suspended")
      return
    }
    self.prepareWaiter = nil
    prepareWaiter.resume()
  }

  func resumeCancel() {
    guard let cancelWaiter else {
      XCTFail("Cancel is not suspended")
      return
    }
    self.cancelWaiter = nil
    cancelWaiter.resume()
  }
}

private enum CaptureHarnessError: Error, Equatable, Sendable {
  case deallocated
  case startFailed
  case finishFailed
  case streamFailed
  case assetInstallFailed
}

@MainActor
private final class SuspendedCaptureSpeechAssets {
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
          XCTFail("Installed assets must not start installation")
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
