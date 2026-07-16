import Foundation
import TopherCore

/// The stateful test seam between Topher's UI lifecycle and a speech engine.
///
/// Apple framework types stay behind this boundary. Tests can drive the same
/// push-to-talk state machine with an in-memory event stream.
@MainActor
struct VoiceTranscriptionClient {
  let prepare: () async throws -> Void
  let start: () async throws -> AsyncThrowingStream<TranscriptionEvent, any Error>
  let finish: () async throws -> Void
  let cancel: () async -> Void

  static func live(
    locale: Locale = Locale(identifier: "en_US"),
    contextualStrings: @escaping @MainActor () -> [String] = {
      TranscriptVocabulary.developerDefaults.contextualStrings
    }
  ) -> Self {
    let session = AppleSpeechTranscriptionSession(
      locale: locale,
      contextualStrings: contextualStrings
    )
    return Self(
      prepare: { try await session.prepare() },
      start: { try await session.start() },
      finish: { try await session.finish() },
      cancel: { await session.cancel() }
    )
  }
}
