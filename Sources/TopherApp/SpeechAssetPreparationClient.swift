import Foundation
import Speech

enum SpeechAssetInventoryStatus: Equatable, Sendable {
  case unsupported
  case supported
  case downloading
  case installed
}

enum SpeechAssetPreparationState: Equatable, Sendable {
  case unavailable
  case unsupportedLocale(requestedIdentifier: String)
  case downloadRequired(localeIdentifier: String)
  case downloading(localeIdentifier: String, progress: Double?)
  case ready(localeIdentifier: String)
}

/// The test seam around `SpeechTranscriber` and `AssetInventory`.
@MainActor
struct SpeechAssetPreparationEnvironment {
  let isTranscriberAvailable: () -> Bool
  let supportedLocaleIdentifier: (Locale) async -> String?
  let inventoryStatus: (String) async -> SpeechAssetInventoryStatus
  let installAssets: (String, @escaping @MainActor (Double) -> Void) async throws -> Bool

  static let live = Self(
    isTranscriberAvailable: {
      SpeechTranscriber.isAvailable
    },
    supportedLocaleIdentifier: { requestedLocale in
      await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale)?.identifier
    },
    inventoryStatus: { localeIdentifier in
      let transcriber = SpeechTranscriber(
        locale: Locale(identifier: localeIdentifier),
        preset: .progressiveTranscription
      )

      return switch await AssetInventory.status(forModules: [transcriber]) {
      case .unsupported:
        .unsupported
      case .supported:
        .supported
      case .downloading:
        .downloading
      case .installed:
        .installed
      @unknown default:
        .unsupported
      }
    },
    installAssets: { localeIdentifier, reportProgress in
      let transcriber = SpeechTranscriber(
        locale: Locale(identifier: localeIdentifier),
        preset: .progressiveTranscription
      )
      guard
        let request = try await AssetInventory.assetInstallationRequest(
          supporting: [transcriber]
        )
      else {
        return false
      }

      let observation = request.progress.observe(
        \.fractionCompleted,
        options: [.initial, .new]
      ) { progress, _ in
        let fractionCompleted = progress.fractionCompleted
        Task { @MainActor in
          reportProgress(fractionCompleted)
        }
      }
      defer { observation.invalidate() }

      try await request.downloadAndInstall()
      reportProgress(1)
      return true
    }
  )
}

@MainActor
struct SpeechAssetPreparationClient {
  static let requestedLocaleIdentifier = "en_US"

  private let environment: SpeechAssetPreparationEnvironment

  init(environment: SpeechAssetPreparationEnvironment? = nil) {
    self.environment = environment ?? .live
  }

  /// Checks availability without starting an asset download.
  func readiness() async -> SpeechAssetPreparationState {
    guard environment.isTranscriberAvailable() else {
      return .unavailable
    }

    let requestedLocale = Locale(identifier: Self.requestedLocaleIdentifier)
    guard
      let supportedLocaleIdentifier = await environment.supportedLocaleIdentifier(requestedLocale)
    else {
      return .unsupportedLocale(requestedIdentifier: Self.requestedLocaleIdentifier)
    }

    return await readiness(for: supportedLocaleIdentifier)
  }

  /// Installs the fixed `en_US` progressive-transcription assets when needed.
  ///
  /// `stateChanged` receives bounded, query-free state suitable for UI. It is
  /// never called with raw framework errors or speech content.
  func prepare(
    stateChanged: @escaping @MainActor (SpeechAssetPreparationState) -> Void = { _ in }
  ) async throws -> SpeechAssetPreparationState {
    let initialState = await readiness()
    stateChanged(initialState)

    let localeIdentifier: String
    switch initialState {
    case .downloadRequired(let identifier), .downloading(let identifier, _):
      localeIdentifier = identifier
    case .unavailable, .unsupportedLocale, .ready:
      return initialState
    }

    let didCreateRequest = try await environment.installAssets(localeIdentifier) { progress in
      stateChanged(
        .downloading(
          localeIdentifier: localeIdentifier,
          progress: min(max(progress, 0), 1)
        )
      )
    }

    // A nil installation request can mean another process completed or owns
    // the same installation. Re-read AssetInventory instead of guessing.
    guard didCreateRequest else {
      let refreshedState = await readiness(for: localeIdentifier)
      stateChanged(refreshedState)
      return refreshedState
    }

    let finalState = await readiness(for: localeIdentifier)
    stateChanged(finalState)
    return finalState
  }

  private func readiness(for localeIdentifier: String) async -> SpeechAssetPreparationState {
    switch await environment.inventoryStatus(localeIdentifier) {
    case .unsupported:
      .unsupportedLocale(requestedIdentifier: Self.requestedLocaleIdentifier)
    case .supported:
      .downloadRequired(localeIdentifier: localeIdentifier)
    case .downloading:
      .downloading(localeIdentifier: localeIdentifier, progress: nil)
    case .installed:
      .ready(localeIdentifier: localeIdentifier)
    }
  }
}
