import XCTest

@testable import TopherCore

final class CommandPolicyTests: XCTestCase {
  private let policy = CommandPolicy()

  func testAllowsRegisteredApplication() {
    XCTAssertEqual(policy.evaluate(.openApplication(.safari)), .allowed)
  }

  func testAllowsRegisteredWebCapabilities() {
    XCTAssertEqual(policy.evaluate(.openWebsite(.youtube)), .allowed)

    let query = SearchQuery("local models")
    XCTAssertNotNil(query)
    if let query {
      XCTAssertEqual(policy.evaluate(.searchWeb(provider: .google, query: query)), .allowed)
    }
  }

  func testDeniesUnsupportedProposal() {
    XCTAssertEqual(
      policy.evaluate(.unsupported),
      .denied(reason: "Topher only executes registered commands.")
    )
  }
}
