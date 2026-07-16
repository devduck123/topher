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

  func testOpensDeveloperAndEntertainmentWebDestinations() async {
    var openedURLs: [URL] = []
    let capability = WebOpenCapability(
      workspace: WebWorkspace(open: { openedURLs.append($0) })
    )

    _ = await capability.execute(.github)
    _ = await capability.execute(.crunchyroll)
    _ = await capability.execute(.gmail)

    XCTAssertEqual(
      openedURLs.map(\.absoluteString),
      ["https://github.com/", "https://www.crunchyroll.com/", "https://mail.google.com/"]
    )
  }

  func testOpensChromeExtensionsThroughTheChromeApplication() async {
    let applicationURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")
    var openedApplicationURL: URL?
    var openedURLs: [URL] = []
    let capability = BrowserRouteOpenCapability(
      workspace: BrowserRouteWorkspace(
        applicationURL: { bundleIdentifier in
          XCTAssertEqual(bundleIdentifier, "com.google.Chrome")
          return applicationURL
        },
        openURLs: { urls, applicationURL in
          openedURLs = urls
          openedApplicationURL = applicationURL
        }
      )
    )

    let outcome = await capability.execute(.chromeExtensions)

    XCTAssertEqual(openedApplicationURL, applicationURL)
    XCTAssertEqual(openedURLs.map(\.absoluteString), ["chrome://extensions/"])
    XCTAssertEqual(outcome, .succeeded(message: "Opened Chrome Extensions."))
    XCTAssertEqual(
      BrowserRouteOpenCapability.descriptor,
      CapabilityDescriptor(
        identifier: "browserRouteNavigation",
        access: .changesState,
        risk: .lowRiskReversible
      )
    )
  }

  func testBrowserRouteFailsClosedWhenChromeIsUnavailable() async {
    let capability = BrowserRouteOpenCapability(
      workspace: BrowserRouteWorkspace(
        applicationURL: { _ in nil },
        openURLs: { _, _ in XCTFail("Must not attempt to open a missing browser") }
      )
    )

    let outcome = await capability.execute(.chromeExtensions)

    XCTAssertEqual(outcome, .failed(message: "Could not open Chrome Extensions."))
  }

  func testOpensAValidatedDomainOverHTTPS() async throws {
    var openedURL: URL?
    let capability = WebOpenCapability(
      workspace: WebWorkspace(open: { openedURL = $0 })
    )
    let domain = try XCTUnwrap(HTTPSDomain("TNC.com"))

    let outcome = await capability.execute(domain)

    XCTAssertEqual(openedURL?.absoluteString, "https://tnc.com/")
    XCTAssertEqual(outcome, .succeeded(message: "Opened tnc.com."))
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
