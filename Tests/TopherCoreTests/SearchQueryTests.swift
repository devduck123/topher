import XCTest

@testable import TopherCore

final class SearchQueryTests: XCTestCase {
  func testTrimsAValidQuery() {
    XCTAssertEqual(SearchQuery("  local models  ")?.value, "local models")
  }

  func testRejectsEmptyControlCharacterAndOversizedQueries() {
    XCTAssertNil(SearchQuery("   "))
    XCTAssertNil(SearchQuery("local\nmodels"))
    XCTAssertNil(
      SearchQuery(String(repeating: "a", count: SearchQuery.maximumUTF8ByteCount + 1))
    )
  }
}
