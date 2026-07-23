import Foundation
import XCTest

@testable import TopherApp
@testable import TopherCore

@MainActor
final class ChromeContextCapabilitiesTests: XCTestCase {
  func testRuntimeOwnershipConstructsLiveBridgeOnlyForPrimaryInstance() {
    var liveFactoryCallCount = 0

    _ = ChromeContextCapabilities.runtime(isPrimary: false) {
      liveFactoryCallCount += 1
      return .unavailable()
    }
    XCTAssertEqual(liveFactoryCallCount, 0)

    _ = ChromeContextCapabilities.runtime(isPrimary: true) {
      liveFactoryCallCount += 1
      return .unavailable()
    }
    XCTAssertEqual(liveFactoryCallCount, 1)
  }

  func testActiveTabReadReturnsBoundedUserVisibleContext() async {
    let stub = ChromeExchangeStub(tabs: [wireTab(title: "Private account — Example")])
    let capability = ChromeActiveTabCapability(client: client(stub))

    let outcome = await capability.execute()

    XCTAssertEqual(
      outcome,
      .succeeded(message: "This Chrome tab is “Private account — Example” on example.com.")
    )
    let operations = await stub.operations()
    XCTAssertEqual(operations, [.getActiveTab])
  }

  func testListReadIsBoundedAndReportsExcludedTabs() async {
    let stub = ChromeExchangeStub(
      tabs: [wireTab(tabID: 1, title: "One"), wireTab(tabID: 2, title: "Two")],
      excludedTabCount: 3
    )
    let capability = ChromeTabListCapability(client: client(stub))

    let outcome = await capability.execute()

    XCTAssertEqual(
      outcome,
      .succeeded(
        message:
          "Open Chrome tabs:\n1. One\n2. Two\n3 tab(s) were excluded by scheme or the list bound. Incognito tabs are intentionally unavailable."
      )
    )
    let maximumTabCounts = await stub.receivedMaximumTabCounts()
    XCTAssertEqual(maximumTabCounts, [25])
  }

  func testActivationUsesExactUniqueMatchAndMutatesExactlyOnce() async throws {
    let now: Int64 = 1_721_000_000_000
    let stub = ChromeExchangeStub(
      tabs: [
        wireTab(tabID: 1, title: "GitHub"),
        wireTab(tabID: 2, title: "Topher", capturedAtMilliseconds: now),
      ]
    )
    let capability = ChromeTabActivationCapability(
      client: client(stub),
      nowMilliseconds: { now }
    )

    let outcome = await capability.execute(try XCTUnwrap(ChromeTabTitleQuery("topher")))

    XCTAssertEqual(outcome, .succeeded(message: "Switched to the Chrome tab “Topher”."))
    let operations = await stub.operations()
    let activationCount = await stub.activationCount()
    let activationTarget = await stub.lastActivationTarget()
    XCTAssertEqual(operations, [.listTabs, .activateTab])
    XCTAssertEqual(activationCount, 1)
    XCTAssertEqual(activationTarget?.tabID, 2)
  }

  func testActivationRefusesAmbiguityBeforeMutation() async throws {
    let now: Int64 = 1_721_000_000_000
    let stub = ChromeExchangeStub(
      tabs: [
        wireTab(tabID: 1, title: "Topher", capturedAtMilliseconds: now),
        wireTab(tabID: 2, title: "TOPHER", capturedAtMilliseconds: now),
      ]
    )
    let capability = ChromeTabActivationCapability(
      client: client(stub),
      nowMilliseconds: { now }
    )

    let outcome = await capability.execute(try XCTUnwrap(ChromeTabTitleQuery("Topher")))

    XCTAssertEqual(
      outcome,
      .failed(
        message:
          "More than one Chrome tab has that exact title. Make the titles unique and try again."
      )
    )
    let operations = await stub.operations()
    let activationCount = await stub.activationCount()
    XCTAssertEqual(operations, [.listTabs])
    XCTAssertEqual(activationCount, 0)
  }

  func testActivationRefusesWhenBoundCannotProveGlobalUniqueness() async throws {
    let now: Int64 = 1_721_000_000_000
    let stub = ChromeExchangeStub(
      tabs: [wireTab(title: "Topher", capturedAtMilliseconds: now)],
      observationWasTruncated: true
    )
    let capability = ChromeTabActivationCapability(
      client: client(stub),
      nowMilliseconds: { now }
    )

    let outcome = await capability.execute(try XCTUnwrap(ChromeTabTitleQuery("Topher")))

    XCTAssertEqual(
      outcome,
      .failed(
        message:
          "Topher couldn't safely check every supported Chrome tab within the activation bound, so it did not switch tabs."
      )
    )
    let operations = await stub.operations()
    let activationCount = await stub.activationCount()
    XCTAssertEqual(operations, [.listTabs])
    XCTAssertEqual(activationCount, 0)
  }

  func testActivationRefusesStaleSnapshotBeforeMutation() async throws {
    let now: Int64 = 1_721_000_010_001
    let stub = ChromeExchangeStub(
      tabs: [wireTab(title: "Topher", capturedAtMilliseconds: now - 5_001)]
    )
    let capability = ChromeTabActivationCapability(
      client: client(stub),
      nowMilliseconds: { now }
    )

    let outcome = await capability.execute(try XCTUnwrap(ChromeTabTitleQuery("Topher")))

    XCTAssertEqual(
      outcome,
      .failed(message: "Chrome's tab snapshot was stale. Ask again to refresh it.")
    )
    let activationCount = await stub.activationCount()
    XCTAssertEqual(activationCount, 0)
  }

  func testExtensionStalenessResponseDoesNotRetryActivation() async throws {
    let now: Int64 = 1_721_000_000_000
    let stub = ChromeExchangeStub(
      tabs: [wireTab(title: "Topher", capturedAtMilliseconds: now)],
      activationFailure: .staleTab
    )
    let capability = ChromeTabActivationCapability(
      client: client(stub),
      nowMilliseconds: { now }
    )

    let outcome = await capability.execute(try XCTUnwrap(ChromeTabTitleQuery("Topher")))

    XCTAssertEqual(
      outcome,
      .failed(
        message: "That Chrome tab changed or closed before activation. Ask again to refresh it.")
    )
    let activationCount = await stub.activationCount()
    XCTAssertEqual(activationCount, 1)
  }

  func testExtensionMutationFailureReportsUnknownOutcomeWithoutRetry() async throws {
    let now: Int64 = 1_721_000_000_000
    let stub = ChromeExchangeStub(
      tabs: [wireTab(title: "Topher", capturedAtMilliseconds: now)],
      activationFailure: .activationOutcomeUnknown
    )
    let capability = ChromeTabActivationCapability(
      client: client(stub),
      nowMilliseconds: { now }
    )

    let outcome = await capability.execute(try XCTUnwrap(ChromeTabTitleQuery("Topher")))

    XCTAssertEqual(
      outcome,
      .failed(
        message:
          "Chrome may have switched tabs, but Topher did not receive confirmation and will not retry automatically."
      )
    )
    let activationCount = await stub.activationCount()
    XCTAssertEqual(activationCount, 1)
  }

  func testLostActivationReplyIsNotRetriedAndReportsUnknownOutcome() async throws {
    let now: Int64 = 1_721_000_000_000
    let stub = ChromeExchangeStub(
      tabs: [wireTab(title: "Topher", capturedAtMilliseconds: now)],
      activationDelay: .seconds(1)
    )
    let client = ChromeBridgeClient(
      exchange: exchange(stub),
      readTimeout: .seconds(1),
      activationTimeout: .milliseconds(10)
    )
    let capability = ChromeTabActivationCapability(
      client: client,
      nowMilliseconds: { now }
    )

    let outcome = await capability.execute(try XCTUnwrap(ChromeTabTitleQuery("Topher")))

    XCTAssertEqual(
      outcome,
      .failed(
        message:
          "Chrome may have switched tabs, but Topher did not receive confirmation and will not retry automatically."
      )
    )
    let activationCount = await stub.activationCount()
    XCTAssertEqual(activationCount, 1)
  }

  func testYouTubeFeedReadStoresAnEphemeralListAndOrdinalOpenConsumesIt() async {
    let now: Int64 = 1_000
    let stub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(capturedAtMilliseconds: now)
    )
    let capabilities = ChromeContextCapabilities(client: client(stub), nowMilliseconds: { now })

    let read = await capabilities.youTubeFeed.execute()
    XCTAssertEqual(read.snapshot?.items.count, 2)
    XCTAssertEqual(
      read.outcome,
      .succeeded(
        message: "I found 2 YouTube recommendations. Open Topher to review the numbered list."
      )
    )

    let opened = await capabilities.openYouTubeVideo.execute(.ordinal(2))
    XCTAssertEqual(
      opened,
      .succeeded(message: "Opened “Swift concurrency, carefully” in the YouTube tab.")
    )
    let openCount = await stub.youTubeOpenCount()
    let openTarget = await stub.lastYouTubeOpenTarget()
    XCTAssertEqual(openCount, 1)
    XCTAssertEqual(openTarget?.videoID.value, "ZYX987abc_-")

    let replay = await capabilities.openYouTubeVideo.execute(.ordinal(2))
    XCTAssertEqual(
      replay,
      .failed(
        message: "Ask “What’s on my YouTube feed?” first, then use the numbered list promptly."
      )
    )
    let replayOpenCount = await stub.youTubeOpenCount()
    XCTAssertEqual(replayOpenCount, 1)
  }

  func testYouTubeTitleSelectionUsesNormalizedUniqueMatchAndRefusesAmbiguity() async throws {
    let now: Int64 = 1_000
    let uniqueStub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(capturedAtMilliseconds: now)
    )
    let unique = ChromeContextCapabilities(client: client(uniqueStub), nowMilliseconds: { now })
    _ = await unique.youTubeFeed.execute()
    let query = try XCTUnwrap(YouTubeVideoTitleQuery("swift concurrency carefully"))
    let uniqueOutcome = await unique.openYouTubeVideo.execute(.title(query))
    XCTAssertEqual(
      uniqueOutcome,
      .succeeded(message: "Opened “Swift concurrency, carefully” in the YouTube tab.")
    )

    let ambiguousStub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(
        capturedAtMilliseconds: now,
        titles: ["Same title", "SAME TITLE"]
      )
    )
    let ambiguous = ChromeContextCapabilities(
      client: client(ambiguousStub),
      nowMilliseconds: { now }
    )
    _ = await ambiguous.youTubeFeed.execute()
    let ambiguousQuery = try XCTUnwrap(YouTubeVideoTitleQuery("same title"))
    let ambiguousOutcome = await ambiguous.openYouTubeVideo.execute(.title(ambiguousQuery))
    XCTAssertEqual(
      ambiguousOutcome,
      .failed(message: "More than one listed YouTube video has that title. Use its number.")
    )
    let ambiguousOpenCount = await ambiguousStub.youTubeOpenCount()
    XCTAssertEqual(ambiguousOpenCount, 0)
  }

  func testYouTubeTitleSelectionUsesSeparateCompletenessAndRefusesExpiredSnapshots() async throws {
    let now: Int64 = 1_000
    let boundedStub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(
        capturedAtMilliseconds: now,
        presentationWasTruncated: true,
        titleObservationWasComplete: true
      )
    )
    let bounded = ChromeContextCapabilities(
      client: client(boundedStub),
      nowMilliseconds: { now }
    )
    _ = await bounded.youTubeFeed.execute()
    let boundedQuery = try XCTUnwrap(
      YouTubeVideoTitleQuery("Local-first Mac assistants")
    )
    let boundedOutcome = await bounded.openYouTubeVideo.execute(.title(boundedQuery))
    XCTAssertEqual(
      boundedOutcome,
      .succeeded(message: "Opened “Local-first Mac assistants” in the YouTube tab.")
    )

    let incompleteStub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(
        capturedAtMilliseconds: now,
        presentationWasTruncated: true,
        titleObservationWasComplete: false
      )
    )
    let incomplete = ChromeContextCapabilities(
      client: client(incompleteStub),
      nowMilliseconds: { now }
    )
    _ = await incomplete.youTubeFeed.execute()
    let incompleteQuery = try XCTUnwrap(
      YouTubeVideoTitleQuery("Local-first Mac assistants")
    )
    let incompleteOutcome = await incomplete.openYouTubeVideo.execute(.title(incompleteQuery))
    XCTAssertEqual(
      incompleteOutcome,
      .failed(
        message:
          "Topher could not safely check every visible title. Use the video’s number or ask again."
      )
    )

    let expiredStub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(capturedAtMilliseconds: now)
    )
    let expired = ChromeContextCapabilities(
      client: client(expiredStub),
      nowMilliseconds: { now + 90_001 }
    )
    let expiredRead = await expired.youTubeFeed.execute()
    XCTAssertEqual(
      expiredRead.outcome,
      .failed(message: "The YouTube feed snapshot was already stale. Ask again.")
    )
    XCTAssertNil(expiredRead.snapshot)
    let expiredOutcome = await expired.openYouTubeVideo.execute(.ordinal(1))
    XCTAssertEqual(
      expiredOutcome,
      .failed(
        message: "Ask “What’s on my YouTube feed?” first, then use the numbered list promptly."
      )
    )
    let expiredOpenCount = await expiredStub.youTubeOpenCount()
    XCTAssertEqual(expiredOpenCount, 0)
  }

  func testYouTubePermissionAndPageFailuresAreActionableAndClearSession() async {
    let stub = ChromeExchangeStub(
      tabs: [],
      youTubeReadFailure: .youTubePermissionRequired
    )
    let capabilities = ChromeContextCapabilities(client: client(stub))
    let read = await capabilities.youTubeFeed.execute()
    XCTAssertNil(read.snapshot)
    XCTAssertEqual(
      read.outcome,
      .failed(
        message:
          "Grant YouTube access from the Topher extension button in Chrome, then ask again. You can remove access there at any time."
      )
    )

    let unsupported = ChromeExchangeStub(
      tabs: [],
      youTubeReadFailure: .unsupportedYouTubePage
    )
    let unsupportedOutcome = await ChromeContextCapabilities(
      client: client(unsupported)
    ).youTubeFeed.execute().outcome
    XCTAssertEqual(
      unsupportedOutcome,
      .failed(message: "Open YouTube Home in the active Chrome tab, then ask again.")
    )
  }

  func testYouTubeOpenChangedAndUnknownOutcomesNeverRetry() async {
    let now: Int64 = 1_000
    let changedStub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(capturedAtMilliseconds: now),
      youTubeOpenFailure: .youTubeFeedChanged
    )
    let changed = ChromeContextCapabilities(
      client: client(changedStub),
      nowMilliseconds: { now }
    )
    _ = await changed.youTubeFeed.execute()
    let changedOutcome = await changed.openYouTubeVideo.execute(.ordinal(1))
    XCTAssertEqual(
      changedOutcome,
      .failed(message: "The YouTube feed changed. Ask “What’s on my YouTube feed?” again.")
    )
    let changedOpenCount = await changedStub.youTubeOpenCount()
    XCTAssertEqual(changedOpenCount, 1)

    let timeoutStub = ChromeExchangeStub(
      tabs: [],
      youTubeFeed: wireYouTubeFeed(capturedAtMilliseconds: now),
      activationDelay: .seconds(1)
    )
    let timeoutClient = ChromeBridgeClient(
      exchange: exchange(timeoutStub),
      feedReadTimeout: .seconds(1),
      activationTimeout: .milliseconds(10)
    )
    let timeout = ChromeContextCapabilities(client: timeoutClient, nowMilliseconds: { now })
    _ = await timeout.youTubeFeed.execute()
    let timeoutOutcome = await timeout.openYouTubeVideo.execute(.ordinal(1))
    XCTAssertEqual(
      timeoutOutcome,
      .failed(
        message:
          "Chrome may have opened the video, but Topher did not receive confirmation and will not retry automatically. Ask for the feed again before another open."
      )
    )
    let timeoutOpenCount = await timeoutStub.youTubeOpenCount()
    XCTAssertEqual(timeoutOpenCount, 1)
  }

  func testClientRejectsMismatchedVersionAndRequestID() async {
    let versionStub = ChromeExchangeStub(
      tabs: [wireTab()],
      responseVersion: ChromeBridgeRequest.protocolVersion + 1
    )
    await assertThrowsErrorAsync(try await client(versionStub).activeTab()) { error in
      XCTAssertEqual(error as? ChromeContextError, .versionMismatch)
    }

    let identifierStub = ChromeExchangeStub(tabs: [wireTab()], mismatchesRequestID: true)
    await assertThrowsErrorAsync(try await client(identifierStub).activeTab()) { error in
      XCTAssertEqual(error as? ChromeContextError, .malformedResponse)
    }
  }

  func testClientRejectsUnexpectedFieldsInAnActiveTabResponse() async {
    let stub = ChromeExchangeStub(
      tabs: [wireTab()],
      unexpectedActiveExcludedCount: 1
    )
    await assertThrowsErrorAsync(try await client(stub).activeTab()) { error in
      XCTAssertEqual(error as? ChromeContextError, .malformedResponse)
    }
  }

  func testClientRejectsMalformedOrMixedYouTubeFeedResponses() async {
    let now: Int64 = 1_000
    let oversized = wireYouTubeFeed(
      capturedAtMilliseconds: now,
      titles: [String(repeating: "a", count: 513)]
    )
    let malformedClient = ChromeBridgeClient(
      exchange: ChromeBridgeExchange(send: { request in
        ChromeBridgeResponse(
          requestID: request.requestID,
          status: .success,
          youTubeFeed: oversized
        )
      })
    )
    do {
      _ = try await malformedClient.youTubeFeed()
      XCTFail("Expected malformed feed data to fail closed")
    } catch {
      XCTAssertEqual(error as? ChromeContextError, .malformedResponse)
    }

    let validFeed = wireYouTubeFeed(capturedAtMilliseconds: now)
    let mixedClient = ChromeBridgeClient(
      exchange: ChromeBridgeExchange(send: { request in
        ChromeBridgeResponse(
          requestID: request.requestID,
          status: .success,
          tabs: [],
          youTubeFeed: validFeed,
          excludedTabCount: 0,
          observationWasTruncated: false
        )
      })
    )
    do {
      _ = try await mixedClient.youTubeFeed()
      XCTFail("Expected mixed response fields to fail closed")
    } catch {
      XCTAssertEqual(error as? ChromeContextError, .malformedResponse)
    }
  }

  func testClientRejectsListWithoutCompletenessMetadata() async {
    let stub = ChromeExchangeStub(
      tabs: [wireTab()],
      observationWasTruncated: nil
    )
    await assertThrowsErrorAsync(try await client(stub).listTabs(maximumCount: 25)) { error in
      XCTAssertEqual(error as? ChromeContextError, .malformedResponse)
    }
  }

  func testIntegrationReadinessDistinguishesConnectionFromOptionalPermission() async {
    let ready = ChromeContextCapabilities(
      client: client(ChromeExchangeStub(tabs: [], integrationPermissionGranted: true))
    )
    let readyResult = await ready.integrationReadiness()
    XCTAssertEqual(readyResult, .ready)

    let permissionRequired = ChromeContextCapabilities(
      client: client(ChromeExchangeStub(tabs: [], integrationPermissionGranted: false))
    )
    let permissionRequiredResult = await permissionRequired.integrationReadiness()
    XCTAssertEqual(permissionRequiredResult, .youtubeAccessRequired)

    let malformed = ChromeContextCapabilities(
      client: client(ChromeExchangeStub(tabs: [], integrationPermissionGranted: nil))
    )
    let malformedResult = await malformed.integrationReadiness()
    XCTAssertEqual(malformedResult, .disconnected)
  }

  func testDisconnectClassificationPreservesUnknownActivationOutcome() {
    XCTAssertEqual(
      chromeBridgeDisconnectError(operation: .activateTab, wasSent: true),
      .activationOutcomeUnknown
    )
    XCTAssertEqual(
      chromeBridgeDisconnectError(operation: .activateTab, wasSent: false),
      .bridgeUnavailable
    )
    XCTAssertEqual(
      chromeBridgeDisconnectError(operation: .listTabs, wasSent: true),
      .bridgeUnavailable
    )
    XCTAssertEqual(
      chromeBridgeDisconnectError(operation: .openYouTubeVideo, wasSent: true),
      .navigationOutcomeUnknown
    )
    XCTAssertEqual(
      chromeBridgeDisconnectError(operation: .openYouTubeVideo, wasSent: false),
      .bridgeUnavailable
    )
  }

  func testCancellationSendsTypedCancellationAndReturnsWithoutReplyReuse() async {
    let stub = ChromeExchangeStub(tabs: [wireTab()], readDelay: .seconds(1))
    let client = ChromeBridgeClient(
      exchange: exchange(stub),
      readTimeout: .seconds(2)
    )

    let task = Task { try await client.activeTab() }
    try? await Task.sleep(for: .milliseconds(10))
    task.cancel()
    _ = try? await task.value
    try? await Task.sleep(for: .milliseconds(10))

    let cancellationCount = await stub.canceledRequestIDs().count
    XCTAssertEqual(cancellationCount, 1)
  }

  func testClientRejectsWorkAboveTheConcurrentRequestBound() async {
    let stub = ChromeExchangeStub(tabs: [wireTab()], readDelay: .milliseconds(100))
    let client = ChromeBridgeClient(
      exchange: exchange(stub),
      readTimeout: .seconds(1),
      maximumConcurrentRequests: 1
    )

    let first = Task { try await client.activeTab() }
    try? await Task.sleep(for: .milliseconds(10))
    await assertThrowsErrorAsync(try await client.activeTab()) { error in
      XCTAssertEqual(error as? ChromeContextError, .busy)
    }
    _ = try? await first.value
  }

  private func client(_ stub: ChromeExchangeStub) -> ChromeBridgeClient {
    ChromeBridgeClient(exchange: exchange(stub))
  }

  private func exchange(_ stub: ChromeExchangeStub) -> ChromeBridgeExchange {
    ChromeBridgeExchange(
      send: { request in try await stub.send(request) },
      cancel: { requestID in await stub.cancel(requestID) }
    )
  }

  private func wireTab(
    tabID: Int = 7,
    title: String = "Example",
    capturedAtMilliseconds: Int64 = 1_721_000_000_000
  ) -> ChromeBridgeWireTab {
    ChromeBridgeWireTab(
      tabID: tabID,
      windowID: 3,
      index: tabID,
      active: tabID == 7,
      title: title,
      url: "https://example.com/private/path",
      fingerprint: String(repeating: "a", count: 64),
      capturedAtMilliseconds: capturedAtMilliseconds
    )
  }

  private func wireYouTubeFeed(
    capturedAtMilliseconds: Int64,
    presentationWasTruncated: Bool = false,
    titleObservationWasComplete: Bool = true,
    titleMatchesAreUnique: Bool = true,
    titles: [String] = ["Local-first Mac assistants", "Swift concurrency, carefully"]
  ) -> ChromeBridgeWireYouTubeFeedSnapshot {
    let videoIDs = ["abcDEF123_-", "ZYX987abc_-"]
    let channels = ["Example Channel", "Sample Engineering"]
    let observationCharacters = ["c", "d"]
    return ChromeBridgeWireYouTubeFeedSnapshot(
      sourceTabID: 7,
      sourceWindowID: 3,
      sourceURL: "https://www.youtube.com/",
      sourceFingerprint: String(repeating: "a", count: 64),
      feedObservationID: String(repeating: "b", count: 64),
      capturedAtMilliseconds: capturedAtMilliseconds,
      expiresAtMilliseconds: capturedAtMilliseconds + 90_000,
      presentationWasTruncated: presentationWasTruncated,
      titleObservationWasComplete: titleObservationWasComplete,
      items: titles.enumerated().map { index, title in
        ChromeBridgeWireYouTubeFeedItem(
          position: index + 1,
          videoID: videoIDs[index],
          title: title,
          channel: channels[index],
          observationID: String(repeating: observationCharacters[index], count: 64),
          titleMatchIsUnique: titleMatchesAreUnique
        )
      }
    )
  }
}

private actor ChromeExchangeStub {
  private let tabs: [ChromeBridgeWireTab]
  private let excludedTabCount: Int
  private let observationWasTruncated: Bool?
  private let activationFailure: ChromeBridgeFailureCode?
  private let youTubeFeed: ChromeBridgeWireYouTubeFeedSnapshot?
  private let youTubeReadFailure: ChromeBridgeFailureCode?
  private let youTubeOpenFailure: ChromeBridgeFailureCode?
  private let responseVersion: Int
  private let mismatchesRequestID: Bool
  private let readDelay: Duration?
  private let activationDelay: Duration?
  private let unexpectedActiveExcludedCount: Int?
  private let integrationPermissionGranted: Bool?
  private var receivedRequests: [ChromeBridgeRequest] = []
  private var cancellations: [UUID] = []

  init(
    tabs: [ChromeBridgeWireTab],
    excludedTabCount: Int = 0,
    observationWasTruncated: Bool? = false,
    activationFailure: ChromeBridgeFailureCode? = nil,
    youTubeFeed: ChromeBridgeWireYouTubeFeedSnapshot? = nil,
    youTubeReadFailure: ChromeBridgeFailureCode? = nil,
    youTubeOpenFailure: ChromeBridgeFailureCode? = nil,
    responseVersion: Int = ChromeBridgeRequest.protocolVersion,
    mismatchesRequestID: Bool = false,
    readDelay: Duration? = nil,
    activationDelay: Duration? = nil,
    unexpectedActiveExcludedCount: Int? = nil,
    integrationPermissionGranted: Bool? = true
  ) {
    self.tabs = tabs
    self.excludedTabCount = excludedTabCount
    self.observationWasTruncated = observationWasTruncated
    self.activationFailure = activationFailure
    self.youTubeFeed = youTubeFeed
    self.youTubeReadFailure = youTubeReadFailure
    self.youTubeOpenFailure = youTubeOpenFailure
    self.responseVersion = responseVersion
    self.mismatchesRequestID = mismatchesRequestID
    self.readDelay = readDelay
    self.activationDelay = activationDelay
    self.unexpectedActiveExcludedCount = unexpectedActiveExcludedCount
    self.integrationPermissionGranted = integrationPermissionGranted
  }

  func send(_ request: ChromeBridgeRequest) async throws -> ChromeBridgeResponse {
    receivedRequests.append(request)
    let delay =
      request.operation == .activateTab || request.operation == .openYouTubeVideo
      ? activationDelay : readDelay
    if let delay {
      try await Task.sleep(for: delay)
    }

    let responseID = mismatchesRequestID ? UUID() : request.requestID
    switch request.operation {
    case .getActiveTab:
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success,
        tab: tabs.first,
        excludedTabCount: unexpectedActiveExcludedCount
      )
    case .getIntegrationStatus:
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success,
        youTubePermissionGranted: integrationPermissionGranted
      )
    case .listTabs:
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success,
        tabs: tabs,
        excludedTabCount: excludedTabCount,
        observationWasTruncated: observationWasTruncated
      )
    case .activateTab:
      if let activationFailure {
        return ChromeBridgeResponse(
          version: responseVersion,
          requestID: responseID,
          status: .failure,
          failureCode: activationFailure
        )
      }
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success
      )
    case .getYouTubeFeed:
      if let youTubeReadFailure {
        return ChromeBridgeResponse(
          version: responseVersion,
          requestID: responseID,
          status: .failure,
          failureCode: youTubeReadFailure
        )
      }
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success,
        youTubeFeed: youTubeFeed
      )
    case .openYouTubeVideo:
      if let youTubeOpenFailure {
        return ChromeBridgeResponse(
          version: responseVersion,
          requestID: responseID,
          status: .failure,
          failureCode: youTubeOpenFailure
        )
      }
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success
      )
    case .cancel:
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success
      )
    }
  }

  func cancel(_ requestID: UUID) {
    cancellations.append(requestID)
  }

  func operations() -> [ChromeBridgeOperation] {
    receivedRequests.map(\.operation)
  }

  func receivedMaximumTabCounts() -> [Int] {
    receivedRequests.compactMap(\.maximumTabCount)
  }

  func activationCount() -> Int {
    receivedRequests.filter { $0.operation == .activateTab }.count
  }

  func lastActivationTarget() -> ChromeTabActivationTarget? {
    receivedRequests.last(where: { $0.operation == .activateTab })?.target
  }

  func youTubeOpenCount() -> Int {
    receivedRequests.filter { $0.operation == .openYouTubeVideo }.count
  }

  func lastYouTubeOpenTarget() -> YouTubeVideoOpenTarget? {
    receivedRequests.last(where: { $0.operation == .openYouTubeVideo })?.youTubeTarget
  }

  func canceledRequestIDs() -> [UUID] {
    cancellations
  }
}

@MainActor
private func assertThrowsErrorAsync<T>(
  _ expression: @autoclosure () async throws -> T,
  _ errorHandler: (Error) -> Void,
  file: StaticString = #filePath,
  line: UInt = #line
) async {
  do {
    _ = try await expression()
    XCTFail("Expected expression to throw", file: file, line: line)
  } catch {
    errorHandler(error)
  }
}
