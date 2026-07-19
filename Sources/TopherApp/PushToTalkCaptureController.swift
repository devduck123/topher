import Dispatch
import Foundation
import OSLog

enum VoiceCaptureReadiness: Equatable, Sendable {
  case checking
  case needsPermission
  case needsAssets
  case preparing(progress: Double?)
  case ready
  case denied
  case restricted
  case unavailable

  var title: String {
    switch self {
    case .checking:
      "Checking voice input…"
    case .needsPermission:
      "Microphone permission required"
    case .needsAssets:
      "Local speech model needs preparation"
    case .preparing(let progress):
      if let progress {
        "Preparing local speech model… \(Int(progress * 100))%"
      } else {
        "Preparing local speech model…"
      }
    case .ready:
      "On-device voice input ready"
    case .denied:
      "Microphone access denied"
    case .restricted:
      "Microphone access restricted"
    case .unavailable:
      "On-device voice input unavailable"
    }
  }

  var canPrepare: Bool {
    switch self {
    case .needsPermission, .needsAssets:
      true
    case .checking, .preparing, .ready, .denied, .restricted, .unavailable:
      false
    }
  }

  var needsSettings: Bool {
    switch self {
    case .denied:
      true
    case .checking, .needsPermission, .needsAssets, .preparing, .ready, .restricted,
      .unavailable:
      false
    }
  }
}

enum PushToTalkCaptureState: Equatable, Sendable {
  enum Preparation: Equatable, Sendable {
    case microphonePermission
    case speechModel
    case speechAssets(VoiceCaptureReadiness)
  }

  case preparing(Preparation)
  case listening(String)
  case finalizing(String)
}

enum PushToTalkCaptureFailure: String, Codable, Equatable, Sendable {
  case microphonePermissionRequired
  case microphoneDenied
  case microphoneRestricted
  case speechModelNotReady
  case speechAssetPreparationFailed
  case startFailed
  case resultStreamEnded
  case resultStreamFailed
  case finalizationFailed
  case finalizationTimedOut
}

enum PushToTalkCaptureEvent: Equatable, Sendable {
  case readinessChanged(
    VoiceCaptureReadiness,
    permission: MicrophonePermissionState
  )
  case stateChanged(PushToTalkCaptureState)
  case readyForNextHold
  case releasedBeforeListening
  case maximumDurationReached(String)
  case completed(String)
  case completedWithEvidence(FinalTranscription)
  case failed(PushToTalkCaptureFailure)
  case failedWithRecovery(PushToTalkCaptureFailure, transcript: String)
}

/// Owns one global push-to-talk capture lifecycle without deciding what the
/// resulting transcript means.
///
/// Shortcut routing, user-facing copy, and command or dictation processing stay
/// with the caller. Apple framework and microphone details remain behind
/// `VoiceTranscriptionClient`.
@MainActor
final class PushToTalkCaptureController {
  typealias EventHandler = @MainActor (PushToTalkCaptureEvent) -> Void

  private enum Phase {
    case idle
    case preparing
    case listening(String)
    case finalizing(String)
    case cleaningUp
  }

  private enum FinalizationOutcome: Equatable, Sendable {
    case completed
    case failed
    case timedOut
  }

  private struct TimingAccumulator {
    let holdStartedAt: UInt64
    var listeningStartedAt: UInt64?
    var firstTranscriptAt: UInt64?
    var releasedAt: UInt64?
    var maximumDurationReached = false
  }

  var onEvent: EventHandler = { _ in }

  private(set) var readiness: VoiceCaptureReadiness

  var isBusy: Bool {
    switch phase {
    case .idle:
      false
    case .preparing, .listening, .finalizing, .cleaningUp:
      true
    }
  }

  private let microphonePermission: MicrophonePermissionClient
  private let speechAssets: SpeechAssetPreparationClient
  private let transcription: VoiceTranscriptionClient
  private let listeningTimeout: Duration
  private let finalizationTimeout: Duration
  private let uptimeNanoseconds: @MainActor () -> UInt64
  private let logger = Logger(subsystem: "dev.topher.app", category: "voice-capture")
  private let signposter = OSSignposter(subsystem: "dev.topher.app", category: "voice-capture")

  private var phase: Phase = .idle
  private var lifecycleTask: Task<Void, Never>?
  private var transcriptionEventsTask: Task<Void, Never>?
  private var listeningTimeoutTask: Task<Void, Never>?
  private var readinessRefreshTask: Task<Void, Never>?
  private var isHeld = false
  private var generation: UInt64 = 0
  private var readinessGeneration: UInt64 = 0
  private var finalTranscript = ""
  private var finalTranscriptionEvidence: FinalTranscription?
  private var timing: TimingAccumulator?
  private var isShutDown = false
  private var preparationInterval: OSSignpostIntervalState?
  private var captureInterval: OSSignpostIntervalState?
  private var finalizationInterval: OSSignpostIntervalState?

  init(
    microphonePermission: MicrophonePermissionClient = .init(),
    speechAssets: SpeechAssetPreparationClient = .init(),
    transcription: VoiceTranscriptionClient = .live(),
    listeningTimeout: Duration = .seconds(30),
    finalizationTimeout: Duration = .seconds(8),
    uptimeNanoseconds: @escaping @MainActor () -> UInt64 = {
      DispatchTime.now().uptimeNanoseconds
    }
  ) {
    self.microphonePermission = microphonePermission
    self.speechAssets = speechAssets
    self.transcription = transcription
    self.listeningTimeout = listeningTimeout
    self.finalizationTimeout = finalizationTimeout
    self.uptimeNanoseconds = uptimeNanoseconds
    readiness = Self.permissionReadiness(microphonePermission.currentState)
  }

  deinit {
    lifecycleTask?.cancel()
    transcriptionEventsTask?.cancel()
    listeningTimeoutTask?.cancel()
    readinessRefreshTask?.cancel()
  }

  func refreshReadiness() {
    guard !isShutDown else { return }

    invalidateReadinessRefresh()
    let token = readinessGeneration
    let permissionState = microphonePermission.currentState

    guard permissionState == .authorized else {
      publishReadiness(Self.permissionReadiness(permissionState), permission: permissionState)
      return
    }

    publishReadiness(.checking, permission: permissionState)
    let speechAssets = speechAssets
    readinessRefreshTask = Task { [weak self] in
      let assetState = await speechAssets.readiness()
      guard
        let self,
        !Task.isCancelled,
        readinessGeneration == token,
        microphonePermission.currentState == .authorized
      else { return }

      publishReadiness(Self.assetReadiness(assetState), permission: .authorized)
    }
  }

  @discardableResult
  func prepareForUse() -> Bool {
    guard !isShutDown, !isBusy else { return false }

    // Menu preparation is an explicit non-hold action. It also clears a stale
    // held bit left while waiting for key-up after first-run setup.
    isHeld = false
    startPreparation(startWhenReady: false)
    return true
  }

  @discardableResult
  func beginHold(maximumDuration: Duration? = nil) -> Bool {
    guard !isShutDown, !isBusy, !isHeld else { return false }

    isHeld = true
    startPreparation(
      startWhenReady: true,
      maximumDuration: maximumDuration ?? listeningTimeout
    )
    return true
  }

  func endHold() {
    guard !isShutDown else { return }

    isHeld = false
    finalizeListening(maximumDurationReached: false)
  }

  private func finalizeListening(maximumDurationReached: Bool) {
    guard case .listening(let visibleTranscript) = phase else { return }

    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = nil
    endCaptureInterval()
    beginFinalizationInterval()
    timing?.releasedAt = uptimeNanoseconds()
    timing?.maximumDurationReached = maximumDurationReached
    phase = .finalizing(visibleTranscript)
    if maximumDurationReached {
      onEvent(.maximumDurationReached(visibleTranscript))
      logger.notice("Maximum capture duration reached; finalizing")
    } else {
      onEvent(.stateChanged(.finalizing(visibleTranscript)))
      logger.info("Push-to-talk ended")
    }

    let token = generation
    let currentEventsTask = transcriptionEventsTask
    lifecycleTask = Task { [weak self] in
      guard let self else { return }

      let outcome = await finalize(eventsTask: currentEventsTask)
      guard generation == token else { return }

      switch outcome {
      case .completed:
        let transcript = finalTranscript
        let evidence = finalTranscriptionEvidence
        let metrics = captureMetrics(completedAt: uptimeNanoseconds())
        clearTranscriptionResult()
        timing = nil
        endFinalizationInterval()
        phase = .idle
        if let evidence, let metrics {
          onEvent(.completedWithEvidence(evidence.addingCaptureMetrics(metrics)))
        } else if let evidence {
          onEvent(.completedWithEvidence(evidence))
        } else {
          onEvent(.completed(transcript))
        }
      case .failed:
        await failAndCancel(.finalizationFailed, token: token)
      case .timedOut:
        await failAndCancel(.finalizationTimedOut, token: token)
      }
    }
  }

  /// Invalidates all controller-owned work and asynchronously tears down the
  /// speech engine without retaining this controller.
  ///
  /// The owner calls this before releasing the controller. Relying on
  /// `deinit` alone is insufficient while a controller-owned task is awaiting
  /// an open result stream and therefore temporarily retains the controller.
  func shutdown() {
    guard !isShutDown else { return }
    isShutDown = true

    generation &+= 1
    readinessGeneration &+= 1
    isHeld = false
    phase = .idle
    onEvent = { _ in }

    lifecycleTask?.cancel()
    lifecycleTask = nil
    transcriptionEventsTask?.cancel()
    transcriptionEventsTask = nil
    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = nil
    readinessRefreshTask?.cancel()
    readinessRefreshTask = nil
    endOpenIntervals()
    finalTranscript = ""
    finalTranscriptionEvidence = nil
    timing = nil

    let transcription = transcription
    Task { @MainActor in
      await transcription.cancel()
    }
  }

  private func startPreparation(
    startWhenReady: Bool,
    maximumDuration: Duration = .seconds(30)
  ) {
    lifecycleTask?.cancel()
    listeningTimeoutTask?.cancel()
    invalidateReadinessRefresh()
    clearTranscriptionResult()
    endOpenIntervals()
    beginPreparationInterval()
    timing = startWhenReady ? TimingAccumulator(holdStartedAt: uptimeNanoseconds()) : nil
    phase = .preparing
    onEvent(.stateChanged(.preparing(.microphonePermission)))
    generation &+= 1
    let token = generation

    lifecycleTask = Task { [weak self] in
      guard let self else { return }
      await prepareAndMaybeStart(
        token: token,
        startWhenReady: startWhenReady,
        maximumDuration: maximumDuration
      )
    }
  }

  private func prepareAndMaybeStart(
    token: UInt64,
    startWhenReady: Bool,
    maximumDuration: Duration
  ) async {
    let initialPermission = microphonePermission.currentState
    let permissionState = await microphonePermission.requestAuthorization()
    guard generation == token else { return }
    invalidateReadinessRefresh()

    switch permissionState {
    case .authorized:
      publishReadiness(.checking, permission: permissionState)
      onEvent(.stateChanged(.preparing(.speechModel)))
    case .notDetermined:
      publishReadiness(.needsPermission, permission: permissionState)
      finishAttempt(with: .failed(.microphonePermissionRequired), token: token)
      return
    case .denied:
      publishReadiness(.denied, permission: permissionState)
      logger.notice("Microphone permission denied")
      finishAttempt(with: .failed(.microphoneDenied), token: token)
      return
    case .restricted:
      publishReadiness(.restricted, permission: permissionState)
      logger.notice("Microphone permission restricted")
      finishAttempt(with: .failed(.microphoneRestricted), token: token)
      return
    }

    let initialAssets = await speechAssets.readiness()
    guard generation == token else { return }
    let initialReadiness = Self.assetReadiness(initialAssets)
    publishReadiness(initialReadiness, permission: permissionState)

    var preparedAssetsThisAttempt = false
    let requiresAssetPreparation =
      switch initialAssets {
      case .ready:
        false
      case .unavailable, .unsupportedLocale, .downloadRequired, .downloading:
        true
      }

    if requiresAssetPreparation {
      preparedAssetsThisAttempt = true
      onEvent(.stateChanged(.preparing(.speechAssets(initialReadiness))))

      do {
        let finalState = try await speechAssets.prepare { [weak self] state in
          guard let self, generation == token else { return }
          let readiness = Self.assetReadiness(state)
          publishReadiness(readiness, permission: permissionState)
          onEvent(.stateChanged(.preparing(.speechAssets(readiness))))
        }
        guard generation == token else { return }

        let finalReadiness = Self.assetReadiness(finalState)
        publishReadiness(finalReadiness, permission: permissionState)
        guard case .ready = finalState else {
          finishAttempt(with: .failed(.speechModelNotReady), token: token)
          return
        }
      } catch {
        guard generation == token else { return }
        publishReadiness(.needsAssets, permission: permissionState)
        logger.error("Speech asset preparation failed")
        finishAttempt(with: .failed(.speechAssetPreparationFailed), token: token)
        return
      }
    }

    let permissionWasRequested = initialPermission == .notDetermined
    if !startWhenReady || permissionWasRequested || preparedAssetsThisAttempt {
      publishReadiness(.ready, permission: permissionState)
      finishAttempt(with: .readyForNextHold, token: token)
      return
    }

    guard isHeld else {
      finishAttempt(with: .releasedBeforeListening, token: token)
      return
    }

    do {
      try await transcription.prepare()
      guard generation == token, isHeld else {
        await transcription.cancel()
        if generation == token {
          finishAttempt(with: .releasedBeforeListening, token: token)
        }
        return
      }

      let events = try await transcription.start()
      guard generation == token, isHeld else {
        await transcription.cancel()
        if generation == token {
          finishAttempt(with: .releasedBeforeListening, token: token)
        }
        return
      }

      endPreparationInterval()
      beginCaptureInterval()
      timing?.listeningStartedAt = uptimeNanoseconds()
      phase = .listening("")
      onEvent(.stateChanged(.listening("")))
      logger.info("Push-to-talk started")
      consume(events, token: token)
      scheduleMaximumDuration(token: token, duration: maximumDuration)
    } catch {
      await transcription.cancel()
      guard generation == token else { return }
      logger.error("Voice capture failed to start")
      finishAttempt(with: .failed(.startFailed), token: token)
    }
  }

  private func consume(
    _ events: AsyncThrowingStream<TranscriptionEvent, any Error>,
    token: UInt64
  ) {
    transcriptionEventsTask?.cancel()
    transcriptionEventsTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await event in events {
          guard generation == token else { return }

          switch event {
          case .partial(let transcript):
            recordFirstTranscriptIfNeeded(transcript)
            if case .listening = phase {
              phase = .listening(transcript)
              onEvent(.stateChanged(.listening(transcript)))
            }
          case .final(let transcript):
            recordFirstTranscriptIfNeeded(transcript)
            finalTranscript = transcript
            switch phase {
            case .finalizing:
              phase = .finalizing(transcript)
              onEvent(.stateChanged(.finalizing(transcript)))
            case .listening:
              phase = .listening(transcript)
              onEvent(.stateChanged(.listening(transcript)))
            case .idle, .preparing, .cleaningUp:
              break
            }
          case .finalWithEvidence(let transcription):
            recordFirstTranscriptIfNeeded(transcription.primary.text)
            finalTranscript = transcription.primary.text
            finalTranscriptionEvidence = transcription
            switch phase {
            case .finalizing:
              phase = .finalizing(transcription.primary.text)
              onEvent(.stateChanged(.finalizing(transcription.primary.text)))
            case .listening:
              phase = .listening(transcription.primary.text)
              onEvent(.stateChanged(.listening(transcription.primary.text)))
            case .idle, .preparing, .cleaningUp:
              break
            }
          }
        }

        guard generation == token else { return }
        if case .listening = phase {
          await failAndCancel(.resultStreamEnded, token: token)
        }
      } catch {
        guard generation == token else { return }
        await failAndCancel(.resultStreamFailed, token: token)
      }
    }
  }

  private func scheduleMaximumDuration(token: UInt64, duration: Duration) {
    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: duration)
      } catch {
        return
      }

      guard let self, generation == token else { return }
      guard case .listening = phase else { return }
      finalizeListening(maximumDurationReached: true)
    }
  }

  private func finalize(
    eventsTask: Task<Void, Never>?
  ) async -> FinalizationOutcome {
    let (outcomes, continuation) = AsyncStream.makeStream(of: FinalizationOutcome.self)
    let transcription = transcription

    let operation = Task { @MainActor in
      do {
        try await transcription.finish()
        await eventsTask?.value
        continuation.yield(.completed)
      } catch {
        continuation.yield(.failed)
      }
    }
    let timeout = finalizationTimeout
    let watchdog = Task { @MainActor in
      do {
        try await Task.sleep(for: timeout)
      } catch {
        return
      }
      continuation.yield(.timedOut)
    }

    var iterator = outcomes.makeAsyncIterator()
    let outcome = await iterator.next() ?? .failed
    watchdog.cancel()
    continuation.finish()
    if outcome != .completed {
      operation.cancel()
    }
    return outcome
  }

  private func failAndCancel(
    _ failure: PushToTalkCaptureFailure,
    token: UInt64
  ) async {
    guard generation == token else { return }

    let recoverableTranscript = recoverableTranscript(for: failure)
    generation &+= 1
    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = nil
    isHeld = false
    phase = .cleaningUp
    if let recoverableTranscript {
      onEvent(.failedWithRecovery(failure, transcript: recoverableTranscript))
    } else {
      onEvent(.failed(failure))
    }
    endOpenIntervals()
    clearTranscriptionResult()
    timing = nil
    log(failure)

    await transcription.cancel()
    phase = .idle
  }

  private func finishAttempt(
    with event: PushToTalkCaptureEvent,
    token: UInt64
  ) {
    guard generation == token else { return }
    endPreparationInterval()
    timing = nil
    phase = .idle
    onEvent(event)
  }

  private func publishReadiness(
    _ readiness: VoiceCaptureReadiness,
    permission: MicrophonePermissionState
  ) {
    self.readiness = readiness
    onEvent(.readinessChanged(readiness, permission: permission))
  }

  private func clearTranscriptionResult() {
    transcriptionEventsTask?.cancel()
    transcriptionEventsTask = nil
    finalTranscript = ""
    finalTranscriptionEvidence = nil
  }

  private func recordFirstTranscriptIfNeeded(_ transcript: String) {
    guard
      !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      timing?.firstTranscriptAt == nil
    else { return }
    timing?.firstTranscriptAt = uptimeNanoseconds()
  }

  private func captureMetrics(completedAt: UInt64) -> VoiceCaptureMetrics? {
    guard let timing else { return nil }
    return VoiceCaptureMetrics(
      holdToListeningMilliseconds: Self.elapsedMilliseconds(
        from: timing.holdStartedAt,
        to: timing.listeningStartedAt
      ),
      listeningToFirstTranscriptMilliseconds: Self.elapsedMilliseconds(
        from: timing.listeningStartedAt,
        to: timing.firstTranscriptAt
      ),
      keyUpToFinalMilliseconds: Self.elapsedMilliseconds(
        from: timing.releasedAt,
        to: completedAt
      ),
      maximumDurationReached: timing.maximumDurationReached
    )
  }

  private func recoverableTranscript(
    for failure: PushToTalkCaptureFailure
  ) -> String? {
    switch failure {
    case .resultStreamEnded, .resultStreamFailed, .finalizationFailed,
      .finalizationTimedOut:
      break
    case .microphonePermissionRequired, .microphoneDenied, .microphoneRestricted,
      .speechModelNotReady, .speechAssetPreparationFailed, .startFailed:
      return nil
    }

    let transcript =
      switch phase {
      case .listening(let transcript), .finalizing(let transcript):
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
      case .idle, .preparing, .cleaningUp:
        ""
      }
    return transcript.isEmpty ? nil : transcript
  }

  private static func elapsedMilliseconds(from start: UInt64?, to end: UInt64?) -> UInt64? {
    guard let start, let end, end >= start else { return nil }
    return (end - start) / 1_000_000
  }

  private func invalidateReadinessRefresh() {
    readinessRefreshTask?.cancel()
    readinessRefreshTask = nil
    readinessGeneration &+= 1
  }

  private func beginPreparationInterval() {
    preparationInterval = signposter.beginInterval("VoicePreparation")
  }

  private func endPreparationInterval() {
    guard let preparationInterval else { return }
    signposter.endInterval("VoicePreparation", preparationInterval)
    self.preparationInterval = nil
  }

  private func beginCaptureInterval() {
    captureInterval = signposter.beginInterval("VoiceCapture")
  }

  private func endCaptureInterval() {
    guard let captureInterval else { return }
    signposter.endInterval("VoiceCapture", captureInterval)
    self.captureInterval = nil
  }

  private func beginFinalizationInterval() {
    finalizationInterval = signposter.beginInterval("VoiceFinalization")
  }

  private func endFinalizationInterval() {
    guard let finalizationInterval else { return }
    signposter.endInterval("VoiceFinalization", finalizationInterval)
    self.finalizationInterval = nil
  }

  private func endOpenIntervals() {
    endPreparationInterval()
    endCaptureInterval()
    endFinalizationInterval()
  }

  private func log(_ failure: PushToTalkCaptureFailure) {
    switch failure {
    case .microphonePermissionRequired:
      logger.notice("Microphone permission remained undetermined")
    case .microphoneDenied:
      logger.notice("Microphone permission denied")
    case .microphoneRestricted:
      logger.notice("Microphone permission restricted")
    case .speechModelNotReady:
      logger.error("Local speech model not ready")
    case .speechAssetPreparationFailed:
      logger.error("Speech asset preparation failed")
    case .startFailed:
      logger.error("Voice capture failed to start")
    case .resultStreamEnded:
      logger.error("Voice result stream ended while listening")
    case .resultStreamFailed:
      logger.error("Voice result stream failed")
    case .finalizationFailed:
      logger.error("Voice transcription failed")
    case .finalizationTimedOut:
      logger.error("Voice finalization timed out")
    }
  }

  private static func permissionReadiness(
    _ state: MicrophonePermissionState
  ) -> VoiceCaptureReadiness {
    switch state {
    case .notDetermined:
      .needsPermission
    case .authorized:
      .checking
    case .denied:
      .denied
    case .restricted:
      .restricted
    }
  }

  private static func assetReadiness(
    _ state: SpeechAssetPreparationState
  ) -> VoiceCaptureReadiness {
    switch state {
    case .unavailable, .unsupportedLocale:
      .unavailable
    case .downloadRequired:
      .needsAssets
    case .downloading(_, let progress):
      .preparing(progress: progress)
    case .ready:
      .ready
    }
  }
}
