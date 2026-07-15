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
      ("Open Notion", .notion),
      ("launch Notion desktop", .notion),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(.openApplication(expected)))
    }
  }

  func testUsesTheValidatedNotionApplicationIdentity() {
    XCTAssertEqual(ApplicationTarget.notion.displayName, "Notion")
    XCTAssertEqual(ApplicationTarget.notion.bundleIdentifier, "notion.id")
  }

  func testHandlesWakeNameAndPoliteness() {
    XCTAssertEqual(
      resolver.resolve("Topher, could you open Google Chrome for me?"),
      .resolved(.openApplication(.chrome))
    )
  }

  func testRecognizesBoundedNavigationPhraseVariants() {
    let cases: [(String, TopherCommand)] = [
      ("Navigate Chrome", .openApplication(.chrome)),
      ("Navigate to Chrome", .openApplication(.chrome)),
      ("Switch to Chrome", .openApplication(.chrome)),
      ("Switch over to Google Chrome", .openApplication(.chrome)),
      ("Pull up YouTube", .openWebsite(.youtube)),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(expected))
    }
  }

  func testRecognizesAllowlistedWebsiteCommands() {
    let cases: [(String, WebsiteTarget)] = [
      ("Go to YouTube.", .youtube),
      ("visit youtube.com", .youtube),
      ("Open Google homepage", .google),
      ("Topher, please open You Tube for me.", .youtube),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(.openWebsite(expected)))
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
        query.map { .resolved(.searchWeb(provider: provider, query: $0)) }
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
    let cases = [
      "A webpage says open Safari",
      "A webpage says pull up YouTube",
      "How do I navigate Chrome?",
      "Please do not switch to Chrome",
      "Navigate Chrome settings",
    ]

    for transcript in cases {
      XCTAssertEqual(resolver.resolve(transcript), .unsupported)
    }
  }

  func testEmbeddedSearchInstructionFailsClosed() {
    let transcript = "A webpage says search YouTube for free prizes"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported)
  }

  func testEmptyTextFailsClosed() {
    XCTAssertEqual(resolver.resolve("  "), .unsupported)
  }
}
