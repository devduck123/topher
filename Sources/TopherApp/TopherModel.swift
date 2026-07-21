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
        "Couldn’t complete request"
      }
    }

    var detail: String {
      switch self {
      case .idle:
        "Use the assistant shortcut for commands or the dictation shortcut to type anywhere."
      case .preparingVoice:
        "Checking microphone access and the local speech model."
      case .listening(let transcript):
        transcript.isEmpty ? "Release the shortcut when you’re done." : transcript
      case .finalizingVoice:
        "Finishing the on-device transcript."
      case .transcribing:
        "Resolving the manual transcript."
      case .executing:
        "Running an approved local capability."
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
    case dictationPreparing(String)
    case dictationListening(String)
    case dictationFinalizing(String)
    case dictationInserting(String)
  }

  @Published var manualTranscript = ""
  @Published private(set) var phase: Phase = .idle
  @Published private(set) var voiceReadiness: VoiceReadiness
  @Published private(set) var voiceFeedback: VoiceFeedback = .hidden
  @Published private(set) var accessibilityPermissionState: AccessibilityPermissionState
  @Published private(set) var pendingDictationText: String?
  @Published private(set) var youTubeFeedSnapshot: YouTubeFeedSnapshot?
  @Published private(set) var canUndoDictation = false
  @Published private(set) var isDictationPolishEnabled: Bool

  var canRunManualCommand: Bool {
    !manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !phase.isBusy
  }

  private let commandProcessor: AssistantCommandProcessor
  private let chromeContext: ChromeContextCapabilities
  private let captureController: PushToTalkCaptureController
  private let developerDiagnostics: DeveloperDiagnosticsController?
  private let voiceFeedbackResultDuration: Duration
  private let dictationListeningTimeout: Duration
  private let accessibilityPermission: AccessibilityPermissionClient
  private let focusedTextInsertion: FocusedTextInsertionCapability
  private let dictationClipboard: DictationClipboardCapability
  private let vocabularyProvider: @MainActor () -> TranscriptVocabulary

  private var assistantShortcutEventsTask: Task<Void, Never>?
  private var dictationShortcutEventsTask: Task<Void, Never>?
  private var commandExecutionTask: Task<Void, Never>?
  private var dictationInsertionTask: Task<Void, Never>?
  private var voiceFeedbackDismissalTask: Task<Void, Never>?
  private var youTubeFeedExpiryTask: Task<Void, Never>?
  private var voiceFeedbackGeneration: UInt64 = 0
  private var activePermissionFailure: MicrophonePermissionState?
  private var activeVoicePresentation: VoicePresentation?
  private var activeVoiceMode: VoiceMode?
  private var activeDictationPreparation: FocusedTextPreparationOutcome?
  private var activeDictationPreparationEvidence: FocusedTextPreparationEvidence?
  private var shortcutOwner: ShortcutOwner?

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
    dictationListeningTimeout: Duration = .seconds(120),
    dictationPolishEnabled: Bool = true,
    finalizationTimeout: Duration = .seconds(8),
    voiceFeedbackResultDuration: Duration = .seconds(3),
    developerDiagnostics: DeveloperDiagnosticsController? = nil,
    accessibilityPermission: AccessibilityPermissionClient? = nil,
    focusedTextInsertion: FocusedTextInsertionCapability? = nil,
    dictationClipboard: DictationClipboardCapability? = nil,
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

    let chromeContext = chromeContext ?? .unavailable()
    self.chromeContext = chromeContext
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
    self.dictationListeningTimeout = dictationListeningTimeout
    self.isDictationPolishEnabled = dictationPolishEnabled
    let accessibilityPermission = accessibilityPermission ?? AccessibilityPermissionClient()
    self.accessibilityPermission = accessibilityPermission
    self.focusedTextInsertion = focusedTextInsertion ?? FocusedTextInsertionCapability()
    self.dictationClipboard = dictationClipboard ?? DictationClipboardCapability()
    self.vocabularyProvider = vocabularyProvider
    voiceReadiness = captureController.readiness
    accessibilityPermissionState = accessibilityPermission.currentState

    captureController.onEvent = { [weak self] event in
      self?.handleCaptureEvent(event)
    }

    if listenForShortcutEvents {
      assistantShortcutEventsTask = Task { [weak self] in
        for await event in KeyboardShortcuts.events(for: .pushToTalk) {
          guard let self else { return }

          switch event {
          case .keyDown:
            handleShortcutDown(.assistantCommand)
          case .keyUp:
            handleShortcutUp(.assistantCommand)
          }
        }
      }
      dictationShortcutEventsTask = Task { [weak self] in
        for await event in KeyboardShortcuts.events(for: .dictation) {
          guard let self else { return }

          switch event {
          case .keyDown:
            handleShortcutDown(.dictation)
          case .keyUp:
            handleShortcutUp(.dictation)
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
    assistantShortcutEventsTask?.cancel()
    dictationShortcutEventsTask?.cancel()
    commandExecutionTask?.cancel()
    dictationInsertionTask?.cancel()
    voiceFeedbackDismissalTask?.cancel()
    youTubeFeedExpiryTask?.cancel()
  }

  func refreshVoiceReadiness() {
    captureController.refreshReadiness()
  }

  func refreshAccessibilityPermission() {
    accessibilityPermissionState = accessibilityPermission.currentState
    if accessibilityPermissionState == .authorized,
      case .failure(let message) = phase,
      message.contains("Accessibility")
    {
      phase = .idle
    }
  }

  func clearYouTubeFeedResults() {
    youTubeFeedExpiryTask?.cancel()
    youTubeFeedExpiryTask = nil
    youTubeFeedSnapshot = nil
    chromeContext.clearYouTubeFeedSession()
  }

  func requestAccessibilityPermission() {
    accessibilityPermissionState = accessibilityPermission.requestAuthorization()
    if accessibilityPermissionState == .authorized {
      phase = .success("Accessibility access is ready for global dictation.")
    } else {
      phase = .failure(
        "Allow Topher in System Settings → Privacy & Security → Accessibility. \(AccessibilityPermissionClient.recoveryInstructions)"
      )
    }
  }

  func openAccessibilitySettings() {
    accessibilityPermission.openSettings()
  }

  func prepareVoiceInput() {
    guard canStartNewInteraction else { return }

    let previousPermissionFailure = activePermissionFailure
    activePermissionFailure = nil
    activeVoicePresentation = .menuPreparation
    activeVoiceMode = .assistantCommand
    hideVoiceFeedback()
    if !captureController.prepareForUse() {
      activePermissionFailure = previousPermissionFailure
      activeVoicePresentation = nil
      activeVoiceMode = nil
    }
  }

  func beginPushToTalk() {
    _ = startAssistantHold()
  }

  @discardableResult
  private func startAssistantHold() -> Bool {
    guard canStartNewInteraction else { return false }

    let previousPermissionFailure = activePermissionFailure
    activePermissionFailure = nil
    activeVoicePresentation = .globalShortcut
    activeVoiceMode = .assistantCommand
    if !captureController.beginHold() {
      activePermissionFailure = previousPermissionFailure
      activeVoicePresentation = nil
      activeVoiceMode = nil
      return false
    }
    return true
  }

  func endPushToTalk() {
    // Always forward key-up. During first-run preparation this clears the
    // controller's physical-held gate even though listening has not begun.
    captureController.endHold()
  }

  func beginDictation() {
    _ = startDictationHold()
  }

  @discardableResult
  private func startDictationHold() -> Bool {
    guard canStartNewInteraction else { return false }

    activePermissionFailure = nil
    hideVoiceFeedback()
    refreshAccessibilityPermission()
    guard accessibilityPermissionState == .authorized else {
      accessibilityPermissionState = accessibilityPermission.requestAuthorization()
      let message =
        "Allow Topher in System Settings → Privacy & Security → Accessibility. \(AccessibilityPermissionClient.recoveryInstructions) Then hold the dictation shortcut again."
      phase = .failure(message)
      presentVoiceResult(.failure(message))
      return false
    }

    let preparation = focusedTextInsertion.prepareTarget()
    activeDictationPreparationEvidence = focusedTextInsertion.latestPreparationEvidence
    if preparation == .secureField {
      let message = "Dictation is disabled in secure text fields."
      phase = .failure(message)
      presentVoiceResult(.failure(message))
      return false
    }

    activeVoicePresentation = .globalShortcut
    activeVoiceMode = .dictation
    activeDictationPreparation = preparation
    guard captureController.beginHold(maximumDuration: dictationListeningTimeout) else {
      activeVoicePresentation = nil
      activeVoiceMode = nil
      activeDictationPreparation = nil
      activeDictationPreparationEvidence = nil
      focusedTextInsertion.discardPreparedTarget()
      return false
    }
    return true
  }

  func endDictation() {
    captureController.endHold()
  }

  func copyPendingDictation() {
    guard
      let pendingDictationText,
      let text = try? DictationText(
        pendingDictationText,
        polishPolicy: .presentationOnly
      )
    else {
      return
    }
    if dictationClipboard.copy(text) {
      phase = .success("Copied dictation. Paste it where you want it.")
    } else {
      phase = .failure("Couldn’t copy the pending dictation.")
    }
  }

  func clearPendingDictation() {
    pendingDictationText = nil
  }

  func setDictationPolishEnabled(_ enabled: Bool) {
    isDictationPolishEnabled = enabled
  }

  func undoLastDictation() {
    let outcome = focusedTextInsertion.undoLastInsertion()
    canUndoDictation = focusedTextInsertion.canUndo
    switch outcome {
    case .restored:
      phase = .success("Undid the last dictation insertion.")
    case .unavailable:
      phase = .failure("There is no dictation insertion to undo.")
    case .focusChanged:
      phase = .failure("Return to the original text field before undoing dictation.")
    case .secureField:
      phase = .failure("The original field became secure, so Topher disabled dictation undo.")
    case .selectionChanged:
      phase = .failure("The caret moved, so Topher left the text unchanged.")
    case .contentChanged:
      phase = .failure("The inserted text changed, so Topher left it unchanged.")
    case .failed:
      phase = .failure("Couldn’t safely undo the last dictation insertion.")
    }
  }

  func runManually() {
    guard canStartNewInteraction else { return }

    let transcript = manualTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !transcript.isEmpty else { return }

    activeVoicePresentation = nil
    activeVoiceMode = nil
    activePermissionFailure = nil
    hideVoiceFeedback()
    phase = .transcribing
    startCommandProcessing(transcript, source: .manual, yieldBeforeProcessing: true)
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
      && dictationInsertionTask == nil
  }

  func handleShortcutDown(_ owner: ShortcutOwner) {
    guard shortcutOwner == nil else { return }
    let accepted =
      switch owner {
      case .assistantCommand:
        startAssistantHold()
      case .dictation:
        startDictationHold()
      }
    if accepted {
      shortcutOwner = owner
    }
  }

  func handleShortcutUp(_ owner: ShortcutOwner) {
    guard shortcutOwner == owner else { return }
    shortcutOwner = nil
    switch owner {
    case .assistantCommand:
      endPushToTalk()
    case .dictation:
      endDictation()
    }
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
      resetActiveVoiceInteraction()
      phase = .success(message)
      if presentsGlobally {
        presentVoiceResult(.success(message))
      }

    case .releasedBeforeListening:
      let message = "Released before listening started. Hold the shortcut again."
      let presentsGlobally = activeVoicePresentation == .globalShortcut
      resetActiveVoiceInteraction()
      phase = .success(message)
      if presentsGlobally {
        presentVoiceResult(.failure(message))
      }

    case .maximumDurationReached:
      phase = .finalizingVoice
      guard activeVoicePresentation == .globalShortcut else { return }
      let message = "Maximum length reached—finishing automatically."
      presentVoiceFeedback(
        activeVoiceMode == .dictation
          ? .dictationFinalizing(message)
          : .finalizing(message)
      )

    case .completed(let rawTranscript):
      let presentsGlobally = activeVoicePresentation == .globalShortcut
      let mode = activeVoiceMode ?? .assistantCommand
      let dictationPreparation = activeDictationPreparation
      let dictationPreparationEvidence = activeDictationPreparationEvidence
      clearActiveVoiceStateWithoutDiscardingTarget()
      let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !transcript.isEmpty else {
        focusedTextInsertion.discardPreparedTarget()
        recordNoUsableSpeechIfEnabled(source: mode.diagnosticSource)
        let message = mode.noUsableSpeechMessage
        phase = .failure(message)
        if presentsGlobally {
          presentVoiceResult(.failure(message))
        }
        return
      }

      switch mode {
      case .assistantCommand:
        startCommandProcessing(transcript, source: .voice)
      case .dictation:
        startDictationProcessing(
          transcript,
          preparation: dictationPreparation,
          preparationEvidence: dictationPreparationEvidence,
          presentsGlobally: presentsGlobally
        )
      }

    case .completedWithEvidence(let transcription):
      let presentsGlobally = activeVoicePresentation == .globalShortcut
      let mode = activeVoiceMode ?? .assistantCommand
      let dictationPreparation = activeDictationPreparation
      let dictationPreparationEvidence = activeDictationPreparationEvidence
      clearActiveVoiceStateWithoutDiscardingTarget()
      let transcript = transcription.primary.text.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !transcript.isEmpty else {
        focusedTextInsertion.discardPreparedTarget()
        recordNoUsableSpeechIfEnabled(
          source: mode.diagnosticSource,
          captureMetrics: transcription.captureMetrics
        )
        let message = mode.noUsableSpeechMessage
        phase = .failure(message)
        if presentsGlobally {
          presentVoiceResult(.failure(message))
        }
        return
      }

      switch mode {
      case .assistantCommand:
        startCommandProcessing(
          transcript,
          source: .voice,
          alternatives: transcription.alternatives,
          confidence: transcription.primary.confidence,
          captureMetrics: transcription.captureMetrics
        )
      case .dictation:
        let selection = DictationTranscriptSelector(
          vocabulary: vocabularyProvider()
        ).select(
          primary: transcription.primary,
          alternatives: transcription.alternatives
        )
        startDictationProcessing(
          selection.selectedTranscript,
          rawTranscript: selection.rawTranscript,
          preparation: dictationPreparation,
          preparationEvidence: dictationPreparationEvidence,
          confidence: selection.confidence,
          pauses: selection.reason == nil ? transcription.pauses : [],
          interpretationReason: selection.reason,
          captureMetrics: transcription.captureMetrics,
          presentsGlobally: presentsGlobally
        )
      }

    case .failed(let failure):
      applyCaptureFailure(failure)

    case .failedWithRecovery(let failure, let transcript):
      applyCaptureFailure(failure, recoverableTranscript: transcript)
    }
  }

  private func recordNoUsableSpeechIfEnabled(
    source: DeveloperTranscriptSource = .voice,
    captureMetrics: VoiceCaptureMetrics? = nil
  ) {
    guard let developerDiagnostics else { return }

    Task {
      guard let token = await developerDiagnostics.beginTrace() else { return }
      await developerDiagnostics.record(
        transcript: "",
        captureMetrics: captureMetrics,
        source: source,
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
    let isDictation = activeVoiceMode == .dictation

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
      presentVoiceFeedback(
        isDictation ? .dictationPreparing(detail) : .preparing(detail)
      )

    case .listening(let transcript):
      phase = .listening(transcript)
      if presentsGlobally {
        presentVoiceFeedback(
          isDictation ? .dictationListening(transcript) : .listening(transcript)
        )
      }

    case .finalizing(let transcript):
      phase = .finalizingVoice
      if presentsGlobally {
        presentVoiceFeedback(
          isDictation ? .dictationFinalizing(transcript) : .finalizing(transcript)
        )
      }
    }
  }

  private func applyCaptureFailure(
    _ failure: PushToTalkCaptureFailure,
    recoverableTranscript: String? = nil
  ) {
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
    case .finalizationTimedOut:
      activePermissionFailure = nil
      message = "Voice finalization timed out. Try the shortcut again."
    }

    let presentsGlobally = activeVoicePresentation == .globalShortcut
    let mode = activeVoiceMode ?? .assistantCommand
    let dictationPreparation = activeDictationPreparation
    var recoveredMessage: String?
    var mayRecordFailure = true

    if let recoverableTranscript,
      !recoverableTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      switch mode {
      case .assistantCommand:
        manualTranscript = recoverableTranscript
        recoveredMessage =
          "Transcription stopped before finalizing. Open Topher to review the recovered text; it was not executed."
        focusedTextInsertion.discardPreparedTarget()
      case .dictation:
        let mayRetain =
          dictationPreparation != .ready
          || focusedTextInsertion.discardPreparedTargetForRecovery()
        if mayRetain,
          let recoveredText = try? DictationText(
            recoverableTranscript,
            polishPolicy: .presentationOnly
          )
        {
          pendingDictationText = recoveredText.value
          recoveredMessage =
            "Transcription stopped before finalizing. Open Topher to review or copy the recovered text."
        } else if !mayRetain {
          recoveredMessage =
            "The target became secure, so Topher discarded the unfinished dictation."
          mayRecordFailure = false
        }
      }
    } else {
      focusedTextInsertion.discardPreparedTarget()
    }

    clearActiveVoiceStateWithoutDiscardingTarget()
    if mayRecordFailure, failure.shouldRecordInDeveloperDiagnostics {
      recordCaptureFailureIfEnabled(failure, source: mode.diagnosticSource)
    }
    let finalMessage = recoveredMessage ?? message
    phase = .failure(finalMessage)
    if presentsGlobally {
      presentVoiceResult(.failure(finalMessage))
    }
  }

  private func recordCaptureFailureIfEnabled(
    _ failure: PushToTalkCaptureFailure,
    source: DeveloperTranscriptSource
  ) {
    guard let developerDiagnostics else { return }
    Task {
      guard let token = await developerDiagnostics.beginTrace() else { return }
      await developerDiagnostics.record(
        transcript: "",
        source: source,
        captureFailureReason: failure,
        trace: AssistantCommandTrace(
          outcome: .captureFailed,
          commandKind: nil,
          capabilityIdentifier: nil
        ),
        processingDurationMilliseconds: 0,
        using: token
      )
    }
  }

  private func startDictationProcessing(
    _ transcript: String,
    rawTranscript: String? = nil,
    preparation: FocusedTextPreparationOutcome?,
    preparationEvidence: FocusedTextPreparationEvidence?,
    confidence: Double? = nil,
    pauses: [DictationPause] = [],
    interpretationReason: TranscriptInterpretationReason? = nil,
    captureMetrics: VoiceCaptureMetrics? = nil,
    presentsGlobally: Bool
  ) {
    guard dictationInsertionTask == nil else {
      focusedTextInsertion.discardPreparedTarget()
      return
    }
    dictationInsertionTask = Task { [weak self] in
      guard let self else { return }
      await processDictation(
        transcript,
        rawTranscript: rawTranscript ?? transcript,
        preparation: preparation,
        preparationEvidence: preparationEvidence,
        confidence: confidence,
        pauses: pauses,
        interpretationReason: interpretationReason,
        captureMetrics: captureMetrics,
        presentsGlobally: presentsGlobally
      )
      dictationInsertionTask = nil
    }
  }

  private func processDictation(
    _ transcript: String,
    rawTranscript: String,
    preparation: FocusedTextPreparationOutcome?,
    preparationEvidence: FocusedTextPreparationEvidence?,
    confidence: Double? = nil,
    pauses: [DictationPause] = [],
    interpretationReason: TranscriptInterpretationReason? = nil,
    captureMetrics: VoiceCaptureMetrics? = nil,
    presentsGlobally: Bool
  ) async {
    let clock = ContinuousClock()
    let startedAt = clock.now
    phase = .executing
    if presentsGlobally {
      presentVoiceFeedback(.dictationInserting(transcript))
    }

    let dictationText: DictationText
    do {
      dictationText = try DictationText(
        transcript,
        pauses: pauses,
        polishPolicy: isDictationPolishEnabled ? .conservative : .presentationOnly
      )
    } catch DictationTextError.tooLong {
      focusedTextInsertion.discardPreparedTarget()
      let message = "That dictation is too long to insert safely. Try a shorter hold."
      phase = .failure(message)
      if presentsGlobally { presentVoiceResult(.failure(message)) }
      recordDictationIfEnabled(
        transcript: rawTranscript,
        interpretedTranscript: nil,
        confidence: confidence,
        captureMetrics: captureMetrics,
        outcome: .dictationFailed,
        capabilityIdentifier: nil,
        failureReason: .tooLong,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now)
      )
      return
    } catch {
      focusedTextInsertion.discardPreparedTarget()
      let message = "I didn’t hear text to dictate. Hold the shortcut and try again."
      phase = .failure(message)
      if presentsGlobally { presentVoiceResult(.failure(message)) }
      return
    }

    guard preparation == .ready else {
      focusedTextInsertion.discardPreparedTarget()
      presentDictationFallback(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        failureReason: preparation == .noFocusedElement
          ? .noFocusedElement
          : .unsupportedField,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )
      return
    }

    let insertionOutcome = await focusedTextInsertion.insert(dictationText)
    canUndoDictation = focusedTextInsertion.canUndo
    switch insertionOutcome {
    case .inserted(let result):
      let message = "Inserted dictation."
      phase = .success(message)
      if presentsGlobally { presentVoiceResult(.success(message)) }
      recordDictationIfEnabled(
        transcript: rawTranscript,
        interpretedTranscript: result.text == rawTranscript ? nil : result.text,
        interpretationReason: interpretationReason ?? dictationText.interpretationReason,
        confidence: confidence,
        captureMetrics: captureMetrics,
        outcome: .dictationInserted,
        capabilityIdentifier: FocusedTextInsertionCapability.descriptor.identifier,
        insertionEvidence: result.evidence,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now)
      )

    case .mutationNotObserved(let evidence):
      presentDictationFallback(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        failureReason: .mutationNotObserved,
        preparationEvidence: preparationEvidence,
        insertionEvidence: evidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )

    case .mutationUnverified(let evidence):
      presentUnverifiedDictation(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        insertionEvidence: evidence,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )

    case .secureField:
      // Do not keep a preview or diagnostic when a target becomes secure
      // during the hold. This is the one deliberate exception to dogfood
      // transcript logging.
      let message = "The target became secure, so Topher discarded the dictation."
      phase = .failure(message)
      if presentsGlobally { presentVoiceResult(.failure(message)) }

    case .focusChanged:
      presentDictationFallback(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        failureReason: .focusChanged,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )
    case .selectionChanged:
      presentDictationFallback(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        failureReason: .selectionChanged,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )
    case .unsupportedField:
      presentDictationFallback(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        failureReason: .unsupportedField,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )
    case .failed:
      presentDictationFallback(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        failureReason: .mutationFailed,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )
    case .noPreparedTarget:
      presentDictationFallback(
        dictationText,
        transcript: rawTranscript,
        confidence: confidence,
        captureMetrics: captureMetrics,
        interpretationReason: interpretationReason,
        failureReason: .noPreparedTarget,
        preparationEvidence: preparationEvidence,
        processingDuration: startedAt.duration(to: clock.now),
        presentsGlobally: presentsGlobally
      )
    }
  }

  private func presentDictationFallback(
    _ dictationText: DictationText,
    transcript: String,
    confidence: Double?,
    captureMetrics: VoiceCaptureMetrics?,
    interpretationReason: TranscriptInterpretationReason? = nil,
    failureReason: DictationFailureReason,
    preparationEvidence: FocusedTextPreparationEvidence?,
    insertionEvidence: FocusedTextInsertionEvidence? = nil,
    processingDuration: Duration,
    presentsGlobally: Bool
  ) {
    pendingDictationText = dictationText.value
    let message: String
    if preparationEvidence?.targetApplication == .terminal {
      message =
        "Terminal doesn’t expose a writable focused field. Open Topher to review or copy the dictation."
    } else if insertionEvidence?.target.application == .codexOrChatGPT,
      insertionEvidence?.wholeValueDecision == .rejectedAmbiguousWebSelection
    {
      message =
        "Codex doesn’t expose a verifiable insertion point for that authored content. Topher left it unchanged; open Topher to review or copy the dictation."
    } else {
      message = "Couldn’t safely insert there. Open Topher to review or copy the dictation."
    }
    phase = .failure(message)
    if presentsGlobally { presentVoiceResult(.failure(message)) }
    recordDictationIfEnabled(
      transcript: transcript,
      interpretedTranscript: dictationText.value == transcript ? nil : dictationText.value,
      interpretationReason: interpretationReason ?? dictationText.interpretationReason,
      confidence: confidence,
      captureMetrics: captureMetrics,
      outcome: .dictationFallback,
      capabilityIdentifier: FocusedTextInsertionCapability.descriptor.identifier,
      failureReason: failureReason,
      insertionEvidence: insertionEvidence,
      preparationEvidence: preparationEvidence,
      processingDuration: processingDuration
    )
  }

  private func presentUnverifiedDictation(
    _ dictationText: DictationText,
    transcript: String,
    confidence: Double?,
    captureMetrics: VoiceCaptureMetrics?,
    interpretationReason: TranscriptInterpretationReason? = nil,
    insertionEvidence: FocusedTextInsertionEvidence,
    preparationEvidence: FocusedTextPreparationEvidence?,
    processingDuration: Duration,
    presentsGlobally: Bool
  ) {
    pendingDictationText = dictationText.value
    let message =
      "Topher couldn’t verify whether that text appeared. Check the target before copying the pending dictation."
    phase = .failure(message)
    if presentsGlobally { presentVoiceResult(.failure(message)) }
    recordDictationIfEnabled(
      transcript: transcript,
      interpretedTranscript: dictationText.value == transcript ? nil : dictationText.value,
      interpretationReason: interpretationReason ?? dictationText.interpretationReason,
      confidence: confidence,
      captureMetrics: captureMetrics,
      outcome: .dictationFallback,
      capabilityIdentifier: FocusedTextInsertionCapability.descriptor.identifier,
      failureReason: .mutationUnverified,
      insertionEvidence: insertionEvidence,
      preparationEvidence: preparationEvidence,
      processingDuration: processingDuration
    )
  }

  private func recordDictationIfEnabled(
    transcript: String,
    interpretedTranscript: String?,
    interpretationReason: TranscriptInterpretationReason? = nil,
    confidence: Double?,
    captureMetrics: VoiceCaptureMetrics?,
    outcome: AssistantCommandTraceOutcome,
    capabilityIdentifier: String?,
    failureReason: DictationFailureReason? = nil,
    insertionEvidence: FocusedTextInsertionEvidence? = nil,
    preparationEvidence: FocusedTextPreparationEvidence? = nil,
    processingDuration: Duration
  ) {
    guard let developerDiagnostics else { return }
    let durationMilliseconds = Self.milliseconds(in: processingDuration)
    Task {
      guard let token = await developerDiagnostics.beginTrace() else { return }
      await developerDiagnostics.record(
        transcript: transcript,
        interpretedTranscript: interpretedTranscript,
        interpretationReason: interpretationReason,
        transcriptionConfidence: confidence,
        captureMetrics: captureMetrics,
        source: .dictation,
        trace: AssistantCommandTrace(
          outcome: outcome,
          commandKind: nil,
          capabilityIdentifier: capabilityIdentifier,
          dictationFailureReason: failureReason,
          dictationPreparationEvidence: preparationEvidence,
          dictationInsertionEvidence: insertionEvidence
        ),
        processingDurationMilliseconds: durationMilliseconds,
        using: token
      )
    }
  }

  private func resetActiveVoiceInteraction() {
    focusedTextInsertion.discardPreparedTarget()
    clearActiveVoiceStateWithoutDiscardingTarget()
  }

  private func clearActiveVoiceStateWithoutDiscardingTarget() {
    activeVoicePresentation = nil
    activeVoiceMode = nil
    activeDictationPreparation = nil
    activeDictationPreparationEvidence = nil
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
      apply(result.presentationUpdate)
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

  private func apply(_ update: AssistantCommandPresentationUpdate?) {
    guard let update else { return }
    youTubeFeedExpiryTask?.cancel()
    youTubeFeedExpiryTask = nil

    switch update {
    case .clearYouTubeFeed:
      youTubeFeedSnapshot = nil
      chromeContext.clearYouTubeFeedSession()
    case .youTubeFeed(let snapshot):
      youTubeFeedSnapshot = snapshot
      let nowMilliseconds = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
      let remainingMilliseconds = max(0, snapshot.expiresAtMilliseconds - nowMilliseconds)
      youTubeFeedExpiryTask = Task { [weak self] in
        do {
          try await Task.sleep(for: .milliseconds(remainingMilliseconds))
        } catch {
          return
        }
        guard
          let self,
          youTubeFeedSnapshot?.feedObservationID == snapshot.feedObservationID
        else { return }
        youTubeFeedSnapshot = nil
        chromeContext.clearYouTubeFeedSession()
        youTubeFeedExpiryTask = nil
      }
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
    case .dictationModeRequired:
      "Use the hold-to-dictate shortcut to insert text into the focused field."
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

private enum VoiceMode: Equatable, Sendable {
  case assistantCommand
  case dictation

  var diagnosticSource: DeveloperTranscriptSource {
    switch self {
    case .assistantCommand:
      .voice
    case .dictation:
      .dictation
    }
  }

  var noUsableSpeechMessage: String {
    switch self {
    case .assistantCommand:
      "I didn’t hear a command. Hold the shortcut and try again."
    case .dictation:
      "I didn’t hear any dictation. Hold the shortcut and try again."
    }
  }
}

extension PushToTalkCaptureFailure {
  fileprivate var shouldRecordInDeveloperDiagnostics: Bool {
    switch self {
    case .startFailed, .resultStreamEnded, .resultStreamFailed, .finalizationFailed,
      .finalizationTimedOut:
      true
    case .microphonePermissionRequired, .microphoneDenied, .microphoneRestricted,
      .speechModelNotReady, .speechAssetPreparationFailed:
      false
    }
  }
}

enum ShortcutOwner: Equatable, Sendable {
  case assistantCommand
  case dictation
}
