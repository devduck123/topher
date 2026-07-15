import Foundation
import XCTest

@testable import TopherApp

@MainActor
final class SpeechAssetPreparationClientTests: XCTestCase {
  func testUnavailableTranscriberStopsBeforeLocaleOrInventoryChecks() async {
    var didCheckLocale = false
    var didCheckInventory = false
    let client = makeClient(
      isAvailable: false,
      supportedLocaleIdentifier: { _ in
        didCheckLocale = true
        return "en_US"
      },
      inventoryStatus: { _ in
        didCheckInventory = true
        return .installed
      }
    )

    let state = await client.readiness()

    XCTAssertEqual(state, .unavailable)
    XCTAssertFalse(didCheckLocale)
    XCTAssertFalse(didCheckInventory)
  }

  func testUnsupportedEnglishLocaleStopsBeforeInventoryCheck() async {
    var requestedIdentifier: String?
    var didCheckInventory = false
    let client = makeClient(
      supportedLocaleIdentifier: { locale in
        requestedIdentifier = locale.identifier
        return nil
      },
      inventoryStatus: { _ in
        didCheckInventory = true
        return .installed
      }
    )

    let state = await client.readiness()

    XCTAssertEqual(state, .unsupportedLocale(requestedIdentifier: "en_US"))
    XCTAssertEqual(requestedIdentifier, "en_US")
    XCTAssertFalse(didCheckInventory)
  }

  func testMapsEveryInventoryStatusToAPreparationState() async {
    let cases: [(SpeechAssetInventoryStatus, SpeechAssetPreparationState)] = [
      (.unsupported, .unsupportedLocale(requestedIdentifier: "en_US")),
      (.supported, .downloadRequired(localeIdentifier: "en_US")),
      (.downloading, .downloading(localeIdentifier: "en_US", progress: nil)),
      (.installed, .ready(localeIdentifier: "en_US")),
    ]

    for (inventoryStatus, expectedState) in cases {
      let client = makeClient(inventoryStatus: { _ in inventoryStatus })

      let state = await client.readiness()
      XCTAssertEqual(state, expectedState)
    }
  }

  func testReadyAssetsDoNotCreateAnInstallationRequest() async throws {
    var installCount = 0
    var states: [SpeechAssetPreparationState] = []
    let client = makeClient(
      inventoryStatus: { _ in .installed },
      installAssets: { _, _ in
        installCount += 1
        return true
      }
    )

    let finalState = try await client.prepare { states.append($0) }

    XCTAssertEqual(finalState, .ready(localeIdentifier: "en_US"))
    XCTAssertEqual(states, [.ready(localeIdentifier: "en_US")])
    XCTAssertEqual(installCount, 0)
  }

  func testInstallsRequiredAssetsReportsProgressAndBecomesReady() async throws {
    var inventoryChecks = 0
    var installedLocaleIdentifier: String?
    var states: [SpeechAssetPreparationState] = []
    let client = makeClient(
      inventoryStatus: { _ in
        defer { inventoryChecks += 1 }
        return inventoryChecks == 0 ? .supported : .installed
      },
      installAssets: { localeIdentifier, reportProgress in
        installedLocaleIdentifier = localeIdentifier
        reportProgress(-0.1)
        reportProgress(0.45)
        reportProgress(1.1)
        return true
      }
    )

    let finalState = try await client.prepare { states.append($0) }

    XCTAssertEqual(installedLocaleIdentifier, "en_US")
    XCTAssertEqual(finalState, .ready(localeIdentifier: "en_US"))
    XCTAssertEqual(
      states,
      [
        .downloadRequired(localeIdentifier: "en_US"),
        .downloading(localeIdentifier: "en_US", progress: 0),
        .downloading(localeIdentifier: "en_US", progress: 0.45),
        .downloading(localeIdentifier: "en_US", progress: 1),
        .ready(localeIdentifier: "en_US"),
      ]
    )
  }

  func testMissingInstallationRequestRefreshesInventoryState() async throws {
    var inventoryChecks = 0
    let client = makeClient(
      inventoryStatus: { _ in
        defer { inventoryChecks += 1 }
        return inventoryChecks == 0 ? .supported : .downloading
      },
      installAssets: { _, _ in false }
    )

    let finalState = try await client.prepare()

    XCTAssertEqual(
      finalState,
      .downloading(localeIdentifier: "en_US", progress: nil)
    )
    XCTAssertEqual(inventoryChecks, 2)
  }

  func testInstallationErrorsPropagateWithoutInventingAReadyState() async {
    struct InstallationError: Error, Equatable {}

    var states: [SpeechAssetPreparationState] = []
    let client = makeClient(
      inventoryStatus: { _ in .supported },
      installAssets: { _, _ in throw InstallationError() }
    )

    do {
      _ = try await client.prepare { states.append($0) }
      XCTFail("Expected installation to fail")
    } catch {
      XCTAssertTrue(error is InstallationError)
    }

    XCTAssertEqual(states, [.downloadRequired(localeIdentifier: "en_US")])
  }

  private func makeClient(
    isAvailable: Bool = true,
    supportedLocaleIdentifier: @escaping (Locale) async -> String? = { _ in "en_US" },
    inventoryStatus: @escaping (String) async -> SpeechAssetInventoryStatus = { _ in
      .installed
    },
    installAssets:
      @escaping (
        String,
        @escaping @MainActor (Double) -> Void
      ) async throws -> Bool = { _, _ in
        XCTFail("Assets should not be installed")
        return false
      }
  ) -> SpeechAssetPreparationClient {
    SpeechAssetPreparationClient(
      environment: SpeechAssetPreparationEnvironment(
        isTranscriberAvailable: { isAvailable },
        supportedLocaleIdentifier: supportedLocaleIdentifier,
        inventoryStatus: inventoryStatus,
        installAssets: installAssets
      )
    )
  }
}
