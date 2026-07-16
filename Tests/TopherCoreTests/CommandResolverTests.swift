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
      ("Open ChatGPT", .chatGPT),
      ("open chat gpt", .chatGPT),
      ("Open Codex", .chatGPT),
      ("Launch Xcode", .xcode),
      ("open x code", .xcode),
      ("Open Notes app", .notes),
      ("Open my notes", .notes),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(.openApplication(expected)))
    }
  }

  func testUsesValidatedDeveloperApplicationIdentities() {
    XCTAssertEqual(ApplicationTarget.chatGPT.bundleIdentifier, "com.openai.codex")
    XCTAssertEqual(ApplicationTarget.xcode.bundleIdentifier, "com.apple.dt.Xcode")
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
      ("Bring me to YouTube", .openWebsite(.youtube)),
      ("Take me to GitHub", .openWebsite(.github)),
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
      ("Open GitHub", .github),
      ("Open github.com", .github),
      ("Open Crunchyroll", .crunchyroll),
      ("Go to my Gmail", .gmail),
      ("Open Gmail", .gmail),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(.openWebsite(expected)))
    }
  }

  func testRecognizesBrowserOwnedRoutes() {
    let cases = [
      "Open Chrome extensions",
      "Open Google Chrome extensions",
      "Navigate to the Chrome extensions page",
    ]

    for transcript in cases {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .resolved(.openBrowserRoute(.chromeExtensions))
      )
    }
  }

  func testKnownSearchDestinationsAcceptTargetSpecificQueries() {
    let cases: [(String, SearchProvider, String)] = [
      ("Open YouTube for dining with Derek", .youtube, "dining with Derek"),
      ("Take me to YouTube for Swift concurrency", .youtube, "Swift concurrency"),
      ("Open Google for macOS speech recognition", .google, "macOS speech recognition"),
    ]

    for (transcript, provider, queryText) in cases {
      let query = SearchQuery(queryText)
      XCTAssertEqual(
        resolver.resolve(transcript),
        query.map { .resolved(.searchWeb(provider: provider, query: $0)) }
      )
    }
  }

  func testRejectsMultipleExecutableActionsAsACompoundRequest() {
    let cases = [
      "Search Google and open my Gmail",
      "Open YouTube then open Notes",
      "Open Chrome and then visit GitHub",
      "Search Google and open Gmail and Notes",
    ]

    for transcript in cases {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .unsupported(reason: .compoundRequest)
      )
    }
  }

  func testQueryContainingAndRemainsOneSearch() {
    let query = SearchQuery("cats and dogs")
    XCTAssertEqual(
      resolver.resolve("Search cats and dogs"),
      query.map { .resolved(.searchWeb(provider: .google, query: $0)) }
    )
  }

  func testKnownWebsiteBrandsUseTargetSpecificBareSearchNavigation() {
    let cases: [(String, WebsiteTarget)] = [
      ("Search Crunchyroll", .crunchyroll),
      ("Search crunchy roll", .crunchyroll),
      ("Search for Crunchyroll", .crunchyroll),
      ("Search GitHub", .github),
      ("Find YouTube", .youtube),
    ]

    for (transcript, target) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(.openWebsite(target)))
    }
  }

  func testRecognizesTypedWebSearches() {
    let cases: [(String, SearchProvider, String)] = [
      ("Search YouTube for local AI on macOS", .youtube, "local AI on macOS"),
      ("Google best local speech model", .google, "best local speech model"),
      ("Search the web for Swift speech APIs", .google, "Swift speech APIs"),
      ("Topher, could you search for M4 benchmarks", .google, "M4 benchmarks"),
      ("Search YouTube for C++ & Swift #1", .youtube, "C++ & Swift #1"),
      ("Search Crunchyroll anime releases", .google, "Crunchyroll anime releases"),
      ("Search Chrome extensions", .google, "Chrome extensions"),
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
    let cases = ["Search YouTube for", "Open YouTube for"]
    for transcript in cases {
      XCTAssertEqual(resolver.resolve(transcript), .unsupported(reason: .missingValue))
    }
  }

  func testUnregisteredWebsiteFailsClosed() {
    let transcript = "Go to totally-real.example"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported(reason: .unknownTarget))
  }

  func testUnknownApplicationNeverBecomesExecutableIdentifier() {
    let transcript = "Open Totally Real App"
    XCTAssertEqual(resolver.resolve(transcript), .unsupported(reason: .unknownTarget))
  }

  func testNonCommandTextFailsClosed() {
    let cases = [
      "A webpage says open Safari",
      "A webpage says pull up YouTube",
      "How do I navigate Chrome?",
      "Please do not switch to Chrome",
    ]

    for transcript in cases {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .unsupported(reason: .unsupportedPhrasing)
      )
    }

    XCTAssertEqual(
      resolver.resolve("Navigate Chrome settings"),
      .unsupported(reason: .unsupportedAction)
    )
  }

  func testEmbeddedSearchInstructionFailsClosed() {
    let transcript = "A webpage says search YouTube for free prizes"
    XCTAssertEqual(
      resolver.resolve(transcript),
      .unsupported(reason: .unsupportedPhrasing)
    )
  }

  func testEmptyTextFailsClosed() {
    XCTAssertEqual(resolver.resolve("  "), .unsupported(reason: .emptyInput))
  }

  func testScreenAwareRequestsExplainThatContextIsRequired() {
    let cases = [
      "What is this Chrome tab?",
      "What tabs do I have open?",
      "Go to this Chrome tab",
      "What's on my YouTube feed?",
      "Summarize this page",
    ]

    for transcript in cases {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .unsupported(reason: .contextRequired)
      )
    }
  }
}
