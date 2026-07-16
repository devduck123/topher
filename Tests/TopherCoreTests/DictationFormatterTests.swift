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

  func testNormalizesSpokenSlashOnlyBetweenStrongDeveloperTokens() throws {
    let text = try DictationText("I am working on UI slash UX changes")

    XCTAssertEqual(text.value, "I am working on UI/UX changes")
    XCTAssertTrue(text.normalizedSpokenPunctuation)
    XCTAssertEqual(text.interpretationReason, .dictationSpokenPunctuation)

    XCTAssertEqual(
      try DictationText("Use and slash or as literal words").value,
      "Use and slash or as literal words"
    )
  }

  func testJoinsOnlyTimedShortPauseAndFragments() throws {
    let transcript = "I wish I could type my code out. And dictate everything sometimes."
    let boundary = ("I wish I could type my code out." as NSString).length
    let text = try DictationText(
      transcript,
      pauses: [.init(boundaryUTF16Offset: boundary, durationMilliseconds: 420)]
    )

    XCTAssertEqual(
      text.value,
      "I wish I could type my code out and dictate everything sometimes."
    )
    XCTAssertTrue(text.joinedShortPause)
    XCTAssertEqual(text.interpretationReason, .dictationPauseJoin)
  }

  func testPreservesLongPausesAndLikelyNewSentenceSubjects() throws {
    let first = "I finished the work."
    let boundary = (first as NSString).length
    XCTAssertEqual(
      try DictationText(
        first + " And started testing.",
        pauses: [.init(boundaryUTF16Offset: boundary, durationMilliseconds: 900)]
      ).value,
      first + " And started testing."
    )
    XCTAssertEqual(
      try DictationText(
        first + " And we deployed it.",
        pauses: [.init(boundaryUTF16Offset: boundary, durationMilliseconds: 300)]
      ).value,
      first + " And we deployed it."
    )
    XCTAssertEqual(
      try DictationText(
        first + " And Tommy reviewed it.",
        pauses: [.init(boundaryUTF16Offset: boundary, durationMilliseconds: 300)]
      ).value,
      first + " And Tommy reviewed it."
    )
  }

  func testConservativelyRemovesAdjacentSpokenRestarts() throws {
    let singleWord = try DictationText("I I think we should ship this")
    XCTAssertEqual(singleWord.value, "I think we should ship this")
    XCTAssertEqual(singleWord.removedRepeatedWordCount, 1)

    let phrase = try DictationText("I want to I want to ship this today")
    XCTAssertEqual(phrase.value, "I want to ship this today")
    XCTAssertEqual(phrase.removedRepeatedWordCount, 3)

    let repeatedRestart = try DictationText("we we we should test this")
    XCTAssertEqual(repeatedRestart.value, "we should test this")
    XCTAssertEqual(repeatedRestart.removedRepeatedWordCount, 2)
  }

  func testPreservesIntentionalOrAmbiguousRepetition() throws {
    for transcript in [
      "I had had enough",
      "I think that that is correct",
      "This is very very useful",
      "No no problem",
      "Compare API API clients",
      "Use version 2 2 times",
      "Keep the final word word",
      "Repeat, repeat after me",
      "first line\nfirst line continues",
    ] {
      XCTAssertEqual(try DictationText(transcript).value, transcript)
    }
  }

  func testPresentationOnlyPolicyNeverRemovesRepeatedSpeech() throws {
    let text = try DictationText(
      "I I think this is useful",
      polishPolicy: .presentationOnly
    )

    XCTAssertEqual(text.value, "I I think this is useful")
    XCTAssertFalse(text.removedRepeatedSpeech)
  }

  func testLongRepeatedChainUsesTheBoundedCleanupPath() throws {
    let transcript = String(repeating: "we ", count: 4_000) + "should stop"

    let text = try DictationText(transcript)

    XCTAssertEqual(text.value, "we should stop")
    XCTAssertEqual(text.removedRepeatedWordCount, 3_999)
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
