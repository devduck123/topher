import Foundation
import XCTest

@testable import TopherApp

final class InstalledApplicationCatalogTests: XCTestCase {
  func testDiscoversAppsAtTheBoundedSupportedDepthAndBuildsUsefulAliases() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try makeApplication(
      at: root.appendingPathComponent("Figma.app", isDirectory: true),
      bundleIdentifier: "com.figma.Desktop",
      displayName: "Figma"
    )
    try makeApplication(
      at:
        root
        .appendingPathComponent("Utilities", isDirectory: true)
        .appendingPathComponent("GitHub Desktop.app", isDirectory: true),
      bundleIdentifier: "com.github.GitHubClient",
      displayName: "GitHub Desktop"
    )
    try makeApplication(
      at:
        root
        .appendingPathComponent("Too", isDirectory: true)
        .appendingPathComponent("Deep", isDirectory: true)
        .appendingPathComponent("Ignored.app", isDirectory: true),
      bundleIdentifier: "com.example.Ignored",
      displayName: "Ignored"
    )

    let catalog = InstalledApplicationCatalog.discover(roots: [root])

    XCTAssertEqual(catalog.applications.map(\.displayName), ["Figma", "GitHub Desktop"])
    let github = try XCTUnwrap(
      catalog.applications.first { $0.bundleIdentifier == "com.github.GitHubClient" }
    )
    XCTAssertTrue(github.aliases.contains("github desktop"))
    XCTAssertTrue(github.aliases.contains("github"))
  }

  func testIgnoresBundlesWithoutAValidIdentifier() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    try makeApplication(
      at: root.appendingPathComponent("Invalid.app", isDirectory: true),
      bundleIdentifier: "invalid identifier",
      displayName: "Invalid"
    )

    XCTAssertTrue(InstalledApplicationCatalog.discover(roots: [root]).applications.isEmpty)
  }

  func testDoesNotFollowSymlinkedApplicationsOutsideTheCatalogRoot() throws {
    let container = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    let root = container.appendingPathComponent("Applications", isDirectory: true)
    let externalApplication = container.appendingPathComponent(
      "External.app",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: container) }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try makeApplication(
      at: externalApplication,
      bundleIdentifier: "com.example.External",
      displayName: "External"
    )
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("Linked.app"),
      withDestinationURL: externalApplication
    )

    XCTAssertTrue(InstalledApplicationCatalog.discover(roots: [root]).applications.isEmpty)
  }

  private func makeApplication(
    at applicationURL: URL,
    bundleIdentifier: String,
    displayName: String
  ) throws {
    let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(
      at: contentsURL,
      withIntermediateDirectories: true
    )
    let plist: [String: Any] = [
      "CFBundleIdentifier": bundleIdentifier,
      "CFBundleDisplayName": displayName,
      "CFBundleName": displayName,
      "CFBundlePackageType": "APPL",
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
  }
}
