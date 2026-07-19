import AppKit
import Foundation
import KeyboardShortcuts
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

  typealias VoiceReadiness = VoiceCaptureReadiness

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

  private let commandProcessor: AssistantCommandProcessor
  private let captureController: PushToTalkCaptureController
  private let developerDiagnostics: DeveloperDiagnosticsController?
  private let voiceFeedbackResultDuration: Duration

  private var shortcutEventsTask: Task<Void, Never>?
  private var commandExecutionTask: Task<Void, Never>?
  private var voiceFeedbackDismissalTask: Task<Void, Never>?
  private var voiceFeedbackGeneration: UInt64 = 0
  private var activePermissionFailure: MicrophonePermissionState?
  private var activeVoicePresentation: VoicePresentation?

  init(
    resolver: CommandResolver = .init(),
    policy: CommandPolicy = .init(),
    applicationOpener: ApplicationOpenCapability? = nil,
    chromeContext: ChromeContextCapabilities? = nil,
    webOpener: WebOpenCapability? = nil,
    microphonePermission: MicrophonePermissionClient? = nil,
    speechAssets: SpeechAssetPreparationClient? = nil,
    voiceTranscription: VoiceTranscriptionClient? = nil,
    listeningTimeout: Duration = .seconds(30),
    finalizationTimeout: Duration = .seconds(8),
    voiceFeedbackResultDuration: Duration = .seconds(3),
    developerDiagnostics: DeveloperDiagnosticsController? = nil,
    vocabularyProvider: @escaping @MainActor () -> TranscriptVocabulary = {
      .developerDefaults
    },
    listenForShortcutEvents: Bool = true
  ) {
    let permission = microphonePermission ?? MicrophonePermissionClient()
    let captureController = PushToTalkCaptureController(
      microphonePermission: permission,
      speechAssets: speechAssets ?? SpeechAssetPreparationClient(),
      transcription: voiceTranscription ?? .live(),
      listeningTimeout: listeningTimeout,
      finalizationTimeout: finalizationTimeout
    )

    commandProcessor = AssistantCommandProcessor(
      resolver: resolver,
      vocabularyProvider: vocabularyProvider,
      policy: policy,
      applicationOpener: applicationOpener,
      chromeContext: chromeContext,
      webOpener: webOpener
    )
    self.captureController = captureController
    self.developerDiagnostics = developerDiagnostics
    self.voiceFeedbackResultDuration = voiceFeedbackResultDuration
    voiceReadiness = captureController.readiness

    captureController.onEvent = { [weak self] event in
      self?.handleCaptureEvent(event)
    }

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

    if permission.currentState == .authorized {
      captureController.refreshReadiness()
    }
  }

  deinit {
    let captureController = captureController
    Task { @MainActor in
      captureController.shutdown()
    }
    shortcutEventsTask?.cancel()
    commandExecutionTask?.cancel()
    voiceFeedbackDismissalTask?.cancel()
  }

  func refreshVoiceReadiness() {
    captureController.refreshReadiness()
  }

  func prepareVoiceInput() {
    guard canStartNewInteraction else { return }

    let previousPermissionFailure = activePermissionFailure
    activePermissionFailure = nil
    activeVoicePresentation = .menuPreparation
    hideVoiceFeedback()
    if !captureController.prepareForUse() {
      activePermissionFailure = previousPermissionFailure
      activeVoicePresentation = nil
    }
  }

  func beginPushToTalk() {
    guard canStartNewInteraction else { return }

    let previousPermissionFailure = activePermissionFailure
    activePermissionFailure = nil
    activeVoicePresentation = .globalShortcut
    if !captureController.beginHold() {
      activePermissionFailure = previousPermissionFailure
      activeVoicePresentation = nil
    }
  }

  func endPushToTalk() {
    // Always forward key-up. During first-run preparation this clears the
    // controller's physical-held gate even though listening has not begun.
    captureController.endHold()
  }

  func runManually() {
    guard canStartNewInteraction else { return }

    activeVoicePresentation = nil
    activePermissionFailure = nil
    hideVoiceFeedback()
    phase = .transcribing
    startCommandProcessing(manualTranscript, source: .manual, yieldBeforeProcessing: true)
  }

  func openMicrophoneSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
      )
    else { return }

    NSWorkspace.shared.open(url)
  }

  private var canStartNewInteraction: Bool {
    !phase.isBusy && !captureController.isBusy && commandExecutionTask == nil
  }

  private func handleCaptureEvent(_ event: PushToTalkCaptureEvent) {
    switch event {
    case .readinessChanged(let readiness, let permission):
      voiceReadiness = readiness
      reconcilePhase(with: permission)

    case .stateChanged(let state):
      handleCaptureState(state)

    case .readyForNextHold:
      let message = "Voice input is ready. Hold your shortcut again to speak."
      let presentsGlobally = activeVoicePresentation == .globalShortcut
      activeVoicePresentation = nil
      phase = .success(message)
      if presentsGlobally {
        presentVoiceResult(.success(message))
      }

    case .releasedBeforeListening:
      let message = "Released before listening started. Hold the shortcut again."
      let presentsGlobally = activeVoicePresentation == .globalShortcut
      activeVoicePresentation = nil
      phase = .success(message)
      if presentsGlobally {
        presentVoiceResult(.failure(message))
      }

    case .completed(let rawTranscript):
      let presentsGlobally = activeVoicePresentation == .globalShortcut
      activeVoicePresentation = nil
      let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !transcript.isEmpty else {
        recordNoUsableSpeechIfEnabled()
        let message = "I didn’t hear a command. Hold the shortcut and try again."
        phase = .failure(message)
        if presentsGlobally {
          presentVoiceResult(.failure(message))
        }
        return
      }

      startCommandProcessing(transcript, source: .voice)

    case .completedWithEvidence(let transcription):
      let presentsGlobally = activeVoicePresentation == .globalShortcut
      activeVoicePresentation = nil
      let transcript = transcription.primary.text.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !transcript.isEmpty else {
        recordNoUsableSpeechIfEnabled(captureMetrics: transcription.captureMetrics)
        let message = "I didn’t hear a command. Hold the shortcut and try again."
        phase = .failure(message)
        if presentsGlobally {
          presentVoiceResult(.failure(message))
        }
        return
      }

      startCommandProcessing(
        transcript,
        source: .voice,
        alternatives: transcription.alternatives,
        confidence: transcription.primary.confidence,
        captureMetrics: transcription.captureMetrics
      )

    case .failed(let failure):
      applyCaptureFailure(failure)
    }
  }

  private func recordNoUsableSpeechIfEnabled(captureMetrics: VoiceCaptureMetrics? = nil) {
    guard let developerDiagnostics else { return }

    Task {
      guard let token = await developerDiagnostics.beginTrace() else { return }
      await developerDiagnostics.record(
        transcript: "",
        captureMetrics: captureMetrics,
        source: .voice,
        trace: AssistantCommandTrace(
          outcome: .noUsableSpeech,
          commandKind: nil,
          capabilityIdentifier: nil
        ),
        processingDurationMilliseconds: 0,
        using: token
      )
    }
  }

  private func handleCaptureState(_ state: PushToTalkCaptureState) {
    let presentsGlobally = activeVoicePresentation == .globalShortcut

    switch state {
    case .preparing(let preparation):
      phase = .preparingVoice
      guard presentsGlobally else { return }

      let detail =
        switch preparation {
        case .microphonePermission:
          "Checking microphone access…"
        case .speechModel:
          "Checking the local speech model…"
        case .speechAssets(let readiness):
          readiness.title
        }
      presentVoiceFeedback(.preparing(detail))

    case .listening(let transcript):
      phase = .listening(transcript)
      if presentsGlobally {
        presentVoiceFeedback(.listening(transcript))
      }

    case .finalizing(let transcript):
      phase = .finalizingVoice
      if presentsGlobally {
        presentVoiceFeedback(.finalizing(transcript))
      }
    }
  }

  private func applyCaptureFailure(_ failure: PushToTalkCaptureFailure) {
    let message: String
    switch failure {
    case .microphonePermissionRequired:
      activePermissionFailure = .notDetermined
      message = "Microphone access is required for push-to-talk."
    case .microphoneDenied:
      activePermissionFailure = .denied
      message = "Microphone denied. Open Topher’s menu to open Microphone Settings."
    case .microphoneRestricted:
      activePermissionFailure = .restricted
      message = "Microphone access is restricted by this Mac’s administrator or policy."
    case .speechModelNotReady:
      activePermissionFailure = nil
      message = "The local English speech model isn’t ready yet."
    case .speechAssetPreparationFailed:
      activePermissionFailure = nil
      message = "Couldn’t prepare the local speech model. Try again."
    case .startFailed:
      activePermissionFailure = nil
      message = "Couldn’t start voice input. Try the shortcut again."
    case .resultStreamEnded:
      activePermissionFailure = nil
      message = "Voice input stopped unexpectedly. Try the shortcut again."
    case .resultStreamFailed, .finalizationFailed:
      activePermissionFailure = nil
      message = "Voice transcription failed. Try the shortcut again."
    case .listeningTimedOut:
      activePermissionFailure = nil
      message = "Listening timed out. Try the shortcut again."
    case .finalizationTimedOut:
      activePermissionFailure = nil
      message = "Voice finalization timed out. Try the shortcut again."
    }

    let presentsGlobally = activeVoicePresentation == .globalShortcut
    activeVoicePresentation = nil
    phase = .failure(message)
    if presentsGlobally {
      presentVoiceResult(.failure(message))
    }
  }

  private func startCommandProcessing(
    _ transcript: String,
    source: DeveloperTranscriptSource,
    alternatives: [TranscriptHypothesis] = [],
    confidence: Double? = nil,
    captureMetrics: VoiceCaptureMetrics? = nil,
    yieldBeforeProcessing: Bool = false
  ) {
    precondition(commandExecutionTask == nil)
    activePermissionFailure = nil
    let processor = commandProcessor
    let diagnostics = developerDiagnostics

    commandExecutionTask = Task { [weak self] in
      if yieldBeforeProcessing {
        await Task.yield()
      }
      guard !Task.isCancelled else { return }

      let traceToken = await diagnostics?.beginTrace()
      let clock = ContinuousClock()
      let processingStartedAt = clock.now
      let result = await processor.process(
        transcript,
        alternatives: alternatives,
        confidence: confidence,
        inputSource: source == .voice ? .voice : .manual
      ) { [weak self] in
        guard let self else { return }
        phase = .executing
        if source == .voice {
          presentVoiceFeedback(.executing(transcript))
        }
      }

      guard !Task.isCancelled, let self else { return }
      commandExecutionTask = nil
      apply(result.outcome, source: source)

      if let diagnostics, let traceToken {
        let duration = processingStartedAt.duration(to: clock.now)
        let durationMilliseconds = Self.milliseconds(in: duration)
        Task {
          await diagnostics.record(
            transcript: transcript,
            interpretedTranscript: result.interpretation.wasCorrected
              ? result.interpretation.selectedTranscript
              : nil,
            interpretationReason: result.interpretation.reason,
            transcriptionConfidence: result.interpretation.confidence,
            captureMetrics: captureMetrics,
            source: source,
            trace: result.trace,
            processingDurationMilliseconds: durationMilliseconds,
            using: traceToken
          )
        }
      }
    }
  }

  private func apply(_ outcome: AssistantCommandOutcome, source: DeveloperTranscriptSource) {
    switch outcome {
    case .unsupported(let reason):
      applyFailure(unsupportedMessage(for: reason), source: source)
    case .denied(let reason):
      applyFailure(reason, source: source)
    case .completed(let actionOutcome):
      apply(actionOutcome, source: source)
    }
  }

  private func unsupportedMessage(for reason: UnsupportedCommandReason) -> String {
    switch reason {
    case .ambiguousTarget:
      "I found more than one installed app with that name. Say the full app name."
    case .applicationNotFound:
      "I couldn't find that application installed on this Mac."
    case .compoundRequest:
      "I can perform one action at a time. Try each request separately."
    case .contextRequired:
      "That request needs app, browser, or screen context that Topher does not have yet."
    case .emptyInput, .missingValue:
      "That command is missing a target or search value."
    case .uncertainDomain:
      "I heard more than one possible domain. Say it again or type the exact domain in Topher."
    case .unknownTarget:
      "Topher does not know that app or destination yet."
    case .unsupportedAction:
      "Topher knows that target but does not support that action yet."
    case .unsupportedPhrasing:
      "Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”"
    }
  }

  private func apply(_ outcome: ActionOutcome, source: DeveloperTranscriptSource) {
    switch outcome {
    case .succeeded(let message):
      phase = .success(message)
      if source == .voice {
        presentVoiceResult(.success(message))
      }
    case .failed(let message):
      applyFailure(message, source: source)
    }
  }

  private func applyFailure(_ message: String, source: DeveloperTranscriptSource) {
    phase = .failure(message)
    if source == .voice {
      presentVoiceResult(.failure(message))
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

  private static func milliseconds(in duration: Duration) -> UInt64 {
    let components = duration.components
    let seconds = Double(components.seconds)
    let fractionalSeconds = Double(components.attoseconds) / 1_000_000_000_000_000_000
    return UInt64(max(0, (seconds + fractionalSeconds) * 1_000).rounded())
  }
}

private enum VoicePresentation: Equatable, Sendable {
  case globalShortcut
  case menuPreparation
}
