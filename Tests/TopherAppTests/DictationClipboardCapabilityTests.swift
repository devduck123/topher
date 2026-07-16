import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class DictationClipboardCapabilityTests: XCTestCase {
  func testDeclaresItsAuthority() {
    XCTAssertEqual(DictationClipboardCapability.descriptor.access, .changesState)
    XCTAssertEqual(DictationClipboardCapability.descriptor.risk, .lowRiskReversible)
  }

  func testCopyWritesExactFormattedTextOnce() throws {
    var writes: [String] = []
    let capability = DictationClipboardCapability(
      environment: DictationClipboardEnvironment(writeString: {
        writes.append($0)
        return true
      })
    )

    XCTAssertTrue(capability.copy(try DictationText("hello   world")))
    XCTAssertEqual(writes, ["hello world"])
  }

  func testCopyReportsPasteboardFailure() throws {
    let capability = DictationClipboardCapability(
      environment: DictationClipboardEnvironment(writeString: { _ in false })
    )

    XCTAssertFalse(capability.copy(try DictationText("hello")))
  }
}
