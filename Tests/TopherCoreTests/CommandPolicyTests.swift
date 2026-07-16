import XCTest

@testable import TopherCore

final class CommandPolicyTests: XCTestCase {
  private let policy = CommandPolicy()

  func testAllowsRegisteredApplication() {
    XCTAssertEqual(policy.evaluate(.openApplication(.safari)), .allowed)
  }

  func testAllowsRegisteredWebCapabilities() {
    XCTAssertEqual(policy.evaluate(.openWebsite(.youtube)), .allowed)
    XCTAssertEqual(policy.evaluate(.openBrowserRoute(.chromeExtensions)), .allowed)

    let query = SearchQuery("local models")
    XCTAssertNotNil(query)
    if let query {
      XCTAssertEqual(policy.evaluate(.searchWeb(provider: .google, query: query)), .allowed)
    }
  }

  func testSupportsAnInjectedDenialWithoutChangingProductionPolicy() {
    let deniedPolicy = CommandPolicy { _ in
      .denied(reason: "User presence is required.")
    }

    XCTAssertEqual(
      deniedPolicy.evaluate(.openApplication(.notion)),
      .denied(reason: "User presence is required.")
    )
    XCTAssertEqual(policy.evaluate(.openApplication(.notion)), .allowed)
  }
}
