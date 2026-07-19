import XCTest

@testable import TopherApp

@MainActor
final class AccessibilityPermissionClientTests: XCTestCase {
  func testStateReadNeverPrompts() {
    var promptCount = 0
    let client = AccessibilityPermissionClient(
      environment: AccessibilityPermissionEnvironment(
        isProcessTrusted: { false },
        promptForTrust: {
          promptCount += 1
          return false
        }
      )
    )

    XCTAssertEqual(client.currentState, .notAuthorized)
    XCTAssertEqual(promptCount, 0)
  }

  func testExplicitRequestPromptsAndMapsCurrentResult() {
    var promptCount = 0
    let client = AccessibilityPermissionClient(
      environment: AccessibilityPermissionEnvironment(
        isProcessTrusted: { true },
        promptForTrust: {
          promptCount += 1
          return true
        }
      )
    )

    XCTAssertEqual(client.requestAuthorization(), .authorized)
    XCTAssertEqual(promptCount, 1)
  }
}
