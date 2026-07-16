import Foundation
import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class SpeechVocabularyControllerTests: XCTestCase {
  func testPersistsPersonalTermsAndMergesSpokenFormsWithBuiltIns() throws {
    let suiteName = "TopherSpeechVocabularyTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let controller = SpeechVocabularyController(userDefaults: defaults)
    XCTAssertTrue(
      controller.add(
        canonicalTerm: "GitHub",
        spokenFormsText: "gidhub, get hub"
      )
    )

    let gitHub = try XCTUnwrap(
      controller.vocabulary.entries.first { $0.canonicalTerm == "GitHub" }
    )
    XCTAssertTrue(gitHub.spokenForms.contains("get hub"))
    XCTAssertTrue(controller.contextualStrings.contains("get hub"))

    let reloaded = SpeechVocabularyController(userDefaults: defaults)
    XCTAssertEqual(reloaded.entries, controller.entries)
  }

  func testRejectsEmptyAndOversizedTerms() {
    let controller = SpeechVocabularyController(
      userDefaults: UserDefaults(suiteName: UUID().uuidString)!
    )

    XCTAssertFalse(controller.add(canonicalTerm: "", spokenFormsText: ""))
    XCTAssertFalse(
      controller.add(canonicalTerm: String(repeating: "x", count: 65), spokenFormsText: "")
    )
    XCTAssertTrue(controller.entries.isEmpty)
  }

  func testDropsInvalidPersistedEntriesBeforeTheyReachSpeechContext() throws {
    let suiteName = "TopherSpeechVocabularyValidationTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let stored = [
      TranscriptVocabularyEntry(canonicalTerm: String(repeating: "x", count: 65)),
      TranscriptVocabularyEntry(
        canonicalTerm: "GitLab",
        spokenForms: ["get lab", String(repeating: "y", count: 65)]
      ),
    ]
    defaults.set(try JSONEncoder().encode(stored), forKey: SpeechVocabularyController.preferenceKey)

    let controller = SpeechVocabularyController(userDefaults: defaults)

    XCTAssertEqual(
      controller.entries,
      [TranscriptVocabularyEntry(canonicalTerm: "GitLab", spokenForms: ["get lab"])]
    )
  }
}
