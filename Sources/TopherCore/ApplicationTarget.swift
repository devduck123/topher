import Foundation

/// Applications that the first Topher slice is explicitly allowed to open.
///
/// Keeping this list application-owned prevents transcript or future model output
/// from becoming an unchecked bundle identifier.
public enum ApplicationTarget: String, CaseIterable, Equatable, Sendable {
  case chatGPT
  case chrome
  case notion
  case notes
  case safari
  case visualStudioCode
  case xcode

  public var displayName: String {
    switch self {
    case .chatGPT:
      "ChatGPT"
    case .chrome:
      "Google Chrome"
    case .notion:
      "Notion"
    case .notes:
      "Notes"
    case .safari:
      "Safari"
    case .visualStudioCode:
      "Visual Studio Code"
    case .xcode:
      "Xcode"
    }
  }

  public var bundleIdentifier: String {
    switch self {
    case .chatGPT:
      "com.openai.codex"
    case .chrome:
      "com.google.Chrome"
    case .notion:
      "notion.id"
    case .notes:
      "com.apple.Notes"
    case .safari:
      "com.apple.Safari"
    case .visualStudioCode:
      "com.microsoft.VSCode"
    case .xcode:
      "com.apple.dt.Xcode"
    }
  }

  var aliases: Set<String> {
    switch self {
    case .chatGPT:
      ["chatgpt", "chat gpt", "chat g p t", "codex", "chatgpt app", "codex app"]
    case .chrome:
      ["chrome", "google chrome"]
    case .notion:
      ["notion", "notion app", "notion desktop"]
    case .notes:
      ["notes", "notes app", "apple notes", "my notes"]
    case .safari:
      ["safari"]
    case .visualStudioCode:
      ["visual studio code", "vs code", "vscode"]
    case .xcode:
      ["xcode", "x code"]
    }
  }

  static func matching(_ normalizedName: String) -> Self? {
    allCases.first { $0.aliases.contains(normalizedName) }
  }
}

/// An installed application discovered from bounded, user-visible macOS
/// application directories at launch.
///
/// The command carries a bundle identifier instead of an application path.
/// Execution resolves that identifier through `NSWorkspace` again, so speech
/// text never becomes an unchecked filesystem path or launch argument.
public struct InstalledApplicationTarget: Equatable, Hashable, Sendable {
  public let displayName: String
  public let bundleIdentifier: String
  public let aliases: Set<String>
  // The production policy receives the same catalog values as the resolver.
  // A separately reconstructed target has different provenance and is denied.
  private let catalogIdentity: UUID

  public init(
    displayName: String,
    bundleIdentifier: String,
    aliases: Set<String> = []
  ) {
    catalogIdentity = UUID()
    self.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.bundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    self.aliases = Set(
      aliases
        .union([displayName])
        .map(Self.normalized)
        .filter { !$0.isEmpty }
    )
  }

  static func normalized(_ value: String) -> String {
    value
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}
