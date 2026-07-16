import XCTest

@testable import TopherCore

final class TranscriptInterpreterTests: XCTestCase {
  private let interpreter = TranscriptInterpreter()

  func testKeepsAlreadySupportedPrimaryTranscript() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Open GitHub", confidence: 0.91),
      alternatives: [TranscriptHypothesis(text: "Open YouTube", confidence: 0.99)]
    )

    XCTAssertEqual(result.selectedTranscript, "Open GitHub")
    XCTAssertEqual(result.confidence, 0.91)
    XCTAssertNil(result.reason)
  }

  func testDoesNotCanonicalizeAnAlreadyResolvedWebsiteAlias() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Open crunchy roll", confidence: 0.71)
    )

    XCTAssertEqual(result.selectedTranscript, "Open crunchy roll")
    XCTAssertNil(result.reason)
  }

  func testDoesNotExpandChromeInsideAnAlreadyValidSearchQuery() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Search Chrome Extensions", confidence: 0.52)
    )

    XCTAssertEqual(result.selectedTranscript, "Search Chrome Extensions")
    XCTAssertNil(result.reason)
  }

  func testSelectsTheOnlySupportedSpeechAlternative() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Open kit hub", confidence: 0.4),
      alternatives: [
        TranscriptHypothesis(text: "Open GitHub", confidence: 0.8),
        TranscriptHypothesis(text: "Open bit tub", confidence: 0.6),
      ]
    )

    XCTAssertEqual(result.selectedTranscript, "Open GitHub")
    XCTAssertEqual(result.reason, .speechAlternative)
  }

  func testDoesNotChooseBetweenAlternativesThatResolveToDifferentCommands() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Open something", confidence: 0.4),
      alternatives: [
        TranscriptHypothesis(text: "Open GitHub", confidence: 0.8),
        TranscriptHypothesis(text: "Open YouTube", confidence: 0.7),
      ]
    )

    XCTAssertEqual(result.selectedTranscript, "Open something")
    XCTAssertNil(result.reason)
  }

  func testCorrectsKnownDeveloperVocabularyOnlyWhenItResolvesSafely() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Open gidhub")
    )

    XCTAssertEqual(result.rawTranscript, "Open gidhub")
    XCTAssertEqual(result.selectedTranscript, "Open GitHub")
    XCTAssertEqual(result.reason, .vocabularyCorrection)
  }

  func testDoesNotRewriteDeveloperTermsInsideUnsupportedFreeformText() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Delete the gidhub repository")
    )

    XCTAssertEqual(result.selectedTranscript, "Delete the gidhub repository")
    XCTAssertNil(result.reason)
  }

  func testPersonalVocabularyCanSafelyCorrectAKnownDestination() {
    let vocabulary = TranscriptVocabulary.developerDefaults.merging([
      TranscriptVocabularyEntry(canonicalTerm: "Crunchyroll", spokenForms: ["crunchy role"])
    ])
    let customInterpreter = TranscriptInterpreter(vocabulary: vocabulary)

    let result = customInterpreter.interpret(
      primary: TranscriptHypothesis(text: "Open crunchy role")
    )

    XCTAssertEqual(result.selectedTranscript, "Open Crunchyroll")
    XCTAssertEqual(result.reason, .vocabularyCorrection)
  }

  func testPersonalVocabularyCorrectsAWebQueryWithoutChangingItsProvider() {
    let vocabulary = TranscriptVocabulary.developerDefaults.merging([
      TranscriptVocabularyEntry(canonicalTerm: "GitLab", spokenForms: ["get lab"])
    ])
    let customInterpreter = TranscriptInterpreter(vocabulary: vocabulary)

    let result = customInterpreter.interpret(
      primary: TranscriptHypothesis(text: "Search get lab pipelines")
    )

    XCTAssertEqual(result.selectedTranscript, "Search GitLab pipelines")
    XCTAssertEqual(result.reason, .vocabularyCorrection)
  }

  func testPersonalVocabularyCannotRedirectAnAlreadySupportedTarget() {
    let vocabulary = TranscriptVocabulary.developerDefaults.merging([
      TranscriptVocabularyEntry(canonicalTerm: "YouTube", spokenForms: ["Google"])
    ])
    let customInterpreter = TranscriptInterpreter(vocabulary: vocabulary)

    let result = customInterpreter.interpret(
      primary: TranscriptHypothesis(text: "Open Google")
    )

    XCTAssertEqual(result.selectedTranscript, "Open Google")
    XCTAssertNil(result.reason)
  }

  func testVocabularyCorrectionRequiresWholePhraseBoundaries() {
    let result = interpreter.interpret(
      primary: TranscriptHypothesis(text: "Open notgidhub.com")
    )

    XCTAssertEqual(result.selectedTranscript, "Open notgidhub.com")
    XCTAssertNil(result.reason)
  }
}
