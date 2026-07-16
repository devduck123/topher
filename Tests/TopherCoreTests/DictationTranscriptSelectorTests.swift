import XCTest

@testable import TopherCore

final class DictationTranscriptSelectorTests: XCTestCase {
  func testSelectsUniqueAlternativeEquivalentToKnownVocabularyCorrection() {
    let selector = DictationTranscriptSelector()

    let result = selector.select(
      primary: TranscriptHypothesis(text: "I pushed this to gidhub today", confidence: 0.8),
      alternatives: [TranscriptHypothesis(text: "I pushed this to GitHub today")]
    )

    XCTAssertEqual(result.rawTranscript, "I pushed this to gidhub today")
    XCTAssertEqual(result.selectedTranscript, "I pushed this to GitHub today")
    XCTAssertEqual(result.reason, .speechAlternative)
  }

  func testUsesPersonalVocabularySpokenForms() {
    let selector = DictationTranscriptSelector(
      vocabulary: TranscriptVocabulary(
        entries: [.init(canonicalTerm: "GPT-5 Pro", spokenForms: ["GPT 5 bro"])]
      )
    )

    let result = selector.select(
      primary: TranscriptHypothesis(text: "Use GPT 5 bro with high mode"),
      alternatives: [TranscriptHypothesis(text: "Use GPT-5 Pro with high mode")]
    )

    XCTAssertEqual(result.selectedTranscript, "Use GPT-5 Pro with high mode")
    XCTAssertEqual(result.reason, .speechAlternative)
  }

  func testPreservesPrimaryWhenAlternativeChangesUnrelatedProseOrIsAmbiguous() {
    let selector = DictationTranscriptSelector()
    let primary = TranscriptHypothesis(text: "I use gidhub every day")

    XCTAssertEqual(
      selector.select(
        primary: primary,
        alternatives: [TranscriptHypothesis(text: "I use GitHub all day")]
      ).selectedTranscript,
      primary.text
    )
    XCTAssertEqual(
      selector.select(
        primary: primary,
        alternatives: [
          TranscriptHypothesis(text: "I use GitHub every day"),
          TranscriptHypothesis(text: "I use gidhub every day"),
        ]
      ).selectedTranscript,
      "I use GitHub every day"
    )
  }
}
