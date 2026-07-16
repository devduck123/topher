import Foundation

public enum DictationTextError: Error, Equatable, Sendable {
  case empty
  case tooLong
}

public enum DictationPolishPolicy: Equatable, Sendable {
  case conservative
  case presentationOnly
}

/// Text that is safe to hand to the focused-field insertion boundary.
///
/// Presentation cleanup is always applied. The default conservative polish may
/// also remove a bounded adjacent restart such as "I I think" while preserving
/// punctuation boundaries and common intentional repetition. It never invokes
/// a model, infers punctuation, or rewrites vocabulary.
public struct DictationText: Equatable, Sendable {
  public static let maximumCharacterCount = 16_384

  public let value: String
  public let removedRepeatedWordCount: Int

  public init(
    _ transcript: String,
    polishPolicy: DictationPolishPolicy = .conservative
  ) throws {
    let presentationText = Self.formatPresentation(transcript)
    let polishResult =
      switch polishPolicy {
      case .conservative:
        Self.removingRepeatedSpeech(from: presentationText)
      case .presentationOnly:
        (text: presentationText, removedWordCount: 0)
      }
    let formatted = polishResult.text
    guard !formatted.isEmpty else { throw DictationTextError.empty }
    guard formatted.count <= Self.maximumCharacterCount else {
      throw DictationTextError.tooLong
    }
    value = formatted
    removedRepeatedWordCount = polishResult.removedWordCount
  }

  public var removedRepeatedSpeech: Bool {
    removedRepeatedWordCount > 0
  }

  private static func formatPresentation(_ transcript: String) -> String {
    let normalizedNewlines =
      transcript
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    var output = ""
    var pendingHorizontalWhitespace = false

    for character in normalizedNewlines {
      if character == "\n" {
        while output.last == " " {
          output.removeLast()
        }
        output.append(character)
        pendingHorizontalWhitespace = false
        continue
      }

      if character.isWhitespace {
        pendingHorizontalWhitespace = true
        continue
      }

      if pendingHorizontalWhitespace, !output.isEmpty, output.last != "\n",
        !Self.closingPunctuation.contains(character)
      {
        output.append(" ")
      }
      pendingHorizontalWhitespace = false
      output.append(character)
    }

    return output
  }

  private static func removingRepeatedSpeech(
    from text: String
  ) -> (text: String, removedWordCount: Int) {
    guard text.count <= maximumCharacterCount, !text.isEmpty else {
      return (text, 0)
    }

    var words: [Word] = []
    var cursor = text.startIndex
    text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) {
      substring,
      range,
      _,
      _ in
      guard let substring else { return }
      words.append(
        Word(
          leading: String(text[cursor..<range.lowerBound]),
          value: substring
        )
      )
      cursor = range.upperBound
    }
    let trailing = String(text[cursor...])
    guard words.count >= 3 else { return (text, 0) }

    var polishedWords: [Word] = []
    polishedWords.reserveCapacity(words.count)
    var removedWordCount = 0

    for (index, word) in words.enumerated() {
      polishedWords.append(word)
      guard index + 1 < words.count else { continue }

      while let repeatedSpan = repeatedSpanAtTail(of: polishedWords) {
        polishedWords.removeLast(repeatedSpan)
        removedWordCount += repeatedSpan
      }
    }

    guard removedWordCount > 0 else { return (text, 0) }
    let polished =
      polishedWords.reduce(into: "") { output, word in
        output += word.leading
        output += word.value
      } + trailing
    return (polished, removedWordCount)
  }

  private static func repeatedSpanAtTail(of words: [Word]) -> Int? {
    let maximumSpan = min(3, words.count / 2)
    guard maximumSpan > 0 else { return nil }

    for span in stride(from: maximumSpan, through: 1, by: -1) {
      let firstIndex = words.count - (2 * span)
      let secondIndex = firstIndex + span
      guard isAutomaticCleanupCandidate(words[firstIndex..<secondIndex]) else {
        continue
      }
      guard words[(firstIndex + 1)...].allSatisfy({ $0.leading == " " }) else {
        continue
      }
      guard
        (0..<span).allSatisfy({ offset in
          normalized(words[firstIndex + offset].value)
            == normalized(words[secondIndex + offset].value)
        })
      else {
        continue
      }
      return span
    }
    return nil
  }

  private static func isAutomaticCleanupCandidate(_ words: ArraySlice<Word>) -> Bool {
    guard !words.isEmpty else { return false }
    if words.count == 1, let word = words.first,
      intentionalRepeatedWords.contains(normalized(word.value))
    {
      return false
    }
    return words.allSatisfy { word in
      let value = word.value
      guard !value.contains(where: \Character.isNumber) else { return false }
      if normalized(value) == "i" { return true }

      let letters = value.filter(\Character.isLetter)
      guard letters.count > 1 else { return false }
      return !letters.allSatisfy(\Character.isUppercase)
    }
  }

  private static func normalized(_ word: String) -> String {
    word.lowercased()
  }

  private struct Word: Equatable, Sendable {
    let leading: String
    let value: String
  }

  private static let closingPunctuation: Set<Character> = [",", ".", "?", "!", ";", ":"]
  private static let intentionalRepeatedWords: Set<String> = [
    "again", "blah", "bye", "go", "ha", "had", "hear", "ho", "more", "never", "night",
    "no", "so", "that", "there", "very", "win",
  ]
}
