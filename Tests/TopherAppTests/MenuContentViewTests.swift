import XCTest

@testable import TopherApp

@MainActor
final class MenuContentViewTests: XCTestCase {
  func testMenuPanelHasDeterministicReadableSize() {
    XCTAssertEqual(MenuContentView.panelSize.width, 380)
    XCTAssertEqual(MenuContentView.panelSize.height, 460)
  }
}
