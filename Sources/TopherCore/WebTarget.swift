import Foundation

/// Websites Topher may open directly without accepting an arbitrary URL.
public enum WebsiteTarget: String, CaseIterable, Equatable, Sendable {
  case crunchyroll
  case gmail
  case github
  case google
  case youtube

  public var displayName: String {
    switch self {
    case .crunchyroll:
      "Crunchyroll"
    case .gmail:
      "Gmail"
    case .github:
      "GitHub"
    case .google:
      "Google"
    case .youtube:
      "YouTube"
    }
  }

  var aliases: Set<String> {
    switch self {
    case .crunchyroll:
      ["crunchyroll", "crunchy roll", "crunchyroll com"]
    case .gmail:
      ["gmail", "gmail com", "my gmail", "gmail inbox", "my gmail inbox"]
    case .github:
      ["github", "git hub", "github com"]
    case .google:
      ["google", "google com", "google homepage"]
    case .youtube:
      ["youtube", "youtube com", "you tube"]
    }
  }

  static func matching(_ normalizedName: String) -> Self? {
    allCases.first { $0.aliases.contains(normalizedName) }
  }

  /// A bare `search <destination>` can be navigational for known web brands.
  /// Query-bearing provider forms such as `search YouTube for cats` are
  /// resolved before this rule.
  var acceptsBareSearchAsNavigation: Bool { true }

  var queryProvider: SearchProvider? {
    switch self {
    case .google:
      .google
    case .youtube:
      .youtube
    case .crunchyroll, .gmail, .github:
      nil
    }
  }
}

/// Browser-owned destinations that are not arbitrary web URLs.
public enum BrowserRouteTarget: String, CaseIterable, Equatable, Sendable {
  case chromeExtensions

  public var displayName: String {
    switch self {
    case .chromeExtensions:
      "Chrome Extensions"
    }
  }

  public var browser: ApplicationTarget {
    switch self {
    case .chromeExtensions:
      .chrome
    }
  }

  var aliases: Set<String> {
    switch self {
    case .chromeExtensions:
      [
        "chrome extensions", "google chrome extensions", "chrome extension manager",
        "chrome extensions page", "the chrome extensions page", "extensions in chrome",
      ]
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
