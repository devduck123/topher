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

  func testSelectsAlternativeWithMultipleIndependentlyKnownCanonicalizations() {
    let selector = DictationTranscriptSelector()

    let result = selector.select(
      primary: TranscriptHypothesis(
        text: "I build with React JS, next JS, for sale, and Kubernetti's."
      ),
      alternatives: [
        TranscriptHypothesis(text: "I build with React, Next.js, Vercel, and Kubernetes.")
      ]
    )

    XCTAssertEqual(
      result.selectedTranscript,
      "I build with React, Next.js, Vercel, and Kubernetes."
    )
    XCTAssertEqual(result.reason, .speechAlternative)
  }

  func testRiskySpokenFormRequiresExactAlternativeCorroboration() {
    let selector = DictationTranscriptSelector()
    let primary = TranscriptHypothesis(text: "The house is for sale")

    XCTAssertEqual(selector.select(primary: primary).selectedTranscript, primary.text)
    XCTAssertEqual(
      selector.select(
        primary: primary,
        alternatives: [TranscriptHypothesis(text: "The house has sold")]
      ).selectedTranscript,
      primary.text
    )
  }

  func testSelectsGitOnlyFromExactCorroboratingAlternative() {
    let selector = DictationTranscriptSelector()
    let primary = TranscriptHypothesis(text: "Get status.")

    XCTAssertEqual(selector.select(primary: primary).selectedTranscript, primary.text)
    let corrected = selector.select(
      primary: primary,
      alternatives: [TranscriptHypothesis(text: "git status.")]
    )
    XCTAssertEqual(corrected.selectedTranscript, "git status.")
    XCTAssertEqual(corrected.reason, .speechAlternative)

    XCTAssertEqual(
      selector.select(
        primary: primary,
        alternatives: [TranscriptHypothesis(text: "git diff.")]
      ).selectedTranscript,
      primary.text
    )
  }

  func testSelectsObservedDeveloperTermsOnlyFromExactAlternatives() {
    let selector = DictationTranscriptSelector()

    for (primary, alternative, expected) in [
      ("Hello, Kodex.", "Hello, Codex.", "Hello, Codex."),
      (
        "I am impending text at the beginning.",
        "I am prepending text at the beginning.",
        "I am prepending text at the beginning."
      ),
    ] {
      XCTAssertEqual(
        selector.select(
          primary: TranscriptHypothesis(text: primary),
          alternatives: [TranscriptHypothesis(text: alternative)]
        ).selectedTranscript,
        expected
      )
    }
  }

  func testObservedDeveloperTermCorrectionsNeverRewriteWithoutCorroboration() {
    let selector = DictationTranscriptSelector()

    XCTAssertEqual(
      selector.select(primary: TranscriptHypothesis(text: "Hello, Kodex.")).selectedTranscript,
      "Hello, Kodex."
    )
    XCTAssertEqual(
      selector.select(
        primary: TranscriptHypothesis(text: "Impending weather is approaching."),
        alternatives: [TranscriptHypothesis(text: "Bad weather is approaching.")]
      ).selectedTranscript,
      "Impending weather is approaching."
    )
  }

  func testRejectsAlternativeThatAlsoChangesGeneralProse() {
    let selector = DictationTranscriptSelector()
    let primary = TranscriptHypothesis(text: "I use React JS at work every day")

    let result = selector.select(
      primary: primary,
      alternatives: [TranscriptHypothesis(text: "We use React at work most days")]
    )

    XCTAssertEqual(result.selectedTranscript, primary.text)
    XCTAssertNil(result.reason)
  }

  func testPreservesPrimaryWhenMultipleDistinctCanonicalizedAlternativesAreValid() {
    let selector = DictationTranscriptSelector()
    let primary = TranscriptHypothesis(text: "I use React JS and gidhub")

    let result = selector.select(
      primary: primary,
      alternatives: [
        TranscriptHypothesis(text: "I use React and gidhub"),
        TranscriptHypothesis(text: "I use React and GitHub"),
      ]
    )

    XCTAssertEqual(result.selectedTranscript, primary.text)
    XCTAssertNil(result.reason)
  }

  func testRequiresWholePhraseBoundariesForEveryCanonicalization() {
    let selector = DictationTranscriptSelector()
    let primary = TranscriptHypothesis(text: "I use prereact JSbuild and notgidhub today")

    let result = selector.select(
      primary: primary,
      alternatives: [TranscriptHypothesis(text: "I use preReactbuild and notGitHub today")]
    )

    XCTAssertEqual(result.selectedTranscript, primary.text)
    XCTAssertNil(result.reason)
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
