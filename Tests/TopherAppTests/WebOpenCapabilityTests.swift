import Foundation
import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class WebOpenCapabilityTests: XCTestCase {
  func testDeclaresItsAuthority() {
    XCTAssertEqual(
      WebOpenCapability.descriptor,
      CapabilityDescriptor(
        identifier: "webNavigation",
        access: .changesState,
        risk: .sensitive
      )
    )
  }

  func testOpensAnAllowlistedHomepage() async {
    var openedURL: URL?
    let capability = WebOpenCapability(
      workspace: WebWorkspace(open: {
        openedURL = $0
      })
    )

    let outcome = await capability.execute(.youtube)

    XCTAssertEqual(openedURL?.absoluteString, "https://www.youtube.com/")
    XCTAssertEqual(outcome, .succeeded(message: "Opened YouTube."))
  }

  func testBuildsAnEncodedGoogleSearchURL() async throws {
    var openedURL: URL?
    let capability = WebOpenCapability(
      workspace: WebWorkspace(open: {
        openedURL = $0
      })
    )
    let query = try XCTUnwrap(SearchQuery("C++ & Swift"))

    let outcome = await capability.execute(provider: .google, query: query)

    let components = try XCTUnwrap(
      openedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
    XCTAssertEqual(components.scheme, "https")
    XCTAssertEqual(components.host, "www.google.com")
    XCTAssertEqual(components.path, "/search")
    XCTAssertEqual(components.queryItems, [URLQueryItem(name: "q", value: "C++ & Swift")])
    XCTAssertTrue(try XCTUnwrap(openedURL?.absoluteString).contains("C%2B%2B"))
    XCTAssertEqual(outcome, .succeeded(message: "Searched Google."))
  }

  func testBuildsAnEncodedYouTubeSearchURL() async throws {
    var openedURL: URL?
    let capability = WebOpenCapability(
      workspace: WebWorkspace(open: {
        openedURL = $0
      })
    )
    let query = try XCTUnwrap(SearchQuery("M4 local AI"))

    let outcome = await capability.execute(provider: .youtube, query: query)

    let components = try XCTUnwrap(
      openedURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
    XCTAssertEqual(components.scheme, "https")
    XCTAssertEqual(components.host, "www.youtube.com")
    XCTAssertEqual(components.path, "/results")
    XCTAssertEqual(
      components.queryItems,
      [URLQueryItem(name: "search_query", value: "M4 local AI")]
    )
    XCTAssertEqual(outcome, .succeeded(message: "Searched YouTube."))
  }

  func testReportsAWorkspaceOpenFailureWithoutExposingTheQuery() async throws {
    struct OpenError: Error {}

    let capability = WebOpenCapability(
      workspace: WebWorkspace(open: { _ in throw OpenError() })
    )
    let query = try XCTUnwrap(SearchQuery("private search text"))

    let outcome = await capability.execute(provider: .youtube, query: query)

    XCTAssertEqual(outcome, .failed(message: "Could not search YouTube."))
  }
}
