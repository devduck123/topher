import AVFAudio
import Speech
import XCTest

@testable import TopherApp

@MainActor
final class SpeechTranscriptionSessionTests: XCTestCase {
  func testPublishesCompletePartialAndFinalTranscripts() async throws {
    let runtime = RuntimeProbe()
    let capture = CaptureProbe()
    let session = makeSession(runtime: runtime, capture: capture)

    try await session.prepare()
    let stream = try await session.start()
    let collected = Task { try await collect(stream) }

    runtime.yield(.init(text: "Open", isFinal: false))
    runtime.yield(.init(text: "Open", isFinal: true))
    runtime.yield(.init(text: "Safari", isFinal: false))
    try await session.finish()

    let events = try await collected.value
    XCTAssertEqual(
      events,
      [
        .partial("Open"),
        .partial("Open"),
        .partial("Open Safari"),
        .final("Open Safari"),
      ]
    )
    XCTAssertEqual(runtime.prepareCount, 1)
    XCTAssertEqual(runtime.startCount, 1)
    XCTAssertEqual(runtime.finishCount, 1)
    XCTAssertEqual(capture.startCount, 1)
    XCTAssertEqual(capture.stopCount, 1)
  }

  func testEmptyUpdateClearsVolatilePartialBeforeFinalization() async throws {
    let runtime = RuntimeProbe()
    let session = makeSession(runtime: runtime, capture: CaptureProbe())

    try await session.prepare()
    let stream = try await session.start()
    let collected = Task { try await collect(stream) }

    runtime.yield(.init(text: "Open Mail", isFinal: false))
    runtime.yield(.init(text: "", isFinal: false))
    try await session.finish()

    let events = try await collected.value
    XCTAssertEqual(
      events,
      [
        .partial("Open Mail"),
        .partial(""),
        .final(""),
      ]
    )
  }

  func testFinishAndCancelAreIdempotent() async throws {
    let finishedRuntime = RuntimeProbe()
    let finishedSession = makeSession(runtime: finishedRuntime, capture: CaptureProbe())
    try await finishedSession.prepare()
    _ = try await finishedSession.start()

    try await finishedSession.finish()
    try await finishedSession.finish()

    XCTAssertEqual(finishedRuntime.finishCount, 1)
    XCTAssertEqual(finishedRuntime.cancelCount, 0)

    let cancelledRuntime = RuntimeProbe()
    let cancelledSession = makeSession(runtime: cancelledRuntime, capture: CaptureProbe())
    try await cancelledSession.prepare()
    _ = try await cancelledSession.start()

    await cancelledSession.cancel()
    await cancelledSession.cancel()

    XCTAssertEqual(cancelledRuntime.finishCount, 0)
    XCTAssertEqual(cancelledRuntime.cancelCount, 1)
  }

  func testCancelledGenerationCannotPublishLateResultsIntoNextHold() async throws {
    let oldRuntime = RuntimeProbe()
    let newRuntime = RuntimeProbe()
    let factory = RuntimeFactoryProbe(runtimes: [oldRuntime, newRuntime])
    let session = AppleSpeechTranscriptionSession(
      runtimeFactory: { try factory.next() },
      microphone: CaptureProbe().client,
      converterFactory: { _, _ in PassthroughConverter() }
    )

    try await session.prepare()
    let oldStream = try await session.start()
    await session.cancel()
    oldRuntime.yield(.init(text: "Open Mail", isFinal: true))

    try await session.prepare()
    let newStream = try await session.start()
    let collected = Task { try await collect(newStream) }
    newRuntime.yield(.init(text: "Open Safari", isFinal: true))
    try await session.finish()

    let oldEvents = try await collect(oldStream)
    let newEvents = try await collected.value
    XCTAssertTrue(oldEvents.isEmpty)
    XCTAssertEqual(newEvents.last, .final("Open Safari"))
    XCTAssertFalse(newEvents.contains(.partial("Open Mail")))
  }

  func testCapturedBufferIsForwardedAsAnalyzerInput() async throws {
    let runtime = RuntimeProbe()
    let capture = CaptureProbe()
    let session = makeSession(runtime: runtime, capture: capture)
    let buffer = try generatedBuffer(format: capture.format)

    try await session.prepare()
    _ = try await session.start()
    capture.emit(buffer)
    await Task.yield()
    try await session.finish()

    XCTAssertEqual(runtime.receivedInputCount, 1)
  }

  private func makeSession(
    runtime: RuntimeProbe,
    capture: CaptureProbe
  ) -> AppleSpeechTranscriptionSession {
    AppleSpeechTranscriptionSession(
      runtimeFactory: { runtime.client },
      microphone: capture.client,
      converterFactory: { _, _ in PassthroughConverter() }
    )
  }

  private func generatedBuffer(format: AVAudioFormat) throws -> AVAudioPCMBuffer {
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
    buffer.frameLength = 64
    return buffer
  }
}

private func collect(
  _ stream: AsyncThrowingStream<TranscriptionEvent, any Error>
) async throws -> [TranscriptionEvent] {
  var events: [TranscriptionEvent] = []
  for try await event in stream {
    events.append(event)
  }
  return events
}

private struct PassthroughConverter: SpeechAudioConverting {
  func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
    buffer
  }

  func flush() throws -> [AVAudioPCMBuffer] {
    []
  }
}

@MainActor
private final class RuntimeProbe {
  let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 16_000,
    channels: 1,
    interleaved: false
  )!

  private let stream: AsyncThrowingStream<SpeechRecognitionUpdate, any Error>
  private let continuation: AsyncThrowingStream<SpeechRecognitionUpdate, any Error>.Continuation
  private var inputTask: Task<Void, Never>?
  private(set) var prepareCount = 0
  private(set) var startCount = 0
  private(set) var finishCount = 0
  private(set) var cancelCount = 0
  private(set) var receivedInputCount = 0

  init() {
    (stream, continuation) = AsyncThrowingStream.makeStream(of: SpeechRecognitionUpdate.self)
  }

  var client: SpeechAnalysisRuntime {
    SpeechAnalysisRuntime(
      audioFormat: format,
      updates: { self.stream },
      prepare: { self.prepareCount += 1 },
      start: { input in
        self.startCount += 1
        self.inputTask = Task {
          for await _ in input {
            self.receivedInputCount += 1
          }
        }
      },
      finish: {
        self.finishCount += 1
        self.continuation.finish()
        await self.inputTask?.value
      },
      cancel: {
        self.cancelCount += 1
        self.continuation.finish()
        self.inputTask?.cancel()
      }
    )
  }

  func yield(_ update: SpeechRecognitionUpdate) {
    continuation.yield(update)
  }
}

@MainActor
private final class RuntimeFactoryProbe {
  private var runtimes: [RuntimeProbe]

  init(runtimes: [RuntimeProbe]) {
    self.runtimes = runtimes
  }

  func next() throws -> SpeechAnalysisRuntime {
    guard !runtimes.isEmpty else {
      throw TranscriptionSessionError.invalidState
    }
    return runtimes.removeFirst().client
  }
}

private final class CaptureProbe: @unchecked Sendable {
  let format = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 48_000,
    channels: 1,
    interleaved: false
  )!

  private let lock = NSLock()
  private var receive: (@Sendable (AVAudioPCMBuffer) -> Void)?
  private(set) var startCount = 0
  private(set) var stopCount = 0

  @MainActor
  var client: MicrophoneCapture {
    MicrophoneCapture(
      inputFormat: { self.format },
      start: { receive in
        self.lock.withLock {
          self.receive = receive
          self.startCount += 1
        }
      },
      stop: {
        self.lock.withLock {
          self.receive = nil
          self.stopCount += 1
        }
      }
    )
  }

  func emit(_ buffer: AVAudioPCMBuffer) {
    let callback = lock.withLock { receive }
    callback?(buffer)
  }
}
