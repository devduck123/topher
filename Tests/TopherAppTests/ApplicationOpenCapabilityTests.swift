import Foundation
import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class ApplicationOpenCapabilityTests: XCTestCase {
  func testDeclaresItsAuthority() {
    XCTAssertEqual(
      ApplicationOpenCapability.descriptor,
      CapabilityDescriptor(
        identifier: "openApplication",
        access: .changesState,
        risk: .lowRiskReversible
      )
    )
  }

  func testOpensTheResolvedApplicationURL() async {
    let expectedURL = URL(fileURLWithPath: "/Applications/Safari.app")
    var requestedBundleIdentifier: String?
    var openedURL: URL?
    let workspace = ApplicationWorkspace(
      applicationURL: { bundleIdentifier in
        requestedBundleIdentifier = bundleIdentifier
        return expectedURL
      },
      openApplication: { url in
        openedURL = url
      }
    )

    let outcome = await ApplicationOpenCapability(workspace: workspace).execute(.safari)

    XCTAssertEqual(requestedBundleIdentifier, ApplicationTarget.safari.bundleIdentifier)
    XCTAssertEqual(openedURL, expectedURL)
    XCTAssertEqual(outcome, .succeeded(message: "Opened Safari."))
  }

  func testReportsAnApplicationThatIsNotInstalled() async {
    var attemptedOpen = false
    let workspace = ApplicationWorkspace(
      applicationURL: { _ in nil },
      openApplication: { _ in attemptedOpen = true }
    )

    let outcome = await ApplicationOpenCapability(workspace: workspace).execute(.chrome)

    XCTAssertFalse(attemptedOpen)
    XCTAssertEqual(outcome, .failed(message: "Google Chrome is not installed."))
  }

  func testOpensADiscoveredApplicationByRevalidatedBundleIdentifier() async {
    let expectedURL = URL(fileURLWithPath: "/Applications/Figma.app")
    let target = InstalledApplicationTarget(
      displayName: "Figma",
      bundleIdentifier: "com.figma.Desktop"
    )
    var requestedBundleIdentifier: String?
    var openedURL: URL?
    let capability = ApplicationOpenCapability(
      workspace: ApplicationWorkspace(
        applicationURL: {
          requestedBundleIdentifier = $0
          return expectedURL
        },
        openApplication: { openedURL = $0 }
      )
    )

    let outcome = await capability.execute(target)

    XCTAssertEqual(requestedBundleIdentifier, "com.figma.Desktop")
    XCTAssertEqual(openedURL, expectedURL)
    XCTAssertEqual(outcome, .succeeded(message: "Opened Figma."))
  }

  func testReportsAWorkspaceLaunchError() async {
    struct LaunchError: LocalizedError {
      var errorDescription: String? { "Simulated launch failure" }
    }

    let workspace = ApplicationWorkspace(
      applicationURL: { _ in URL(fileURLWithPath: "/Applications/Safari.app") },
      openApplication: { _ in throw LaunchError() }
    )

    let outcome = await ApplicationOpenCapability(workspace: workspace).execute(.safari)

    XCTAssertEqual(
      outcome,
      .failed(message: "Could not open Safari: Simulated launch failure")
    )
  }
}
