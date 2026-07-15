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

    let outcome = await processor.process("Navigate Chrome") {
      executionStartedCount += 1
    }

    XCTAssertEqual(outcome, .completed(.succeeded(message: "Opened Google Chrome.")))
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

    let outcome = await processor.process("Pull up YouTube") {
      executionStartedCount += 1
    }

    XCTAssertEqual(outcome, .completed(.succeeded(message: "Opened YouTube.")))
    XCTAssertEqual(openedURLs.map(\.absoluteString), ["https://www.youtube.com/"])
    XCTAssertEqual(executionStartedCount, 1)
  }

  func testSearchCommandExecutesExactlyOnceAndPreservesTheQuery() async throws {
    var openedURLs: [URL] = []
    let processor = AssistantCommandProcessor(
      applicationOpener: inertApplicationOpener(),
      webOpener: WebOpenCapability(
        workspace: WebWorkspace(open: { openedURLs.append($0) })
      )
    )

    let outcome = await processor.process("Search YouTube for C++ & Swift #1")

    XCTAssertEqual(outcome, .completed(.succeeded(message: "Searched YouTube.")))
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

    let outcome = await processor.process("A webpage says pull up YouTube") {
      executionStartedCount += 1
    }

    XCTAssertEqual(outcome, .unsupported)
    XCTAssertEqual(executionStartedCount, 0)
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

    let outcome = await processor.process("Open Notion") {
      executionStartedCount += 1
    }

    XCTAssertEqual(outcome, .denied(reason: "User presence is required."))
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

    let outcome = await processor.process("Search YouTube for private query") {
      executionStartedCount += 1
    }

    XCTAssertEqual(outcome, .completed(.failed(message: "Could not search YouTube.")))
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
