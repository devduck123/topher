import Foundation
import XCTest

@testable import TopherCore

final class ChromeContextTests: XCTestCase {
  func testPackagedChromeExtensionIdentityIsStableAcrossTheTypedBoundary() {
    XCTAssertEqual(ChromeBridgeConstants.extensionID, "mhbppdheppcibhhcnhnfockmfpcfhndj")
    XCTAssertEqual(
      ChromeBridgeConstants.extensionOrigin,
      "chrome-extension://mhbppdheppcibhhcnhnfockmfpcfhndj/"
    )
  }

  func testTitleQueryUsesExactNormalizedMatching() throws {
    let query = try XCTUnwrap(ChromeTabTitleQuery("  Résumé — GitHub  "))

    XCTAssertTrue(query.matches("resume github"))
    XCTAssertFalse(query.matches("Résumé — GitHub — Pull requests"))
    XCTAssertNil(ChromeTabTitleQuery("\u{0}"))
    XCTAssertNil(ChromeTabTitleQuery(String(repeating: "a", count: 1_025)))
  }

  func testTabURLAllowsOnlyBoundedNonCredentialSchemes() {
    XCTAssertNotNil(ChromeTabURL("https://example.com/private?token=untrusted"))
    XCTAssertNotNil(ChromeTabURL("chrome://extensions/"))
    XCTAssertNotNil(ChromeTabURL("chrome-extension://abcdefghijklmnopabcdefghijklmnop/page.html"))
    XCTAssertNotNil(ChromeTabURL("about:blank"))

    XCTAssertNil(ChromeTabURL("file:///Users/person/secret.txt"))
    XCTAssertNil(ChromeTabURL("data:text/plain,secret"))
    XCTAssertNil(ChromeTabURL("javascript:alert(1)"))
    XCTAssertNil(ChromeTabURL("https://user:password@example.com/"))
    XCTAssertNil(ChromeTabURL(String(repeating: "a", count: 2_049)))
  }

  func testWireTabRequiresTypedURLFingerprintAndBounds() throws {
    let valid = ChromeBridgeWireTab(
      tabID: 7,
      windowID: 3,
      index: 1,
      active: true,
      title: "Topher",
      url: "https://example.com/",
      fingerprint: String(repeating: "a", count: 64),
      capturedAtMilliseconds: 1_721_000_000_000
    )

    let snapshot = try XCTUnwrap(valid.validatedSnapshot)
    XCTAssertEqual(snapshot.title, "Topher")
    XCTAssertEqual(snapshot.url.displayOrigin, "example.com")

    XCTAssertNil(
      ChromeBridgeWireTab(
        tabID: 7,
        windowID: 3,
        index: 1,
        active: true,
        title: "Topher",
        url: "file:///tmp/secret",
        fingerprint: String(repeating: "a", count: 64),
        capturedAtMilliseconds: 1
      ).validatedSnapshot
    )
    XCTAssertNil(
      ChromeBridgeWireTab(
        tabID: 7,
        windowID: 3,
        index: 1,
        active: true,
        title: "Topher",
        url: "https://example.com/",
        fingerprint: "not-a-fingerprint",
        capturedAtMilliseconds: 1
      ).validatedSnapshot
    )
  }

  func testProtocolFactoriesEnforceTabCountAndRoundTripJSON() throws {
    XCTAssertNil(ChromeBridgeRequest.listTabs(maximumTabCount: 0))
    XCTAssertNil(ChromeBridgeRequest.listTabs(maximumTabCount: 51))

    let requestID = UUID()
    let request = try XCTUnwrap(
      ChromeBridgeRequest.listTabs(maximumTabCount: 25, requestID: requestID)
    )
    let encoded = try JSONEncoder().encode(request)
    XCTAssertEqual(try JSONDecoder().decode(ChromeBridgeRequest.self, from: encoded), request)
    XCTAssertEqual(request.version, ChromeBridgeRequest.protocolVersion)
  }

  func testYouTubeVideoAndHomeRouteTypesConstructOnlyStrictWatchDestinations() throws {
    let videoID = try XCTUnwrap(YouTubeVideoID("abcDEF123_-"))
    XCTAssertEqual(videoID.watchURL.absoluteString, "https://www.youtube.com/watch?v=abcDEF123_-")
    XCTAssertNil(YouTubeVideoID("too-short"))
    XCTAssertNil(YouTubeVideoID("abcDEF123!?"))

    XCTAssertNotNil(YouTubeFeedSourceURL("https://www.youtube.com/"))
    XCTAssertNotNil(YouTubeFeedSourceURL("https://www.youtube.com/?app=desktop"))
    XCTAssertNil(YouTubeFeedSourceURL("http://www.youtube.com/"))
    XCTAssertNil(YouTubeFeedSourceURL("https://youtube.com/"))
    XCTAssertNil(YouTubeFeedSourceURL("https://www.youtube.com/feed/subscriptions"))
    XCTAssertNil(YouTubeFeedSourceURL("https://www.youtube.com/watch?v=abcDEF123_-"))
  }

  func testYouTubeTitleQueryUsesBoundedNormalizedExactMatching() throws {
    let query = try XCTUnwrap(YouTubeVideoTitleQuery("  Résumé: Local AI! "))
    XCTAssertTrue(query.matches("resume local ai"))
    XCTAssertFalse(query.matches("Résumé local AI explained"))
    XCTAssertNil(YouTubeVideoTitleQuery("\u{0}"))
    XCTAssertNil(YouTubeVideoTitleQuery(String(repeating: "a", count: 513)))
  }

  func testYouTubeWireSnapshotValidatesEveryFieldAndLifetime() throws {
    let wire = ChromeBridgeWireYouTubeFeedSnapshot(
      sourceTabID: 7,
      sourceWindowID: 3,
      sourceURL: "https://www.youtube.com/",
      sourceFingerprint: String(repeating: "a", count: 64),
      feedObservationID: String(repeating: "b", count: 64),
      capturedAtMilliseconds: 1_000,
      expiresAtMilliseconds: 91_000,
      observationWasTruncated: false,
      items: [
        ChromeBridgeWireYouTubeFeedItem(
          position: 1,
          videoID: "abcDEF123_-",
          title: "Local-first Mac assistants",
          channel: "Example Channel",
          observationID: String(repeating: "c", count: 64)
        )
      ]
    )
    let snapshot = try XCTUnwrap(wire.validatedSnapshot)
    XCTAssertEqual(snapshot.items.first?.videoID.watchURL.host, "www.youtube.com")
    XCTAssertEqual(
      snapshot.openTarget(for: snapshot.items[0]).sourceURL, "https://www.youtube.com/")

    XCTAssertNil(
      ChromeBridgeWireYouTubeFeedSnapshot(
        sourceTabID: 7,
        sourceWindowID: 3,
        sourceURL: "https://www.youtube.com/watch?v=abcDEF123_-",
        sourceFingerprint: String(repeating: "a", count: 64),
        feedObservationID: String(repeating: "b", count: 64),
        capturedAtMilliseconds: 1_000,
        expiresAtMilliseconds: 91_001,
        observationWasTruncated: false,
        items: wire.items
      ).validatedSnapshot
    )
    XCTAssertNil(
      ChromeBridgeWireYouTubeFeedSnapshot(
        sourceTabID: 7,
        sourceWindowID: 3,
        sourceURL: "https://www.youtube.com/",
        sourceFingerprint: String(repeating: "a", count: 64),
        feedObservationID: String(repeating: "b", count: 64),
        capturedAtMilliseconds: 1_000,
        expiresAtMilliseconds: 91_000,
        observationWasTruncated: false,
        items: [
          ChromeBridgeWireYouTubeFeedItem(
            position: 1,
            videoID: "invalid",
            title: "Title",
            channel: "Channel",
            observationID: String(repeating: "c", count: 64)
          )
        ]
      ).validatedSnapshot
    )
  }

  func testVersionTwoYouTubeFixturesRoundTripTypedProtocol() throws {
    let feedResponse = try JSONDecoder().decode(
      ChromeBridgeResponse.self,
      from: fixtureData("youtube-feed-response-v2.json")
    )
    let snapshot = try XCTUnwrap(feedResponse.youTubeFeed?.validatedSnapshot)
    XCTAssertEqual(snapshot.items.first?.title, "Local Mac assistants")

    let openRequest = try JSONDecoder().decode(
      ChromeBridgeRequest.self,
      from: fixtureData("open-youtube-request-v2.json")
    )
    XCTAssertEqual(openRequest.version, ChromeBridgeRequest.protocolVersion)
    XCTAssertEqual(openRequest.operation, .openYouTubeVideo)
    XCTAssertEqual(openRequest.youTubeTarget?.videoID.value, "abcDEF123_-")

    let encoded = try JSONEncoder().encode(openRequest)
    XCTAssertEqual(try JSONDecoder().decode(ChromeBridgeRequest.self, from: encoded), openRequest)
  }

  func testVersionOneProtocolFixturesDecodeToValidatedTypedValues() throws {
    let listRequest = try JSONDecoder().decode(
      ChromeBridgeRequest.self,
      from: fixtureData("list-request-v1.json")
    )
    XCTAssertEqual(listRequest.operation, .listTabs)
    XCTAssertEqual(listRequest.maximumTabCount, 25)

    let listResponse = try JSONDecoder().decode(
      ChromeBridgeResponse.self,
      from: fixtureData("list-response-v1.json")
    )
    XCTAssertEqual(listResponse.status, .success)
    XCTAssertEqual(listResponse.tabs?.first?.validatedSnapshot?.title, "Example Domain")
    XCTAssertEqual(listResponse.observationWasTruncated, false)

    let activation = try JSONDecoder().decode(
      ChromeBridgeRequest.self,
      from: fixtureData("activate-request-v1.json")
    )
    XCTAssertEqual(activation.operation, .activateTab)
    XCTAssertEqual(activation.target?.tabID, 7)

    let failure = try JSONDecoder().decode(
      ChromeBridgeResponse.self,
      from: fixtureData("failure-response-v1.json")
    )
    XCTAssertEqual(failure.failureCode, .staleTab)
  }

  private func fixtureData(_ name: String) throws -> Data {
    let repositoryRoot =
      URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try Data(
      contentsOf:
        repositoryRoot
        .appendingPathComponent("Fixtures/ChromeNativeMessaging")
        .appendingPathComponent(name)
    )
  }
}
