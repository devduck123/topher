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
      case .denied, .restricted:
        true
      case .checking, .needsPermission, .needsAssets, .preparing, .ready, .unavailable:
        false
      }
    }
  }

  @Published var manualTranscript = "Open Safari."
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var voiceReadiness: VoiceReadiness

  private let resolver: CommandResolver
  private let policy: CommandPolicy
  private let applicationOpener: ApplicationOpenCapability
  private let webOpener: WebOpenCapability
  private let microphonePermission: MicrophonePermissionClient
  private let speechAssets: SpeechAssetPreparationClient
  private let voiceTranscription: VoiceTranscriptionClient
  private let listeningTimeout: Duration
  private let finalizationTimeout: Duration
  private let logger = Logger(subsystem: "dev.topher.app", category: "control-path")

  private var shortcutEventsTask: Task<Void, Never>?
  private var voiceLifecycleTask: Task<Void, Never>?
  private var voiceEventsTask: Task<Void, Never>?
  private var listeningTimeoutTask: Task<Void, Never>?
  private var isPushToTalkHeld = false
  private var isVoiceCleanupPending = false
  private var voiceGeneration: UInt64 = 0
  private var finalVoiceTranscript = ""

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
  }

  func refreshVoiceReadiness() {
    let permissionState = microphonePermission.currentState
    guard permissionState == .authorized else {
      voiceReadiness = Self.permissionReadiness(permissionState)
      return
    }

    voiceReadiness = .checking
    Task { [weak self] in
      guard let self else { return }
      let assetState = await speechAssets.readiness()
      voiceReadiness = Self.assetReadiness(assetState)
    }
  }

  func prepareVoiceInput() {
    guard !phase.isBusy, !isVoiceCleanupPending else { return }
    isPushToTalkHeld = false
    startVoicePreparation(startWhenReady: false)
  }

  func beginPushToTalk() {
    guard !phase.isBusy, !isVoiceCleanupPending, !isPushToTalkHeld else { return }
    isPushToTalkHeld = true
    startVoicePreparation(startWhenReady: true)
  }

  func endPushToTalk() {
    isPushToTalkHeld = false
    guard phase.isListening else { return }

    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = nil
    phase = .finalizingVoice
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
          phase = .failure("I didn’t hear a command. Hold the shortcut and try again.")
          logger.notice("Voice capture completed without speech")
          return
        }

        processTranscript(transcript)
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
    phase = .transcribing
    let transcript = manualTranscript
    Task { [weak self] in
      await Task.yield()
      self?.processTranscript(transcript)
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

  private func startVoicePreparation(startWhenReady: Bool) {
    voiceLifecycleTask?.cancel()
    listeningTimeoutTask?.cancel()
    clearVoiceResultState()
    phase = .preparingVoice
    voiceGeneration &+= 1
    let token = voiceGeneration

    voiceLifecycleTask = Task { [weak self] in
      guard let self else { return }
      await prepareAndMaybeStartVoice(token: token, startWhenReady: startWhenReady)
    }
  }

  private func prepareAndMaybeStartVoice(token: UInt64, startWhenReady: Bool) async {
    let initialPermission = microphonePermission.currentState
    let permissionState = await microphonePermission.requestAuthorization()
    guard voiceGeneration == token else { return }

    switch permissionState {
    case .authorized:
      voiceReadiness = .checking
    case .notDetermined:
      voiceReadiness = .needsPermission
      phase = .failure("Microphone access is required for push-to-talk.")
      return
    case .denied:
      voiceReadiness = .denied
      phase = .failure(
        "Allow Topher in System Settings → Privacy & Security → Microphone."
      )
      logger.notice("Microphone permission denied")
      return
    case .restricted:
      voiceReadiness = .restricted
      phase = .failure("Microphone access is restricted on this Mac.")
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
        }
        guard voiceGeneration == token else { return }
        voiceReadiness = Self.assetReadiness(finalState)
        guard case .ready = finalState else {
          phase = .failure("The local English speech model isn’t ready yet.")
          return
        }
      } catch {
        guard voiceGeneration == token else { return }
        voiceReadiness = .needsAssets
        phase = .failure("Couldn’t prepare the local speech model. Try again.")
        logger.error("Speech asset preparation failed")
        return
      }
    }

    let permissionWasRequested = initialPermission == .notDetermined
    if !startWhenReady || permissionWasRequested || preparedAssetsThisAttempt {
      voiceReadiness = .ready
      phase = .success("Voice input is ready. Hold your shortcut again to speak.")
      return
    }

    guard isPushToTalkHeld else {
      phase = .success("Released before listening started. Hold the shortcut again.")
      return
    }

    do {
      try await voiceTranscription.prepare()
      guard voiceGeneration == token, isPushToTalkHeld else {
        await voiceTranscription.cancel()
        if voiceGeneration == token {
          phase = .success("Released before listening started. Hold the shortcut again.")
        }
        return
      }

      let events = try await voiceTranscription.start()
      guard voiceGeneration == token, isPushToTalkHeld else {
        await voiceTranscription.cancel()
        if voiceGeneration == token {
          phase = .success("Released before listening started. Hold the shortcut again.")
        }
        return
      }

      phase = .listening("")
      logger.info("Push-to-talk started")
      consumeVoiceEvents(events, token: token)
      scheduleListeningTimeout(token: token)
    } catch {
      await voiceTranscription.cancel()
      guard voiceGeneration == token else { return }
      phase = .failure("Couldn’t start voice input. Try the shortcut again.")
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
            }
          case .final(let transcript):
            finalVoiceTranscript = transcript
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
    phase = .failure(message)
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

  private func processTranscript(_ transcript: String) {
    let command = resolver.resolve(transcript)

    guard policy.evaluate(command) == .allowed else {
      phase = .failure(
        "Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”"
      )
      logger.notice("Rejected an unsupported command")
      return
    }

    switch command {
    case .openApplication(let target):
      phase = .executing
      logger.info(
        "Executing registered capability: \(ApplicationOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        let outcome = await applicationOpener.execute(target)
        apply(outcome)
      }
    case .openWebsite(let target):
      phase = .executing
      logger.info(
        "Executing registered capability: \(WebOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        await Task.yield()
        let outcome = await webOpener.execute(target)
        apply(outcome)
      }
    case .searchWeb(let provider, let query):
      phase = .executing
      logger.info(
        "Executing registered capability: \(WebOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        await Task.yield()
        let outcome = await webOpener.execute(provider: provider, query: query)
        apply(outcome)
      }
    case .unsupported:
      phase = .failure("Unsupported command.")
    }
  }

  private func apply(_ outcome: ActionOutcome) {
    switch outcome {
    case .succeeded(let message):
      phase = .success(message)
      logger.info("Capability completed")
    case .failed(let message):
      phase = .failure(message)
      logger.error("Capability failed")
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
