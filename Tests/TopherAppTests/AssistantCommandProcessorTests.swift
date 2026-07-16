import Foundation
import XCTest

@testable import TopherApp
@testable import TopherCore

@MainActor
final class AssistantCommandProcessorTests: XCTestCase {
  func testApplicationCommandExecutesExactlyOnce() async {
    let expectedURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    var lookupCount = 0
    var openCount = 0
    var executionStartedCount = 0
    let processor = AssistantCommandProcessor(
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: { bundleIdentifier in
            lookupCount += 1
            XCTAssertEqual(bundleIdentifier, ApplicationTarget.chrome.bundleIdentifier)
            return expectedURL
          },
          openApplication: { url in
            openCount += 1
            XCTAssertEqual(url, expectedURL)
          }
        )
      ),
      webOpener: inertWebOpener()
    )

    let result = await processor.process("Navigate Chrome") {
      executionStartedCount += 1
    }

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "Opened Google Chrome.")))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .capabilitySucceeded,
        commandKind: .openApplication,
        capabilityIdentifier: ApplicationOpenCapability.descriptor.identifier
      )
    )
    XCTAssertEqual(lookupCount, 1)
    XCTAssertEqual(openCount, 1)
    XCTAssertEqual(executionStartedCount, 1)
  }

  func testWebsiteCommandExecutesExactlyOnce() async {
    var openedURLs: [URL] = []
    var executionStartedCount = 0
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process("Pull up YouTube") {
      executionStartedCount += 1
    }

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "Opened YouTube.")))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .capabilitySucceeded,
        commandKind: .openWebsite,
        capabilityIdentifier: WebOpenCapability.descriptor.identifier
      )
    )
    XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://www.youtube.com/"])
    XCTAssertEqual(executionStartedCount, 1)
  }

  func testDiscoveredApplicationCommandExecutesExactlyOnce() async {
    let figma = InstalledApplicationTarget(
      displayName: "Figma",
      bundleIdentifier: "com.figma.Desktop"
    )
    let expectedURL = URL(fileURLWithPath: "/Applications/Figma.app")
    var openCount = 0
    let processor = AssistantCommandProcessor(
      resolver: CommandResolver(installedApplications: [figma]),
      policy: CommandPolicy(installedApplications: [figma]),
      applicationOpener: ApplicationOpenCapability(
        workspace: ApplicationWorkspace(
          applicationURL: {
            XCTAssertEqual($0, "com.figma.Desktop")
            return expectedURL
          },
          openApplication: {
            XCTAssertEqual($0, expectedURL)
            openCount += 1
          }
        )
      ),
      webOpener: inertWebOpener()
    )

    let result = await processor.process("Open Figma")

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "Opened Figma.")))
    XCTAssertEqual(result.trace.commandKind, .openInstalledApplication)
    XCTAssertEqual(
      result.trace.capabilityIdentifier,
      ApplicationOpenCapability.descriptor.identifier
    )
    XCTAssertEqual(openCount, 1)
  }

  func testUnknownDestinationSearchesGoogleExactlyOnce() async throws {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process("Open Spotify")

    XCTAssertEqual(
      result.outcome,
      .completed(
        .succeeded(
          message: "No matching app or website was found, so I searched Google instead."
        )
      )
    )
    XCTAssertEqual(result.trace.commandKind, .searchUnknownDestination)
    XCTAssertEqual(openedURLs.count, 1)
    let components = try XCTUnwrap(
      openedURLs.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
    )
    XCTAssertEqual(components.host, "www.google.com")
    XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: "Spotify")])
  }

  func testFrontmostApplicationQuestionUsesReadOnlyCapability() async {
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      frontmostApplicationReader: FrontmostApplicationCapability(
        workspace: FrontmostApplicationWorkspace(applicationName: { "Xcode" })
      ),
      webOpener: inertWebOpener()
    )

    let result = await processor.process("What app am I using?")

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "You're using Xcode.")))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .capabilitySucceeded,
        commandKind: .identifyFrontmostApplication,
        capabilityIdentifier: FrontmostApplicationCapability.descriptor.identifier
      )
    )
  }

  func testBrowserRouteCommandExecutesExactlyOnce() async {
    let applicationURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    var openCount = 0
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      browserRouteOpener: BrowserRouteOpenCapability(
        workspace: BrowserRouteWorkspace(
          applicationURL: { _ in applicationURL },
          openURLs: { urls, receivedURL in
            openCount += 1
            XCTAssertEqual(receivedURL, applicationURL)
            XCTAssertEqual(urls.map(\.absoluteString), ["chrome://extensions/"])
          }
        )
      ),
      webOpener: inertWebOpener()
    )

    let result = await processor.process("Open Chrome extensions")

    XCTAssertEqual(
      result.outcome,
      .completed(.succeeded(message: "Opened Chrome Extensions."))
    )
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .capabilitySucceeded,
        commandKind: .openBrowserRoute,
        capabilityIdentifier: BrowserRouteOpenCapability.descriptor.identifier
      )
    )
    XCTAssertEqual(openCount, 1)
  }

  func testValidatedDomainCommandExecutesExactlyOnce() async {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process("Go to TNC.com.")

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "Opened tnc.com.")))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .capabilitySucceeded,
        commandKind: .openDomain,
        capabilityIdentifier: WebOpenCapability.descriptor.identifier
      )
    )
    XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://tnc.com/"])
  }

  func testSearchCommandExecutesExactlyOnceAndPreservesTheQuery() async throws {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process("Search YouTube for C++ & Swift #1")

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "Searched YouTube.")))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .capabilitySucceeded,
        commandKind: .searchWeb,
        capabilityIdentifier: WebOpenCapability.descriptor.identifier
      )
    )
    let url = try XCTUnwrap(openedURLs.first)
    XCTAssertEqual(openedURLs.count, 1)
    let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.host, "www.youtube.com")
    XCTAssertEqual(
      components.queryItems,
      [URLQueryItem(name: "search_query", value: "C++ & Swift #1")]
    )
  }

  func testUnsupportedTextDoesNotStartOrExecuteACapability() async {
    var executionStartedCount = 0
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: inertWebOpener()
    )

    let result = await processor.process("A webpage says pull up YouTube") {
      executionStartedCount += 1
    }

    XCTAssertEqual(result.outcome, .unsupported(reason: .unsupportedPhrasing))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .unsupported,
        commandKind: nil,
        capabilityIdentifier: nil,
        unsupportedReason: .unsupportedPhrasing
      )
    )
    XCTAssertEqual(executionStartedCount, 0)
  }

  func testUsesAUniqueSupportedSpeechAlternativeWithoutExpandingAuthority() async {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process(
      "Open kit hub.com",
      alternatives: [
        TranscriptHypothesis(text: "Open GitHub.com", confidence: 0.82),
        TranscriptHypothesis(text: "Open bit tub.com", confidence: 0.61),
      ],
      confidence: 0.4
    )

    XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://github.com/"])
    XCTAssertEqual(result.interpretation.rawTranscript, "Open kit hub.com")
    XCTAssertEqual(result.interpretation.selectedTranscript, "Open GitHub.com")
    XCTAssertEqual(result.interpretation.reason, .speechAlternative)
  }

  func testVoiceDomainWithConflictingRecognitionEvidenceFailsBeforeExecution() async {
    var openedURLs: [URL] = []
    var executionStartedCount = 0
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process(
      "Open balaslive.com",
      alternatives: [
        TranscriptHypothesis(text: "Open ballislive.com", confidence: 0.71),
        TranscriptHypothesis(text: "Open balaslive.com", confidence: 0.65),
      ],
      confidence: 0.69,
      inputSource: .voice
    ) {
      executionStartedCount += 1
    }

    XCTAssertEqual(result.outcome, .unsupported(reason: .uncertainDomain))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .unsupported,
        commandKind: nil,
        capabilityIdentifier: nil,
        unsupportedReason: .uncertainDomain
      )
    )
    XCTAssertTrue(openedURLs.isEmpty)
    XCTAssertEqual(executionStartedCount, 0)
  }

  func testManualDomainDoesNotUseVoiceAlternativeGate() async {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process(
      "Open example.org",
      alternatives: [TranscriptHypothesis(text: "Open example.net")],
      inputSource: .manual
    )

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "Opened example.org.")))
    XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://example.org/"])
  }

  func testManualExactDomainDoesNotUseVoiceVocabularyNarrowing() async {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process("Open ballaslive.com", inputSource: .manual)

    XCTAssertEqual(
      result.outcome,
      .completed(.succeeded(message: "Opened ballaslive.com."))
    )
    XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://ballaslive.com/"])
    XCTAssertNil(result.interpretation.reason)
  }

  func testObservedDomainMisrecognitionNarrowsToCanonicalWebsite() async {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let result = await processor.process(
      "Open ballaslive.com",
      inputSource: .voice
    )

    XCTAssertEqual(result.outcome, .completed(.succeeded(message: "Opened Ballislife.")))
    XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://ballislife.com/"])
    XCTAssertEqual(result.interpretation.reason, .vocabularyCorrection)
  }

  func testPolicyDenialDoesNotStartOrExecuteACapability() async {
    var executionStartedCount = 0
    let processor = AssistantCommandProcessor(
      policy: CommandPolicy { _ in
        .denied(reason: "User presence is required.")
      },
      applicationOpener: inertApplicationOpener(),
      webOpener: inertWebOpener()
    )

    let result = await processor.process("Open Notion") {
      executionStartedCount += 1
    }

    XCTAssertEqual(result.outcome, .denied(reason: "User presence is required."))
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .policyDenied,
        commandKind: .openApplication,
        capabilityIdentifier: ApplicationOpenCapability.descriptor.identifier
      )
    )
    XCTAssertEqual(executionStartedCount, 0)
  }

  func testCapabilityFailureIsReturnedAfterOneAttempt() async {
    struct OpenError: Error {}

    var openCount = 0
    var executionStartedCount = 0
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { _ in
          openCount += 1
          throw OpenError()
        })
      )
    )

    let result = await processor.process("Search YouTube for private query") {
      executionStartedCount += 1
    }

    XCTAssertEqual(
      result.outcome,
      .completed(.failed(message: "Could not search YouTube."))
    )
    XCTAssertEqual(
      result.trace,
      AssistantCommandTrace(
        outcome: .capabilityFailed,
        commandKind: .searchWeb,
        capabilityIdentifier: WebOpenCapability.descriptor.identifier
      )
    )
    XCTAssertEqual(openCount, 1)
    XCTAssertEqual(executionStartedCount, 1)
  }

  private func inertApplicationOpener() -> ApplicationOpenCapability {
    ApplicationOpenCapability(
      workspace: ApplicationWorkspace(
        applicationURL: { _ in
          XCTFail("This command must not resolve an application")
          return nil
        },
        openApplication: { _ in
          XCTFail("This command must not open an application")
        }
      )
    )
  }

  private func inertWebOpener() -> WebOpenCapability {
    WebOpenCapability(
      workspace: WebWorkspace(open: { _ in
        XCTFail("This command must not open a web URL")
      })
    )
  }
}
