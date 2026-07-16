import Combine
import Foundation
import SwiftUI
import TopherCore

@MainActor
final class SpeechVocabularyController: ObservableObject {
  static let preferenceKey = "speechPersonalization.vocabularyEntries"
  static let maximumPersonalEntryCount = 40

  @Published private(set) var entries: [TranscriptVocabularyEntry]
  @Published private(set) var validationMessage: String?

  var vocabulary: TranscriptVocabulary {
    TranscriptVocabulary.developerDefaults.merging(entries)
  }

  var contextualStrings: [String] {
    vocabulary.contextualStrings
  }

  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    if let data = userDefaults.data(forKey: Self.preferenceKey),
      let decoded = try? JSONDecoder().decode([TranscriptVocabularyEntry].self, from: data)
    {
      entries = Array(
        decoded
          .compactMap(Self.validatedEntry)
          .prefix(Self.maximumPersonalEntryCount)
      )
    } else {
      entries = []
    }
  }

  @discardableResult
  func add(canonicalTerm: String, spokenFormsText: String) -> Bool {
    let canonical = canonicalTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    let spokenForms =
      spokenFormsText
      .split(separator: ",", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }

    guard Self.isValidPhrase(canonical) else {
      validationMessage = "Use a short term of up to 64 bytes."
      return false
    }
    guard spokenForms.count <= 5, spokenForms.allSatisfy(Self.isValidPhrase) else {
      validationMessage = "Use at most five short, comma-separated spoken variants."
      return false
    }

    let normalizedCanonical = Self.normalized(canonical)
    var updated = entries.filter { Self.normalized($0.canonicalTerm) != normalizedCanonical }
    guard updated.count < Self.maximumPersonalEntryCount else {
      validationMessage = "Personal vocabulary is limited to 40 terms."
      return false
    }

    updated.append(
      TranscriptVocabularyEntry(canonicalTerm: canonical, spokenForms: spokenForms)
    )
    entries = updated
    validationMessage = nil
    persist()
    return true
  }

  func remove(_ entry: TranscriptVocabularyEntry) {
    entries.removeAll { $0 == entry }
    validationMessage = nil
    persist()
  }

  func dismissValidationMessage() {
    validationMessage = nil
  }

  private func persist() {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    userDefaults.set(data, forKey: Self.preferenceKey)
  }

  private static func isValidPhrase(_ value: String) -> Bool {
    !value.isEmpty
      && value.utf8.count <= 64
      && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
  }

  private static func validatedEntry(
    _ entry: TranscriptVocabularyEntry
  ) -> TranscriptVocabularyEntry? {
    let canonical = entry.canonicalTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidPhrase(canonical) else { return nil }
    let spokenForms = entry.spokenForms
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter(isValidPhrase)
      .prefix(5)
    return TranscriptVocabularyEntry(
      canonicalTerm: canonical,
      spokenForms: Array(spokenForms)
    )
  }

  private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
  }
}

struct SpeechVocabularyView: View {
  @ObservedObject var vocabulary: SpeechVocabularyController

  @State private var isExpanded = false

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      SpeechVocabularyEditor(vocabulary: vocabulary)
        .padding(.top, 8)
    } label: {
      Label("Personal vocabulary", systemImage: "text.book.closed")
        .font(.caption)
    }
  }
}

struct SpeechVocabularyEditor: View {
  @ObservedObject var vocabulary: SpeechVocabularyController

  @State private var canonicalTerm = ""
  @State private var spokenForms = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        "Topher supplies canonical developer and personal terms to on-device speech. Known mis-transcriptions stay local to Topher and are used only when the corrected command maps to an allowlisted capability."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      TextField("Canonical term, e.g. GitLab", text: $canonicalTerm)
        .textFieldStyle(.roundedBorder)
      TextField("Known mis-transcriptions, comma-separated", text: $spokenForms)
        .textFieldStyle(.roundedBorder)

      HStack {
        Text(
          "\(vocabulary.entries.count)/\(SpeechVocabularyController.maximumPersonalEntryCount) personal terms"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer()

        Button("Add") {
          if vocabulary.add(
            canonicalTerm: canonicalTerm,
            spokenFormsText: spokenForms
          ) {
            canonicalTerm = ""
            spokenForms = ""
          }
        }
        .controlSize(.small)
        .disabled(canonicalTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }

      if let validationMessage = vocabulary.validationMessage {
        Text(validationMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }

      ForEach(Array(vocabulary.entries.enumerated()), id: \.offset) { _, entry in
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 1) {
            Text(entry.canonicalTerm)
              .font(.subheadline)
            if !entry.spokenForms.isEmpty {
              Text(entry.spokenForms.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          Spacer()

          Button(role: .destructive) {
            vocabulary.remove(entry)
          } label: {
            Image(systemName: "trash")
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Remove \(entry.canonicalTerm)")
        }
      }
    }
  }
}
