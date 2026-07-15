import AVFoundation
import XCTest

@testable import TopherApp

@MainActor
final class MicrophonePermissionClientTests: XCTestCase {
  func testMapsEveryCurrentMacOSAuthorizationStatus() {
    let cases: [(AVAuthorizationStatus, MicrophonePermissionState)] = [
      (.notDetermined, .notDetermined),
      (.authorized, .authorized),
      (.denied, .denied),
      (.restricted, .restricted),
    ]

    for (authorizationStatus, expectedState) in cases {
      let client = MicrophonePermissionClient(
        environment: MicrophonePermissionEnvironment(
          authorizationStatus: { authorizationStatus },
          requestAccess: {
            XCTFail("A state read must not request access")
            return false
          }
        )
      )

      XCTAssertEqual(client.currentState, expectedState)
    }
  }

  func testRequestsOnlyAfterExplicitRequestWhenNotDetermined() async {
    var requestCount = 0
    let client = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { .notDetermined },
        requestAccess: {
          requestCount += 1
          return true
        }
      )
    )

    XCTAssertEqual(client.currentState, .notDetermined)
    XCTAssertEqual(requestCount, 0)

    let result = await client.requestAuthorization()

    XCTAssertEqual(result, .authorized)
    XCTAssertEqual(requestCount, 1)
  }

  func testMapsARejectedPromptToDenied() async {
    let client = MicrophonePermissionClient(
      environment: MicrophonePermissionEnvironment(
        authorizationStatus: { .notDetermined },
        requestAccess: { false }
      )
    )

    let result = await client.requestAuthorization()

    XCTAssertEqual(result, .denied)
  }

  func testDoesNotRequestAgainForRecordedDecisions() async {
    let cases: [(AVAuthorizationStatus, MicrophonePermissionState)] = [
      (.authorized, .authorized),
      (.denied, .denied),
      (.restricted, .restricted),
    ]
    var requestCount = 0

    for (authorizationStatus, expectedState) in cases {
      let client = MicrophonePermissionClient(
        environment: MicrophonePermissionEnvironment(
          authorizationStatus: { authorizationStatus },
          requestAccess: {
            requestCount += 1
            return true
          }
        )
      )

      let result = await client.requestAuthorization()
      XCTAssertEqual(result, expectedState)
    }

    XCTAssertEqual(requestCount, 0)
  }
}
