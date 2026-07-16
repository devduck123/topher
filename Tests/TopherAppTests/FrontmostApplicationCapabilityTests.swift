import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class FrontmostApplicationCapabilityTests: XCTestCase {
  func testDeclaresReadOnlyStateAccess() {
    XCTAssertEqual(
      FrontmostApplicationCapability.descriptor,
      CapabilityDescriptor(
        identifier: "frontmostApplication",
        access: .readsState,
        risk: .readOnly
      )
    )
  }

  func testReportsTheFrontmostApplicationWithoutAnotherPermission() {
    let capability = FrontmostApplicationCapability(
      workspace: FrontmostApplicationWorkspace(applicationName: { "Google Chrome" })
    )

    XCTAssertEqual(
      capability.execute(),
      .succeeded(message: "You're using Google Chrome.")
    )
  }

  func testFailsClearlyWhenMacOSDoesNotExposeAnApplication() {
    let capability = FrontmostApplicationCapability(
      workspace: FrontmostApplicationWorkspace(applicationName: { nil })
    )

    XCTAssertEqual(
      capability.execute(),
      .failed(message: "I couldn't identify the app you're using.")
    )
  }
}
