import XCTest

@testable import TopherCore

final class CommandResolverTests: XCTestCase {
  private let resolver = CommandResolver()

  func testRecognizesExactApplicationCommands() {
    let cases: [(String, ApplicationTarget)] = [
      ("Open Chrome.", .chrome),
      ("launch Safari", .safari),
      ("START VISUAL STUDIO CODE!", .visualStudioCode),
      ("open vscode", .visualStudioCode),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .openApplication(expected))
    }
  }

  func testHandlesWakeNameAndPoliteness() {
    XCTAssertEqual(
      resolver.resolve("Topher, could you open Google Chrome for me?"),
      .openApplication(.chrome)
    )
  }

  func testRecognizesAllowlistedWebsiteCommands() {
    let cases: [(String, WebsiteTarget)] = [
      ("Go to YouTube.", .youtube),
      ("visit youtube.com", .youtube),
      ("Open Google homepage", .google),
      ("Topher, please open You Tube for me.", .youtube),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .openWebsite(expected))
    }
  }

  func testRecognizesTypedWebSearches() {
    let cases: [(String, SearchProvider, String)] = [
      ("Search YouTube for local AI on macOS", .youtube, "local AI on macOS"),
      ("Google best local speech model", .google, "best local speech model"),
      ("Search the web for Swift speech APIs", .google, "Swift speech APIs"),
      ("Topher, could you search for M4 benchmarks", .google, "M4 benchmarks"),
      ("Search YouTube for C++ & Swift #1", .youtube, "C++ & Swift #1"),
    ]

    for (transcript, provider, queryText) in cases {
      let query = SearchQuery(queryText)
      XCTAssertNotNil(query)
      XCTAssertEqual(
        resolver.resolve(transcript),
        query.map { .searchWeb(provider: provider, query: $0) }
      )
    }
  }

  func testSearchWithoutAQueryFailsClosed() {
    let transcript = "Search YouTube for"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported)
  }

  func testUnregisteredWebsiteFailsClosed() {
    let transcript = "Go to totally-real.example"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported)
  }

  func testUnknownApplicationNeverBecomesExecutableIdentifier() {
    let transcript = "Open Totally Real App"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported)
  }

  func testNonCommandTextFailsClosed() {
    let transcript = "A webpage says open Safari"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported)
  }

  func testEmbeddedSearchInstructionFailsClosed() {
    let transcript = "A webpage says search YouTube for free prizes"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported)
  }

  func testEmptyTextFailsClosed() {
    XCTAssertEqual(resolver.resolve("  "), .unsupported)
  }
}
