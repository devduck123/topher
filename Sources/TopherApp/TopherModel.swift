import AppKit
import Foundation
import KeyboardShortcuts
import OSLog
import TopherCore

@MainActor
final class TopherModel: ObservableObject {
  enum Phase: Equatable {
    case idle
    case preparingVoice
    case listening(String)
    case finalizingVoice
    case transcribing
    case executing
    case success(String)
    case failure(String)

    var title: String {
      switch self {
      case .idle:
        "Ready"
      case .preparingVoice:
        "Preparing voice…"
      case .listening:
        "Listening…"
      case .finalizingVoice:
        "Finalizing…"
      case .transcribing:
        "Processing…"
      case .executing:
        "Executing…"
      case .success:
        "Done"
      case .failure:
        "Couldn’t complete command"
      }
    }

    var detail: String {
      switch self {
      case .idle:
        "Hold your shortcut, speak, then release to run the command."
      case .preparingVoice:
        "Checking microphone access and the local speech model."
      case .listening(let transcript):
        transcript.isEmpty ? "Release the shortcut when you’re done." : transcript
      case .finalizingVoice:
        "Finishing the on-device transcript."
      case .transcribing:
        "Resolving the manual transcript."
      case .executing:
        "Running an approved native capability."
      case .success(let message), .failure(let message):
        message
      }
    }

    var symbolName: String {
      switch self {
      case .idle:
        "sparkles"
      case .preparingVoice:
        "arrow.trianglehead.2.clockwise.rotate.90"
      case .listening:
        "waveform"
      case .finalizingVoice, .transcribing:
        "text.bubble"
      case .executing:
        "gearshape.2"
      case .success:
        "checkmark.circle"
      case .failure:
        "exclamationmark.triangle"
      }
    }

    var isListening: Bool {
      if case .listening = self { return true }
      return false
    }

    var isBusy: Bool {
      switch self {
      case .preparingVoice, .listening, .finalizingVoice, .transcribing, .executing:
        true
      case .idle, .success, .failure:
        false
      }
    }
  }

  enum VoiceReadiness: Equatable {
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

  enum VoiceFeedback: Equatable {
    case hidden
    case preparing(String)
    case listening(String)
    case finalizing(String)
    case executing(String)
    case success(String)
    case failure(String)
  }

  @Published var manualTranscript = "Open Safari."
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var voiceReadiness: VoiceReadiness
  @Published private(set) var voiceFeedback: VoiceFeedback = .hidden

  private let resolver: CommandResolver
  private let policy: CommandPolicy
  private let applicationOpener: ApplicationOpenCapability
  private let webOpener: WebOpenCapability
  private let microphonePermission: MicrophonePermissionClient
  private let speechAssets: SpeechAssetPreparationClient
  private let voiceTranscription: VoiceTranscriptionClient
  private let listeningTimeout: Duration
  private let finalizationTimeout: Duration
  private let voiceFeedbackResultDuration: Duration
  private let logger = Logger(subsystem: "dev.topher.app", category: "control-path")

  private var shortcutEventsTask: Task<Void, Never>?
  private var voiceLifecycleTask: Task<Void, Never>?
  private var voiceEventsTask: Task<Void, Never>?
  private var listeningTimeoutTask: Task<Void, Never>?
  private var voiceReadinessRefreshTask: Task<Void, Never>?
  private var voiceFeedbackDismissalTask: Task<Void, Never>?
  private var isPushToTalkHeld = false
  private var isVoiceCleanupPending = false
  private var voiceGeneration: UInt64 = 0
  private var voiceReadinessGeneration: UInt64 = 0
  private var voiceFeedbackGeneration: UInt64 = 0
  private var finalVoiceTranscript = ""
  private var activePermissionFailure: MicrophonePermissionState?

  init(
    resolver: CommandResolver = .init(),
    policy: CommandPolicy = .init(),
    applicationOpener: ApplicationOpenCapability? = nil,
    webOpener: WebOpenCapability? = nil,
    microphonePermission: MicrophonePermissionClient? = nil,
    speechAssets: SpeechAssetPreparationClient? = nil,
    voiceTranscription: VoiceTranscriptionClient? = nil,
    listeningTimeout: Duration = .seconds(30),
    finalizationTimeout: Duration = .seconds(8),
    voiceFeedbackResultDuration: Duration = .seconds(3),
    listenForShortcutEvents: Bool = true
  ) {
    self.resolver = resolver
    self.policy = policy
    self.applicationOpener = applicationOpener ?? ApplicationOpenCapability()
    self.webOpener = webOpener ?? WebOpenCapability()
    self.microphonePermission = microphonePermission ?? MicrophonePermissionClient()
    self.speechAssets = speechAssets ?? SpeechAssetPreparationClient()
    self.voiceTranscription = voiceTranscription ?? .live()
    self.listeningTimeout = listeningTimeout
    self.finalizationTimeout = finalizationTimeout
    self.voiceFeedbackResultDuration = voiceFeedbackResultDuration
    voiceReadiness = Self.permissionReadiness(self.microphonePermission.currentState)

    if listenForShortcutEvents {
      shortcutEventsTask = Task { [weak self] in
        for await event in KeyboardShortcuts.events(for: .pushToTalk) {
          guard let self else { return }

          switch event {
          case .keyDown:
            beginPushToTalk()
          case .keyUp:
            endPushToTalk()
          }
        }
      }
    }

    if self.microphonePermission.currentState == .authorized {
      refreshVoiceReadiness()
    }
  }

  deinit {
    shortcutEventsTask?.cancel()
    voiceLifecycleTask?.cancel()
    voiceEventsTask?.cancel()
    listeningTimeoutTask?.cancel()
    voiceReadinessRefreshTask?.cancel()
    voiceFeedbackDismissalTask?.cancel()
  }

  func refreshVoiceReadiness() {
    invalidateVoiceReadinessRefresh()
    let token = voiceReadinessGeneration
    let permissionState = microphonePermission.currentState
    guard permissionState == .authorized else {
      voiceReadiness = Self.permissionReadiness(permissionState)
      reconcilePhase(with: permissionState)
      return
    }

    reconcilePhase(with: permissionState)
    voiceReadiness = .checking
    let speechAssets = speechAssets
    voiceReadinessRefreshTask = Task { [weak self] in
      let assetState = await speechAssets.readiness()
      guard
        let self,
        !Task.isCancelled,
        voiceReadinessGeneration == token,
        microphonePermission.currentState == .authorized
      else { return }
      voiceReadiness = Self.assetReadiness(assetState)
    }
  }

  func prepareVoiceInput() {
    guard !phase.isBusy, !isVoiceCleanupPending else { return }
    isPushToTalkHeld = false
    hideVoiceFeedback()
    startVoicePreparation(startWhenReady: false, presentsGlobalFeedback: false)
  }

  func beginPushToTalk() {
    guard !phase.isBusy, !isVoiceCleanupPending, !isPushToTalkHeld else { return }
    isPushToTalkHeld = true
    startVoicePreparation(startWhenReady: true, presentsGlobalFeedback: true)
  }

  func endPushToTalk() {
    isPushToTalkHeld = false
    guard phase.isListening else { return }

    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = nil
    phase = .finalizingVoice
    let visibleTranscript =
      if case .listening(let transcript) = voiceFeedback {
        transcript
      } else {
        finalVoiceTranscript
      }
    presentVoiceFeedback(.finalizing(visibleTranscript))
    logger.info("Push-to-talk ended")

    let token = voiceGeneration
    voiceLifecycleTask = Task { [weak self] in
      guard let self else { return }

      let outcome = await finalizeVoice(eventsTask: voiceEventsTask)
      guard voiceGeneration == token else { return }

      switch outcome {
      case .completed:
        let transcript = finalVoiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        clearVoiceResultState()
        guard !transcript.isEmpty else {
          let message = "I didn’t hear a command. Hold the shortcut and try again."
          phase = .failure(message)
          presentVoiceResult(.failure(message))
          logger.notice("Voice capture completed without speech")
          return
        }

        processTranscript(transcript, source: .voice)
      case .failed:
        await failAndCancelVoice(
          token: token,
          message: "Voice transcription failed. Try the shortcut again.",
          logEvent: .transcriptionFailed
        )
      case .timedOut:
        await failAndCancelVoice(
          token: token,
          message: "Voice finalization timed out. Try the shortcut again.",
          logEvent: .finalizationTimedOut
        )
      }
    }
  }

  func runManually() {
    guard !phase.isBusy, !isVoiceCleanupPending else { return }
    activePermissionFailure = nil
    hideVoiceFeedback()
    phase = .transcribing
    let transcript = manualTranscript
    Task { [weak self] in
      await Task.yield()
      self?.processTranscript(transcript, source: .manual)
    }
  }

  func openMicrophoneSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
      )
    else { return }

    NSWorkspace.shared.open(url)
  }

  private func startVoicePreparation(
    startWhenReady: Bool,
    presentsGlobalFeedback: Bool
  ) {
    voiceLifecycleTask?.cancel()
    listeningTimeoutTask?.cancel()
    invalidateVoiceReadinessRefresh()
    clearVoiceResultState()
    activePermissionFailure = nil
    phase = .preparingVoice
    if presentsGlobalFeedback {
      presentVoiceFeedback(.preparing("Checking microphone access…"))
    }
    voiceGeneration &+= 1
    let token = voiceGeneration

    voiceLifecycleTask = Task { [weak self] in
      guard let self else { return }
      await prepareAndMaybeStartVoice(
        token: token,
        startWhenReady: startWhenReady,
        presentsGlobalFeedback: presentsGlobalFeedback
      )
    }
  }

  private func prepareAndMaybeStartVoice(
    token: UInt64,
    startWhenReady: Bool,
    presentsGlobalFeedback: Bool
  ) async {
    let initialPermission = microphonePermission.currentState
    let permissionState = await microphonePermission.requestAuthorization()
    guard voiceGeneration == token else { return }
    invalidateVoiceReadinessRefresh()

    switch permissionState {
    case .authorized:
      voiceReadiness = .checking
      if presentsGlobalFeedback {
        presentVoiceFeedback(.preparing("Checking the local speech model…"))
      }
    case .notDetermined:
      activePermissionFailure = .notDetermined
      voiceReadiness = .needsPermission
      let message = "Microphone access is required for push-to-talk."
      phase = .failure(message)
      if presentsGlobalFeedback {
        presentVoiceResult(.failure(message))
      }
      return
    case .denied:
      activePermissionFailure = .denied
      voiceReadiness = .denied
      let message = "Microphone denied. Open Topher’s menu to open Microphone Settings."
      phase = .failure(message)
      if presentsGlobalFeedback {
        presentVoiceResult(.failure(message))
      }
      logger.notice("Microphone permission denied")
      return
    case .restricted:
      activePermissionFailure = .restricted
      voiceReadiness = .restricted
      let message = "Microphone access is restricted by this Mac’s administrator or policy."
      phase = .failure(message)
      if presentsGlobalFeedback {
        presentVoiceResult(.failure(message))
      }
      logger.notice("Microphone permission restricted")
      return
    }

    let initialAssets = await speechAssets.readiness()
    guard voiceGeneration == token else { return }
    voiceReadiness = Self.assetReadiness(initialAssets)

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
      do {
        let finalState = try await speechAssets.prepare { [weak self] state in
          guard let self, voiceGeneration == token else { return }
          voiceReadiness = Self.assetReadiness(state)
          if presentsGlobalFeedback {
            presentVoiceFeedback(.preparing(voiceReadiness.title))
          }
        }
        guard voiceGeneration == token else { return }
        voiceReadiness = Self.assetReadiness(finalState)
        guard case .ready = finalState else {
          let message = "The local English speech model isn’t ready yet."
          phase = .failure(message)
          if presentsGlobalFeedback {
            presentVoiceResult(.failure(message))
          }
          return
        }
      } catch {
        guard voiceGeneration == token else { return }
        voiceReadiness = .needsAssets
        let message = "Couldn’t prepare the local speech model. Try again."
        phase = .failure(message)
        if presentsGlobalFeedback {
          presentVoiceResult(.failure(message))
        }
        logger.error("Speech asset preparation failed")
        return
      }
    }

    let permissionWasRequested = initialPermission == .notDetermined
    if !startWhenReady || permissionWasRequested || preparedAssetsThisAttempt {
      voiceReadiness = .ready
      let message = "Voice input is ready. Hold your shortcut again to speak."
      phase = .success(message)
      if presentsGlobalFeedback {
        presentVoiceResult(.success(message))
      }
      return
    }

    guard isPushToTalkHeld else {
      let message = "Released before listening started. Hold the shortcut again."
      phase = .success(message)
      if presentsGlobalFeedback {
        presentVoiceResult(.failure(message))
      }
      return
    }

    do {
      try await voiceTranscription.prepare()
      guard voiceGeneration == token, isPushToTalkHeld else {
        await voiceTranscription.cancel()
        if voiceGeneration == token {
          let message = "Released before listening started. Hold the shortcut again."
          phase = .success(message)
          if presentsGlobalFeedback {
            presentVoiceResult(.failure(message))
          }
        }
        return
      }

      let events = try await voiceTranscription.start()
      guard voiceGeneration == token, isPushToTalkHeld else {
        await voiceTranscription.cancel()
        if voiceGeneration == token {
          let message = "Released before listening started. Hold the shortcut again."
          phase = .success(message)
          if presentsGlobalFeedback {
            presentVoiceResult(.failure(message))
          }
        }
        return
      }

      phase = .listening("")
      presentVoiceFeedback(.listening(""))
      logger.info("Push-to-talk started")
      consumeVoiceEvents(events, token: token)
      scheduleListeningTimeout(token: token)
    } catch {
      await voiceTranscription.cancel()
      guard voiceGeneration == token else { return }
      let message = "Couldn’t start voice input. Try the shortcut again."
      phase = .failure(message)
      if presentsGlobalFeedback {
        presentVoiceResult(.failure(message))
      }
      logger.error("Voice capture failed to start")
    }
  }

  private func consumeVoiceEvents(
    _ events: AsyncThrowingStream<TranscriptionEvent, any Error>,
    token: UInt64
  ) {
    voiceEventsTask?.cancel()
    voiceEventsTask = Task { [weak self] in
      guard let self else { return }

      do {
        for try await event in events {
          guard voiceGeneration == token else { return }
          switch event {
          case .partial(let transcript):
            if phase.isListening {
              phase = .listening(transcript)
              presentVoiceFeedback(.listening(transcript))
            }
          case .final(let transcript):
            finalVoiceTranscript = transcript
            if phase == .finalizingVoice {
              presentVoiceFeedback(.finalizing(transcript))
            } else if phase.isListening {
              phase = .listening(transcript)
              presentVoiceFeedback(.listening(transcript))
            }
          }
        }

        guard voiceGeneration == token, phase.isListening else { return }
        await failAndCancelVoice(
          token: token,
          message: "Voice input stopped unexpectedly. Try the shortcut again.",
          logEvent: .resultStreamEnded
        )
      } catch {
        guard voiceGeneration == token else { return }
        await failAndCancelVoice(
          token: token,
          message: "Voice transcription failed. Try the shortcut again.",
          logEvent: .resultStreamFailed
        )
      }
    }
  }

  private func scheduleListeningTimeout(token: UInt64) {
    listeningTimeoutTask?.cancel()
    let timeout = listeningTimeout
    listeningTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: timeout)
      } catch {
        return
      }

      guard let self, voiceGeneration == token, phase.isListening else { return }
      await failAndCancelVoice(
        token: token,
        message: "Listening timed out. Try the shortcut again.",
        logEvent: .listeningTimedOut
      )
    }
  }

  private func finalizeVoice(
    eventsTask: Task<Void, Never>?
  ) async -> VoiceFinalizationOutcome {
    let (outcomes, continuation) = AsyncStream.makeStream(of: VoiceFinalizationOutcome.self)
    let transcription = voiceTranscription

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

  private func failAndCancelVoice(
    token: UInt64,
    message: String,
    logEvent: VoiceFailureLogEvent
  ) async {
    guard voiceGeneration == token else { return }

    voiceGeneration &+= 1
    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = nil
    isPushToTalkHeld = false
    isVoiceCleanupPending = true
    activePermissionFailure = nil
    phase = .failure(message)
    presentVoiceResult(.failure(message))
    clearVoiceResultState()
    switch logEvent {
    case .transcriptionFailed:
      logger.error("Voice transcription failed")
    case .finalizationTimedOut:
      logger.error("Voice finalization timed out")
    case .resultStreamEnded:
      logger.error("Voice result stream ended while listening")
    case .resultStreamFailed:
      logger.error("Voice result stream failed")
    case .listeningTimedOut:
      logger.notice("Push-to-talk timed out without a key-up event")
    }

    await voiceTranscription.cancel()
    isVoiceCleanupPending = false
  }

  private func processTranscript(_ transcript: String, source: TranscriptSource) {
    activePermissionFailure = nil
    let command = resolver.resolve(transcript)

    guard policy.evaluate(command) == .allowed else {
      let message = "Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”"
      phase = .failure(message)
      if source == .voice {
        presentVoiceResult(.failure(message))
      }
      logger.notice("Rejected an unsupported command")
      return
    }

    if source == .voice {
      presentVoiceFeedback(.executing(transcript))
    }

    switch command {
    case .openApplication(let target):
      phase = .executing
      logger.info(
        "Executing registered capability: \(ApplicationOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        let outcome = await applicationOpener.execute(target)
        apply(outcome, source: source)
      }
    case .openWebsite(let target):
      phase = .executing
      logger.info(
        "Executing registered capability: \(WebOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        await Task.yield()
        let outcome = await webOpener.execute(target)
        apply(outcome, source: source)
      }
    case .searchWeb(let provider, let query):
      phase = .executing
      logger.info(
        "Executing registered capability: \(WebOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        await Task.yield()
        let outcome = await webOpener.execute(provider: provider, query: query)
        apply(outcome, source: source)
      }
    case .unsupported:
      let message = "Unsupported command."
      phase = .failure(message)
      if source == .voice {
        presentVoiceResult(.failure(message))
      }
    }
  }

  private func apply(_ outcome: ActionOutcome, source: TranscriptSource) {
    switch outcome {
    case .succeeded(let message):
      phase = .success(message)
      if source == .voice {
        presentVoiceResult(.success(message))
      }
      logger.info("Capability completed")
    case .failed(let message):
      phase = .failure(message)
      if source == .voice {
        presentVoiceResult(.failure(message))
      }
      logger.error("Capability failed")
    }
  }

  private func presentVoiceResult(_ feedback: VoiceFeedback) {
    presentVoiceFeedback(feedback, dismissAfter: voiceFeedbackResultDuration)
  }

  private func presentVoiceFeedback(
    _ feedback: VoiceFeedback,
    dismissAfter duration: Duration? = nil
  ) {
    voiceFeedbackDismissalTask?.cancel()
    voiceFeedbackGeneration &+= 1
    let token = voiceFeedbackGeneration
    voiceFeedback = feedback

    guard let duration else {
      voiceFeedbackDismissalTask = nil
      return
    }

    voiceFeedbackDismissalTask = Task { [weak self] in
      do {
        try await Task.sleep(for: duration)
      } catch {
        return
      }

      guard let self, voiceFeedbackGeneration == token else { return }
      voiceFeedback = .hidden
      voiceFeedbackDismissalTask = nil
    }
  }

  private func hideVoiceFeedback() {
    voiceFeedbackDismissalTask?.cancel()
    voiceFeedbackDismissalTask = nil
    voiceFeedbackGeneration &+= 1
    voiceFeedback = .hidden
  }

  private func invalidateVoiceReadinessRefresh() {
    voiceReadinessRefreshTask?.cancel()
    voiceReadinessRefreshTask = nil
    voiceReadinessGeneration &+= 1
  }

  private func reconcilePhase(with permissionState: MicrophonePermissionState) {
    guard !phase.isBusy else { return }

    switch permissionState {
    case .authorized:
      guard activePermissionFailure != nil else { return }
      activePermissionFailure = nil
      hideVoiceFeedback()
      phase = .idle
    case .denied:
      activePermissionFailure = .denied
      phase = .failure(
        "Allow Topher in System Settings → Privacy & Security → Microphone."
      )
    case .restricted:
      activePermissionFailure = .restricted
      phase = .failure("Microphone access is restricted by this Mac’s administrator or policy.")
    case .notDetermined:
      if activePermissionFailure != nil {
        activePermissionFailure = nil
        phase = .idle
      }
    }
  }

  private func clearVoiceResultState() {
    voiceEventsTask?.cancel()
    voiceEventsTask = nil
    finalVoiceTranscript = ""
  }

  private static func permissionReadiness(
    _ state: MicrophonePermissionState
  ) -> VoiceReadiness {
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
  ) -> VoiceReadiness {
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

private enum TranscriptSource: Equatable, Sendable {
  case manual
  case voice
}

private enum VoiceFinalizationOutcome: Equatable, Sendable {
  case completed
  case failed
  case timedOut
}

private enum VoiceFailureLogEvent {
  case transcriptionFailed
  case finalizationTimedOut
  case resultStreamEnded
  case resultStreamFailed
  case listeningTimedOut
}
