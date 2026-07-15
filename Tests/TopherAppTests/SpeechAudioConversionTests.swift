import AVFAudio
import XCTest

@testable import TopherApp

final class SpeechAudioConversionTests: XCTestCase {
  func testConvertsGeneratedStereoFloatPCMToMonoInt16() throws {
    let inputFormat = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
      )
    )
    let outputFormat = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
      )
    )
    let input = try XCTUnwrap(
      AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 480)
    )
    input.frameLength = 480

    let channels = try XCTUnwrap(input.floatChannelData)
    for frame in 0..<Int(input.frameLength) {
      let sample = Float(sin(Double(frame) * 2 * .pi / 48)) * 0.5
      channels[0][frame] = sample
      channels[1][frame] = sample
    }

    let converter = try SpeechAudioConverter(
      inputFormat: inputFormat,
      outputFormat: outputFormat
    )
    let converted = try XCTUnwrap(converter.convert(input))

    XCTAssertEqual(converted.format.commonFormat, .pcmFormatInt16)
    XCTAssertEqual(converted.format.sampleRate, 16_000)
    XCTAssertEqual(converted.format.channelCount, 1)
    XCTAssertGreaterThan(converted.frameLength, 0)
    XCTAssertLessThanOrEqual(converted.frameLength, 168)
    let samples = try XCTUnwrap(converted.int16ChannelData)
    XCTAssertTrue((0..<Int(converted.frameLength)).contains { samples[0][$0] != 0 })
  }

  func testRejectsAnInvalidOutputFormat() throws {
    let inputFormat = try XCTUnwrap(
      AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
      )
    )
    let invalidOutput = AVAudioFormat()

    XCTAssertThrowsError(
      try SpeechAudioConverter(inputFormat: inputFormat, outputFormat: invalidOutput)
    ) { error in
      XCTAssertEqual(error as? SpeechAudioConversionError, .incompatibleFormats)
    }
  }
}
