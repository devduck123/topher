import XCTest

@testable import TopherCore

final class DictationFormatterTests: XCTestCase {
  func testTrimsOuterWhitespaceAndNormalizesHorizontalSpacing() throws {
    let text = try DictationText("  dining   with\tDerek  ")

    XCTAssertEqual(text.value, "dining with Derek")
  }

  func testRemovesWhitespaceBeforeClosingPunctuationWithoutInventingPunctuation() throws {
    let text = try DictationText("ship build six , then stop")

    XCTAssertEqual(text.value, "ship build six, then stop")
    XCTAssertFalse(text.value.hasSuffix("."))
  }

  func testNormalizesLineEndingsAndPreservesLineBreaks() throws {
    let text = try DictationText("first line  \r\nsecond\tline\rthird")

    XCTAssertEqual(text.value, "first line\nsecond line\nthird")
  }

  func testPreservesDeveloperTerminologyAndCapitalization() throws {
    let text = try DictationText("open gidhub.com and inspect GraphQL, URLSession, and npm")

    XCTAssertEqual(
      text.value,
      "open gidhub.com and inspect GraphQL, URLSession, and npm"
    )
  }

  func testRejectsEmptyText() {
    XCTAssertThrowsError(try DictationText(" \n\t ")) { error in
      XCTAssertEqual(error as? DictationTextError, .empty)
    }
  }

  func testRejectsOversizedText() {
    XCTAssertThrowsError(
      try DictationText(String(repeating: "a", count: DictationText.maximumCharacterCount + 1))
    ) { error in
      XCTAssertEqual(error as? DictationTextError, .tooLong)
    }
  }
}
