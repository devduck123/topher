import AVFAudio
import Foundation
import Speech

enum TranscriptionEvent: Equatable, Sendable {
  /// The complete best-known text, including the current volatile phrase.
  case partial(String)
  /// The complete text after the analyzer has consumed and finalized input.
  case final(String)
}

enum TranscriptionSessionError: Error, Equatable, LocalizedError, Sendable {
  case speechUnavailable
  case unsupportedLocale
  case missingAudioFormat
  case invalidMicrophoneFormat
  case invalidState

  var errorDescription: String? {
    switch self {
    case .speechUnavailable:
      "On-device transcription is unavailable on this Mac."
    case .unsupportedLocale:
      "The selected transcription language is unsupported."
    case .missingAudioFormat:
      "No compatible speech audio format is installed."
    case .invalidMicrophoneFormat:
      "The microphone did not provide a usable audio format."
    case .invalidState:
      "The transcription session is not ready for that operation."
    }
  }
}

struct SpeechRecognitionUpdate: Equatable, Sendable {
  let text: String
  let isFinal: Bool
}

@MainActor
struct SpeechAnalysisRuntime {
  let audioFormat: AVAudioFormat
  let updates: () -> AsyncThrowingStream<SpeechRecognitionUpdate, any Error>
  let prepare: () async throws -> Void
  let start: (AsyncStream<AnalyzerInput>) async throws -> Void
  let finish: () async throws -> Void
  let cancel: () async -> Void

  static func apple(locale: Locale) async throws -> Self {
    guard SpeechTranscriber.isAvailable else {
      throw TranscriptionSessionError.speechUnavailable
    }
    guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
      throw TranscriptionSessionError.unsupportedLocale
    }

    let transcriber = SpeechTranscriber(
      locale: supportedLocale,
      preset: .progressiveTranscription
    )
    guard
      let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
        compatibleWith: [transcriber]
      )
    else {
      throw TranscriptionSessionError.missingAudioFormat
    }

    let analyzer = SpeechAnalyzer(
      modules: [transcriber],
      options: .init(priority: .userInitiated, modelRetention: .lingering)
    )

    return Self(
      audioFormat: audioFormat,
      updates: {
        AsyncThrowingStream { continuation in
          let resultsTask = Task {
            do {
              for try await result in transcriber.results {
                continuation.yield(
                  SpeechRecognitionUpdate(
                    text: String(result.text.characters),
                    isFinal: result.isFinal
                  )
                )
              }
              continuation.finish()
            } catch is CancellationError {
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
          continuation.onTermination = { _ in resultsTask.cancel() }
        }
      },
      prepare: {
        try await analyzer.prepareToAnalyze(in: audioFormat)
      },
      start: { inputSequence in
        try await analyzer.start(inputSequence: inputSequence)
      },
      finish: {
        try await analyzer.finalizeAndFinishThroughEndOfInput()
      },
      cancel: {
        await analyzer.cancelAndFinishNow()
      }
    )
  }
}

@MainActor
struct MicrophoneCapture {
  let inputFormat: () throws -> AVAudioFormat
  let start: (@escaping @Sendable (AVAudioPCMBuffer) -> Void) throws -> Void
  let stop: () -> Void

  static func live() -> Self {
    let capture = LiveMicrophoneCapture()
    return Self(
      inputFormat: { try capture.inputFormat() },
      start: { try capture.start(receive: $0) },
      stop: { capture.stop() }
    )
  }
}

@MainActor
private final class LiveMicrophoneCapture {
  private let engine = AVAudioEngine()
  private var tapIsInstalled = false

  func inputFormat() throws -> AVAudioFormat {
    let format = engine.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw TranscriptionSessionError.invalidMicrophoneFormat
    }
    return format
  }

  func start(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
    stop()

    let inputNode = engine.inputNode
    let format = try inputFormat()
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) {
      buffer,
      _ in
      receive(buffer)
    }
    tapIsInstalled = true

    do {
      engine.prepare()
      try engine.start()
    } catch {
      inputNode.removeTap(onBus: 0)
      tapIsInstalled = false
      throw error
    }
  }

  func stop() {
    if engine.isRunning {
      engine.stop()
    }
    if tapIsInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapIsInstalled = false
    }
    engine.reset()
  }
}

/// A reusable push-to-talk transcription session.
///
/// Call `prepare()` after permissions and assets are ready, then `start()` to
/// obtain a per-hold event stream. `finish()` flushes conversion and explicitly
/// finalizes SpeechAnalyzer. `cancel()` is safe from every state.
@MainActor
final class AppleSpeechTranscriptionSession {
  typealias RuntimeFactory = @MainActor () async throws -> SpeechAnalysisRuntime
  typealias ConverterFactory = (AVAudioFormat, AVAudioFormat) throws -> any SpeechAudioConverting

  private enum Phase {
    case idle
    case preparing
    case prepared
    case active
    case finishing
  }

  private let runtimeFactory: RuntimeFactory
  private let microphone: MicrophoneCapture
  private let converterFactory: ConverterFactory

  private var phase: Phase = .idle
  private var generation: UInt64 = 0
  private var runtime: SpeechAnalysisRuntime?
  private var converter: (any SpeechAudioConverting)?
  private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
  private var eventContinuation: AsyncThrowingStream<TranscriptionEvent, any Error>.Continuation?
  private var resultsTask: Task<Void, Never>?
  private var resultsError: (any Error)?
  private var finalizedText = ""
  private var volatileText = ""

  convenience init(locale: Locale = Locale(identifier: "en_US")) {
    self.init(
      runtimeFactory: { try await .apple(locale: locale) },
      microphone: .live(),
      converterFactory: { try SpeechAudioConverter(inputFormat: $0, outputFormat: $1) }
    )
  }

  init(
    runtimeFactory: @escaping RuntimeFactory,
    microphone: MicrophoneCapture,
    converterFactory: @escaping ConverterFactory
  ) {
    self.runtimeFactory = runtimeFactory
    self.microphone = microphone
    self.converterFactory = converterFactory
  }

  func prepare() async throws {
    if phase == .prepared { return }
    guard phase == .idle else { throw TranscriptionSessionError.invalidState }
    try Task.checkCancellation()

    let token = nextGeneration()
    phase = .preparing
    var candidateRuntime: SpeechAnalysisRuntime?

    do {
      let newRuntime = try await runtimeFactory()
      candidateRuntime = newRuntime
      guard isCurrent(token, phase: .preparing) else {
        await newRuntime.cancel()
        throw CancellationError()
      }
      try await newRuntime.prepare()
      guard isCurrent(token, phase: .preparing) else {
        await newRuntime.cancel()
        throw CancellationError()
      }
      try Task.checkCancellation()
      runtime = newRuntime
      phase = .prepared
    } catch {
      if generation == token {
        await candidateRuntime?.cancel()
        resetState()
      }
      throw error
    }
  }

  func start() async throws -> AsyncThrowingStream<TranscriptionEvent, any Error> {
    guard phase == .prepared, let runtime else {
      throw TranscriptionSessionError.invalidState
    }
    try Task.checkCancellation()

    let microphoneFormat = try microphone.inputFormat()
    let newConverter = try converterFactory(microphoneFormat, runtime.audioFormat)
    let (inputStream, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
    let (eventStream, eventBuilder) = AsyncThrowingStream.makeStream(
      of: TranscriptionEvent.self
    )
    let token = generation

    converter = newConverter
    inputContinuation = inputBuilder
    eventContinuation = eventBuilder
    finalizedText = ""
    volatileText = ""
    resultsError = nil
    phase = .active

    let updates = runtime.updates()
    resultsTask = Task { [weak self] in
      do {
        for try await update in updates {
          guard let self, isCurrent(token) else { return }
          apply(update)
        }
      } catch is CancellationError {
        return
      } catch {
        guard let self, isCurrent(token) else { return }
        resultsError = error
      }
    }

    do {
      try await runtime.start(inputStream)
      guard isCurrent(token, phase: .active) else { throw CancellationError() }
      try Task.checkCancellation()

      try microphone.start { [weak self] buffer in
        guard let self else { return }
        do {
          if let converted = try newConverter.convert(buffer) {
            inputBuilder.yield(AnalyzerInput(buffer: converted))
          }
        } catch {
          inputBuilder.finish()
          eventBuilder.finish(throwing: error)
          Task { @MainActor [weak self] in
            await self?.cancelIfCurrent(token)
          }
        }
      }
      return eventStream
    } catch {
      await failStart(error, token: token)
      throw error
    }
  }

  func finish() async throws {
    guard phase == .active else { return }
    guard let runtime, let converter, let inputContinuation else {
      throw TranscriptionSessionError.invalidState
    }

    let token = generation
    phase = .finishing
    microphone.stop()

    do {
      for buffer in try converter.flush() {
        inputContinuation.yield(AnalyzerInput(buffer: buffer))
      }
      inputContinuation.finish()
      try await runtime.finish()
      await resultsTask?.value

      guard isCurrent(token, phase: .finishing) else { return }
      if let resultsError {
        throw resultsError
      }

      eventContinuation?.yield(.final(combinedTranscript))
      eventContinuation?.finish()
      resetState()
    } catch {
      if isCurrent(token) {
        eventContinuation?.finish(throwing: error)
        await runtime.cancel()
        resetState()
      }
      throw error
    }
  }

  func cancel() async {
    guard phase != .idle else { return }
    let oldRuntime = runtime
    _ = nextGeneration()
    microphone.stop()
    inputContinuation?.finish()
    eventContinuation?.finish()
    resultsTask?.cancel()
    resetState(keepGeneration: true)
    await oldRuntime?.cancel()
  }

  private func apply(_ update: SpeechRecognitionUpdate) {
    let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else {
      // SpeechTranscriber can revoke its current volatile interpretation with
      // an empty result. Never retain or execute the superseded phrase.
      volatileText = ""
      eventContinuation?.yield(.partial(combinedTranscript))
      return
    }

    if update.isFinal {
      finalizedText = joining(finalizedText, text)
      volatileText = ""
    } else {
      volatileText = text
    }
    eventContinuation?.yield(.partial(combinedTranscript))
  }

  private var combinedTranscript: String {
    joining(finalizedText, volatileText)
  }

  private func joining(_ first: String, _ second: String) -> String {
    if first.isEmpty { return second }
    if second.isEmpty { return first }
    return first + " " + second
  }

  private func failStart(_ error: any Error, token: UInt64) async {
    guard isCurrent(token) else { return }
    microphone.stop()
    inputContinuation?.finish()
    eventContinuation?.finish(throwing: error)
    resultsTask?.cancel()
    await runtime?.cancel()
    resetState()
  }

  private func cancelIfCurrent(_ token: UInt64) async {
    guard isCurrent(token) else { return }
    await cancel()
  }

  @discardableResult
  private func nextGeneration() -> UInt64 {
    generation &+= 1
    return generation
  }

  private func isCurrent(_ token: UInt64, phase expectedPhase: Phase? = nil) -> Bool {
    guard generation == token else { return false }
    guard let expectedPhase else { return true }
    return phase == expectedPhase
  }

  private func resetState(keepGeneration: Bool = false) {
    if !keepGeneration {
      _ = nextGeneration()
    }
    phase = .idle
    runtime = nil
    converter = nil
    inputContinuation = nil
    eventContinuation = nil
    resultsTask?.cancel()
    resultsTask = nil
    resultsError = nil
    finalizedText = ""
    volatileText = ""
  }
}
