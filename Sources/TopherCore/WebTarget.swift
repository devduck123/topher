import Foundation

/// Websites Topher may open directly without accepting an arbitrary URL.
public enum WebsiteTarget: String, CaseIterable, Equatable, Sendable {
  case google
  case youtube

  public var displayName: String {
    switch self {
    case .google:
      "Google"
    case .youtube:
      "YouTube"
    }
  }

  var aliases: Set<String> {
    switch self {
    case .google:
      ["google", "google com", "google homepage"]
    case .youtube:
      ["youtube", "youtube com", "you tube"]
    }
  }

  static func matching(_ normalizedName: String) -> Self? {
    allCases.first { $0.aliases.contains(normalizedName) }
  }
}

/// Search providers with application-owned URL construction.
public enum SearchProvider: String, Equatable, Sendable {
  case google
  case youtube

  public var displayName: String {
    switch self {
    case .google:
      "Google"
    case .youtube:
      "YouTube"
    }
  }
}

/// A bounded search value that can be safely encoded as one URL query item.
public struct SearchQuery: Equatable, Sendable {
  public static let maximumUTF8ByteCount = 512

  public let value: String

  public init?(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      trimmed.utf8.count <= Self.maximumUTF8ByteCount,
      trimmed.unicodeScalars.allSatisfy({
        !CharacterSet.controlCharacters.contains($0)
      })
    else {
      return nil
    }

    self.value = trimmed
  }
}
