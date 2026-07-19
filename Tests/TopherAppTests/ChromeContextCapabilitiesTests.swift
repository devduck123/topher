import Foundation
import XCTest

@testable import TopherApp
@testable import TopherCore

@MainActor
final class ChromeContextCapabilitiesTests: XCTestCase {
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
}

private actor ChromeExchangeStub {
  private let tabs: [ChromeBridgeWireTab]
  private let excludedTabCount: Int
  private let activationFailure: ChromeBridgeFailureCode?
  private let responseVersion: Int
  private let mismatchesRequestID: Bool
  private let readDelay: Duration?
  private let activationDelay: Duration?
  private let unexpectedActiveExcludedCount: Int?
  private var receivedRequests: [ChromeBridgeRequest] = []
  private var cancellations: [UUID] = []

  init(
    tabs: [ChromeBridgeWireTab],
    excludedTabCount: Int = 0,
    activationFailure: ChromeBridgeFailureCode? = nil,
    responseVersion: Int = ChromeBridgeRequest.protocolVersion,
    mismatchesRequestID: Bool = false,
    readDelay: Duration? = nil,
    activationDelay: Duration? = nil,
    unexpectedActiveExcludedCount: Int? = nil
  ) {
    self.tabs = tabs
    self.excludedTabCount = excludedTabCount
    self.activationFailure = activationFailure
    self.responseVersion = responseVersion
    self.mismatchesRequestID = mismatchesRequestID
    self.readDelay = readDelay
    self.activationDelay = activationDelay
    self.unexpectedActiveExcludedCount = unexpectedActiveExcludedCount
  }

  func send(_ request: ChromeBridgeRequest) async throws -> ChromeBridgeResponse {
    receivedRequests.append(request)
    let delay = request.operation == .activateTab ? activationDelay : readDelay
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
    case .listTabs:
      return ChromeBridgeResponse(
        version: responseVersion,
        requestID: responseID,
        status: .success,
        tabs: tabs,
        excludedTabCount: excludedTabCount
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
