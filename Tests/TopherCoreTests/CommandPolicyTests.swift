import XCTest

@testable import TopherCore

final class CommandPolicyTests: XCTestCase {
  private let policy = CommandPolicy()

  func testAllowsRegisteredApplication() {
    XCTAssertEqual(policy.evaluate(.openApplication(.safari)), .allowed)
    let installed = InstalledApplicationTarget(
      displayName: "Figma",
      bundleIdentifier: "com.figma.Desktop"
    )
    let catalogPolicy = CommandPolicy(installedApplications: [installed])
    XCTAssertEqual(catalogPolicy.evaluate(.openInstalledApplication(installed)), .allowed)
    XCTAssertEqual(policy.evaluate(.identifyFrontmostApplication), .allowed)
  }

  func testDeniesAnInstalledApplicationIdentityOutsideTheLaunchCatalog() {
    let registered = InstalledApplicationTarget(
      displayName: "Figma",
      bundleIdentifier: "com.figma.Desktop"
    )
    let reconstructedOutsideCatalog = InstalledApplicationTarget(
      displayName: registered.displayName,
      bundleIdentifier: registered.bundleIdentifier,
      aliases: registered.aliases
    )
    let catalogPolicy = CommandPolicy(installedApplications: [registered])

    XCTAssertEqual(
      catalogPolicy.evaluate(.openInstalledApplication(reconstructedOutsideCatalog)),
      .denied(reason: "That application is not in this launch's catalog.")
    )
  }

  func testAllowsRegisteredWebCapabilities() {
    XCTAssertEqual(policy.evaluate(.openWebsite(.youtube)), .allowed)
    XCTAssertEqual(policy.evaluate(.openBrowserRoute(.chromeExtensions)), .allowed)

    let domain = HTTPSDomain("tnc.com")
    XCTAssertNotNil(domain)
    if let domain {
      XCTAssertEqual(policy.evaluate(.openDomain(domain)), .allowed)
    }

    let query = SearchQuery("local models")
    XCTAssertNotNil(query)
    if let query {
      XCTAssertEqual(policy.evaluate(.searchWeb(provider: .google, query: query)), .allowed)
      XCTAssertEqual(policy.evaluate(.searchUnknownDestination(query)), .allowed)
    }
  }

  func testAllowsRegisteredChromeReadsAndExplicitTabActivation() throws {
    let title = try XCTUnwrap(ChromeTabTitleQuery("Topher"))

    XCTAssertEqual(policy.evaluate(.identifyActiveChromeTab), .allowed)
    XCTAssertEqual(policy.evaluate(.listChromeTabs), .allowed)
    XCTAssertEqual(policy.evaluate(.activateChromeTab(title)), .allowed)
  }

  func testSupportsAnInjectedDenialWithoutChangingProductionPolicy() {
    let deniedPolicy = CommandPolicy { _ in
      .denied(reason: "User presence is required.")
    }

    XCTAssertEqual(
      deniedPolicy.evaluate(.openApplication(.notion)),
      .denied(reason: "User presence is required.")
    )
    XCTAssertEqual(policy.evaluate(.openApplication(.notion)), .allowed)
  }
}
