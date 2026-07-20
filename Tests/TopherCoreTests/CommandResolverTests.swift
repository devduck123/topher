import XCTest

@testable import TopherCore

final class CommandResolverTests: XCTestCase {
  private let resolver = CommandResolver()

  func testRecognizesBoundedChromeContextQuestions() {
    let cases: [(String, TopherCommand)] = [
      ("What is this Chrome tab?", .identifyActiveChromeTab),
      ("Which Chrome tab is active?", .identifyActiveChromeTab),
      ("What tabs do I have open?", .listChromeTabs),
      ("List my open Chrome tabs.", .listChromeTabs),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(expected))
    }
  }

  func testRecognizesExplicitChromeTabTitleActivation() throws {
    let title = try XCTUnwrap(ChromeTabTitleQuery("GitHub — Pull requests"))
    XCTAssertEqual(
      resolver.resolve("Switch to the Chrome tab titled GitHub — Pull requests."),
      .resolved(.activateChromeTab(title))
    )
    XCTAssertEqual(
      resolver.resolve("Go to Chrome tab titled GitHub — Pull requests"),
      .resolved(.activateChromeTab(title))
    )
  }

  func testRecognizesBoundedYouTubeFeedReadPhrasings() {
    for transcript in [
      "What’s on my YouTube feed?",
      "What is on my YouTube feed",
      "Show me my YouTube feed.",
      "Read my YouTube feed",
      "What's on my YouTube home page?",
    ] {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .resolved(.readYouTubeFeed),
        transcript
      )
    }
  }

  func testRecognizesYouTubeFeedOrdinalFollowupsThroughTwenty() {
    let cases: [(String, Int)] = [
      ("Open the third one", 3),
      ("Play the 2nd video", 2),
      ("Open YouTube recommendation number 12", 12),
      ("Open item twenty", 20),
      ("Open item one", 1),
      ("Open number 1", 1),
    ]
    for (transcript, position) in cases {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .resolved(.openYouTubeFeedItem(.ordinal(position))),
        transcript
      )
    }

    XCTAssertEqual(
      resolver.resolve("Open the twenty-first one"),
      .unsupported(reason: .contextRequired)
    )
    XCTAssertEqual(
      resolver.resolve("Open number 21"),
      .unsupported(reason: .contextRequired)
    )
  }

  func testRecognizesYouTubeFeedTitleFollowupWithoutFuzzyAuthority() throws {
    let title = try XCTUnwrap(YouTubeVideoTitleQuery("Swift Concurrency — Carefully"))
    XCTAssertEqual(
      resolver.resolve("Open the YouTube video titled Swift Concurrency — Carefully."),
      .resolved(.openYouTubeFeedItem(.title(title)))
    )
    XCTAssertEqual(
      resolver.resolve("Open the YouTube video titled"),
      .unsupported(reason: .missingValue)
    )
    XCTAssertEqual(
      resolver.resolve("Open any YouTube recommendation"),
      .unsupported(reason: .unsupportedAction)
    )
  }

  func testChromeTabActivationRequiresATitleAndDoesNotAcceptBroaderBrowserWork() {
    XCTAssertEqual(
      resolver.resolve("Switch to the Chrome tab titled"),
      .unsupported(reason: .missingValue)
    )
    XCTAssertEqual(
      resolver.resolve("Close the Chrome tab titled GitHub"),
      .unsupported(reason: .unsupportedPhrasing)
    )
  }

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

  func testRecognizesBareExactKnownTargets() {
    let cases: [(String, TopherCommand)] = [
      ("Chrome", .openApplication(.chrome)),
      ("Notes.", .openApplication(.notes)),
      ("Notion!", .openApplication(.notion)),
      ("VS Code.", .openApplication(.visualStudioCode)),
      ("YouTube", .openWebsite(.youtube)),
      ("GitHub.", .openWebsite(.github)),
    ]

    for (transcript, expected) in cases {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(expected))
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
      ("Open gidhub.com", .github),
      ("Open Crunchyroll", .crunchyroll),
      ("Open Netflix", .netflix),
      ("Open Hulu", .hulu),
      ("Open Amazon", .amazon),
      ("Open Ballislife", .ballislife),
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
      ("Open YouTube for dining with Derek.", .youtube, "dining with Derek"),
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

  func testKnownSearchDestinationsAcceptDestinationFirstQueries() {
    let cases: [(String, SearchProvider, String)] = [
      ("YouTube for dining with Derek.", .youtube, "dining with Derek"),
      ("YouTube, dining with Derek.", .youtube, "dining with Derek"),
      ("YouTube search dining with Derek", .youtube, "dining with Derek"),
      ("Google for Swift concurrency", .google, "Swift concurrency"),
      ("Google: local macOS speech recognition", .google, "local macOS speech recognition"),
    ]

    for (transcript, provider, queryText) in cases {
      let query = SearchQuery(queryText)
      XCTAssertEqual(
        resolver.resolve(transcript),
        query.map { .resolved(.searchWeb(provider: provider, query: $0)) }
      )
    }
  }

  func testRecognizesExplicitValidatedHTTPSDomains() throws {
    let cases = [
      ("Go to TNC.com.", "tnc.com"),
      ("Go to TNC.com for me.", "tnc.com"),
      ("Visit www.swift.org", "www.swift.org"),
      ("Open https://developer.apple.com", "developer.apple.com"),
    ]

    for (transcript, host) in cases {
      let domain = try XCTUnwrap(HTTPSDomain(host))
      XCTAssertEqual(resolver.resolve(transcript), .resolved(.openDomain(domain)))
    }
  }

  func testExplicitDomainNavigationFailsClosedForUnsafeOrAmbiguousValues() {
    let cases = [
      "Open http://example.com",
      "Open example.com/private/path",
      "Open user@example.com",
      "Open example.com:8443",
      "Open 127.0.0.1",
      "Open localhost",
      "Open totally-real.example",
    ]

    for transcript in cases {
      XCTAssertEqual(resolver.resolve(transcript), .unsupported(reason: .unknownTarget))
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
      ("Search Netflix", .netflix),
      ("Search Hulu", .hulu),
      ("Search Amazon", .amazon),
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
      ("Search YouTube for dining with Derek.", .youtube, "dining with Derek"),
      ("Search for tnc.com", .google, "tnc.com"),
      ("Search Crunchyroll anime releases", .google, "Crunchyroll anime releases"),
      ("Search Chrome extensions", .google, "Chrome extensions"),
      ("Search Chrome for Ball is Life", .google, "Ball is Life"),
      ("Search in Chrome for Swift concurrency", .google, "Swift concurrency"),
      ("Chrome search for GPT 5", .google, "GPT 5"),
      (
        "Search Chrome for what are some good UI slash UX principles?",
        .google,
        "what are some good UI/UX principles"
      ),
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

  func testSearchTechnicalNotationNormalizationRemainsConservative() throws {
    XCTAssertEqual(
      resolver.resolve("Search Chrome for UI slash UX principles"),
      .resolved(
        .searchWeb(
          provider: .google,
          query: try XCTUnwrap(SearchQuery("UI/UX principles"))
        )
      )
    )
    XCTAssertEqual(
      resolver.resolve("Search Chrome for turn left slash right at the fork"),
      .resolved(
        .searchWeb(
          provider: .google,
          query: try XCTUnwrap(SearchQuery("turn left slash right at the fork"))
        )
      )
    )
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
    XCTAssertEqual(
      resolver.resolve(transcript),
      .unsupported(reason: .applicationNotFound)
    )
  }

  func testResolvesDiscoveredInstalledApplicationsWithoutConstructingPaths() throws {
    let figma = InstalledApplicationTarget(
      displayName: "Figma",
      bundleIdentifier: "com.figma.Desktop"
    )
    let dynamicResolver = CommandResolver(installedApplications: [figma])

    for transcript in ["Open Figma", "Launch Figma app", "Figma."] {
      XCTAssertEqual(
        dynamicResolver.resolve(transcript),
        .resolved(.openInstalledApplication(figma))
      )
    }
  }

  func testWebsiteAndApplicationQualifiersMakePrecedenceExplicit() throws {
    let netflix = InstalledApplicationTarget(
      displayName: "Netflix",
      bundleIdentifier: "com.netflix.Netflix"
    )
    let dynamicResolver = CommandResolver(installedApplications: [netflix])

    XCTAssertEqual(
      dynamicResolver.resolve("Open Netflix"),
      .resolved(.openWebsite(.netflix))
    )
    XCTAssertEqual(
      dynamicResolver.resolve("Open Netflix website"),
      .resolved(.openWebsite(.netflix))
    )
    XCTAssertEqual(
      dynamicResolver.resolve("Open Netflix app"),
      .resolved(.openInstalledApplication(netflix))
    )
  }

  func testUnknownNavigationFallsBackToTransparentGoogleSearch() throws {
    let spotify = try XCTUnwrap(SearchQuery("Spotify"))
    let crunchyroll = try XCTUnwrap(SearchQuery("Crunchyroll"))

    XCTAssertEqual(
      resolver.resolve("Open Spotify."),
      .resolved(.searchUnknownDestination(spotify))
    )
    XCTAssertEqual(
      resolver.resolve("Bring me to Crunchyroll website"),
      .resolved(.openWebsite(.crunchyroll))
    )
    XCTAssertEqual(
      resolver.resolve("Open Acme Streaming website."),
      .resolved(.searchUnknownDestination(try XCTUnwrap(SearchQuery("Acme Streaming"))))
    )
    XCTAssertNotEqual(
      resolver.resolve("Open Crunchyroll"),
      .resolved(.searchUnknownDestination(crunchyroll))
    )
  }

  func testExplicitMissingApplicationDoesNotBecomeAWebSearch() {
    XCTAssertEqual(
      resolver.resolve("Open Spotify desktop app"),
      .unsupported(reason: .applicationNotFound)
    )
  }

  func testAmbiguousInstalledApplicationNameFailsClearly() {
    let first = InstalledApplicationTarget(
      displayName: "Preview",
      bundleIdentifier: "com.example.PreviewOne"
    )
    let second = InstalledApplicationTarget(
      displayName: "Preview",
      bundleIdentifier: "com.example.PreviewTwo"
    )
    let dynamicResolver = CommandResolver(installedApplications: [first, second])

    XCTAssertEqual(
      dynamicResolver.resolve("Open Preview"),
      .unsupported(reason: .ambiguousTarget)
    )
  }

  func testRecognizesBoundedFrontmostApplicationQuestions() {
    let cases = [
      "What app am I using?",
      "What application am I in?",
      "What app is open?",
      "What app is this?",
    ]

    for transcript in cases {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .resolved(.identifyFrontmostApplication)
      )
    }
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

  func testBroaderScreenAndPageRequestsStillRequireUnavailableContext() {
    let cases = [
      "Go to this Chrome tab",
      "Summarize this page",
    ]

    for transcript in cases {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .unsupported(reason: .contextRequired)
      )
    }
  }

  func testObservedYouTubeQueriesDoNotDependOnSpokenPunctuation() throws {
    let query = try XCTUnwrap(SearchQuery("dining with Derek"))
    let expected = CommandResolution.resolved(.searchWeb(provider: .youtube, query: query))

    for transcript in [
      "YouTube dining with Derek.",
      "Go to YouTube, look for dining with Derek.",
      "Go to YouTube and look for dining with Derek.",
    ] {
      XCTAssertEqual(resolver.resolve(transcript), expected)
    }
  }

  func testEBayIsAKnownCanonicalWebsite() {
    for transcript in ["eBay", "eBay.com", "Go to eBay", "Go to eBay.com"] {
      XCTAssertEqual(resolver.resolve(transcript), .resolved(.openWebsite(.ebay)))
    }
  }

  func testExplicitTypingPhrasesDirectTheUserToDictationMode() {
    for transcript in ["Type LeBron James", "Input LeBron James", "Dictate hello"] {
      XCTAssertEqual(
        resolver.resolve(transcript),
        .unsupported(reason: .dictationModeRequired)
      )
    }

    XCTAssertEqual(
      resolver.resolve("LeBron James"),
      .unsupported(reason: .unsupportedPhrasing)
    )
  }
}
