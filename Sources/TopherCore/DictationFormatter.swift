import Foundation

public enum DictationTextError: Error, Equatable, Sendable {
  case empty
  case tooLong
}

/// Text that is safe to hand to the focused-field insertion boundary.
///
/// This formatter deliberately performs presentation cleanup only. It does not
/// infer punctuation, rewrite vocabulary, or otherwise change the user's
/// meaning. Speech recognition context is responsible for terminology; richer
/// rewriting belongs in a future, separately measured layer.
public struct DictationText: Equatable, Sendable {
  public static let maximumCharacterCount = 16_384

  public let value: String

  public init(_ transcript: String) throws {
    let formatted = Self.format(transcript)
    guard !formatted.isEmpty else { throw DictationTextError.empty }
    guard formatted.count <= Self.maximumCharacterCount else {
      throw DictationTextError.tooLong
    }
    value = formatted
  }

  private static func format(_ transcript: String) -> String {
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

  private static let closingPunctuation: Set<Character> = [",", ".", "?", "!", ";", ":"]
}
