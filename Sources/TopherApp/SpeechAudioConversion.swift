import AVFAudio
import Foundation

enum SpeechAudioConversionError: Error, Equatable, LocalizedError, Sendable {
  case incompatibleFormats
  case conversionFailed

  var errorDescription: String? {
    switch self {
    case .incompatibleFormats:
      "The microphone audio format cannot be converted for speech recognition."
    case .conversionFailed:
      "Microphone audio conversion failed."
    }
  }
}

protocol SpeechAudioConverting: Sendable {
  func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer?
  func flush() throws -> [AVAudioPCMBuffer]
}

/// Converts microphone buffers without writing audio to disk.
///
/// AVAudioEngine invokes its tap off the main actor. AVAudioConverter is mutable,
/// so all access is serialized by the lock rather than crossing actor boundaries.
final class SpeechAudioConverter: SpeechAudioConverting, @unchecked Sendable {
  private final class InputProvider: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer?
    private let isEndOfStream: Bool
    private var suppliedBuffer = false

    init(buffer: AVAudioPCMBuffer?, isEndOfStream: Bool) {
      self.buffer = buffer
      self.isEndOfStream = isEndOfStream
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
      if let buffer, !suppliedBuffer {
        suppliedBuffer = true
        status.pointee = .haveData
        return buffer
      }

      status.pointee = isEndOfStream ? .endOfStream : .noDataNow
      return nil
    }
  }

  private let converter: AVAudioConverter
  private let outputFormat: AVAudioFormat
  private let outputCapacity: AVAudioFrameCount
  private let lock = NSLock()

  init(inputFormat: AVAudioFormat, outputFormat: AVAudioFormat) throws {
    guard
      inputFormat.sampleRate > 0,
      inputFormat.channelCount > 0,
      outputFormat.sampleRate > 0,
      outputFormat.channelCount > 0,
      let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
    else {
      throw SpeechAudioConversionError.incompatibleFormats
    }

    self.converter = converter
    self.outputFormat = outputFormat
    outputCapacity = max(
      1,
      AVAudioFrameCount(
        ceil(4_096 * outputFormat.sampleRate / inputFormat.sampleRate)
      ) + 8
    )
  }

  func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer? {
    try lock.withLock {
      let scaledCapacity = max(
        1,
        AVAudioFrameCount(
          ceil(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate)
        ) + 8
      )
      return try performConversion(
        capacity: max(outputCapacity, scaledCapacity),
        inputBuffer: buffer,
        isEndOfStream: false
      )
    }
  }

  func flush() throws -> [AVAudioPCMBuffer] {
    try lock.withLock {
      var buffers: [AVAudioPCMBuffer] = []

      // A converter can retain a short resampling tail. Bound the loop so a
      // misbehaving converter cannot hang shortcut release indefinitely.
      for _ in 0..<8 {
        guard
          let buffer = try performConversion(
            capacity: outputCapacity,
            inputBuffer: nil,
            isEndOfStream: true
          )
        else {
          break
        }
        buffers.append(buffer)
      }

      return buffers
    }
  }

  private func performConversion(
    capacity: AVAudioFrameCount,
    inputBuffer: AVAudioPCMBuffer?,
    isEndOfStream: Bool
  ) throws -> AVAudioPCMBuffer? {
    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
    else {
      throw SpeechAudioConversionError.incompatibleFormats
    }

    let inputProvider = InputProvider(buffer: inputBuffer, isEndOfStream: isEndOfStream)
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) {
      _, inputStatus in
      inputProvider.next(status: inputStatus)
    }

    guard conversionError == nil, status != .error else {
      throw SpeechAudioConversionError.conversionFailed
    }

    guard outputBuffer.frameLength > 0 else { return nil }
    return outputBuffer
  }
}
