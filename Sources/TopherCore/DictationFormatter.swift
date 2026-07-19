import Foundation

public enum DictationTextError: Error, Equatable, Sendable {
  case empty
  case tooLong
}

public enum DictationPolishPolicy: Equatable, Sendable {
  case conservative
  case presentationOnly
}

public struct DictationPause: Equatable, Sendable {
  public let boundaryUTF16Offset: Int
  public let durationMilliseconds: UInt64

  public init(boundaryUTF16Offset: Int, durationMilliseconds: UInt64) {
    self.boundaryUTF16Offset = boundaryUTF16Offset
    self.durationMilliseconds = durationMilliseconds
  }
}

/// Conservative presentation normalization shared by dictation and typed
/// command payloads. It only rewrites an explicitly spoken slash between two
/// short, uppercase technical tokens such as `UI slash UX`; ordinary prose and
/// the original diagnostic transcript remain unchanged.
enum SpokenTechnicalNotation {
  static func normalizing(in transcript: String) -> (text: String, changed: Bool) {
    let source = transcript as NSString
    let expression = try? NSRegularExpression(
      pattern: #"\b([A-Z][A-Z0-9]{0,11})\s+slash\s+([A-Z][A-Z0-9]{0,11})\b"#
    )
    let matches =
      expression?.matches(
        in: transcript,
        range: NSRange(location: 0, length: source.length)
      ) ?? []
    guard !matches.isEmpty else { return (transcript, false) }

    let output = NSMutableString(string: transcript)
    for match in matches.reversed() {
      let left = source.substring(with: match.range(at: 1))
      let right = source.substring(with: match.range(at: 2))
      output.replaceCharacters(in: match.range, with: "\(left)/\(right)")
    }
    return (output as String, true)
  }
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
  public let joinedShortPause: Bool
  public let normalizedSpokenPunctuation: Bool

  public init(
    _ transcript: String,
    pauses: [DictationPause] = [],
    polishPolicy: DictationPolishPolicy = .conservative
  ) throws {
    let pauseResult = Self.joiningShortPauseContinuations(in: transcript, pauses: pauses)
    let punctuationResult = SpokenTechnicalNotation.normalizing(in: pauseResult.text)
    let presentationText = Self.formatPresentation(punctuationResult.text)
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
    joinedShortPause = pauseResult.changed
    normalizedSpokenPunctuation = punctuationResult.changed
  }

  public var removedRepeatedSpeech: Bool {
    removedRepeatedWordCount > 0
  }

  public var interpretationReason: TranscriptInterpretationReason? {
    if removedRepeatedSpeech { return .dictationDisfluencyCleanup }
    if joinedShortPause { return .dictationPauseJoin }
    if normalizedSpokenPunctuation { return .dictationSpokenPunctuation }
    return nil
  }

  private static func joiningShortPauseContinuations(
    in transcript: String,
    pauses: [DictationPause]
  ) -> (text: String, changed: Bool) {
    guard !pauses.isEmpty else { return (transcript, false) }
    let source = transcript as NSString
    let expression = try? NSRegularExpression(pattern: #"\.\s+And\s+([A-Za-z]+)"#)
    let matches =
      expression?.matches(
        in: transcript,
        range: NSRange(location: 0, length: source.length)
      ) ?? []
    var replacements: [NSRange] = []

    for match in matches {
      guard match.numberOfRanges == 2 else { continue }
      let nextWord = source.substring(with: match.range(at: 1)).lowercased()
      guard continuationWords.contains(nextWord) else { continue }
      let matchedText = source.substring(with: match.range)
      guard let andRange = matchedText.range(of: "And") else { continue }
      let prefixLength = (matchedText[..<andRange.lowerBound] as Substring).utf16.count
      let periodEnd = match.range.location + 1
      let andStart = match.range.location + prefixLength
      guard
        pauses.contains(where: {
          $0.durationMilliseconds <= maximumContinuationPauseMilliseconds
            && $0.boundaryUTF16Offset >= periodEnd
            && $0.boundaryUTF16Offset <= andStart
        })
      else { continue }
      replacements.append(
        NSRange(location: match.range.location, length: andStart + 3 - match.range.location)
      )
    }

    guard !replacements.isEmpty else { return (transcript, false) }
    let output = NSMutableString(string: transcript)
    for range in replacements.sorted(by: { $0.location > $1.location }) {
      output.replaceCharacters(in: range, with: " and")
    }
    return (output as String, true)
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
  private static let maximumContinuationPauseMilliseconds: UInt64 = 700
  private static let continuationWords: Set<String> = [
    "add", "also", "continue", "dictate", "do", "include", "keep", "make", "say", "ship",
    "test", "then", "type", "use", "work", "write",
  ]
  private static let intentionalRepeatedWords: Set<String> = [
    "again", "blah", "bye", "go", "ha", "had", "hear", "ho", "more", "never", "night",
    "no", "so", "that", "there", "very", "win",
  ]
}
