import Foundation

/// Applications that the first Topher slice is explicitly allowed to open.
///
/// Keeping this list application-owned prevents transcript or future model output
/// from becoming an unchecked bundle identifier.
public enum ApplicationTarget: String, CaseIterable, Equatable, Sendable {
  case chatGPT
  case chrome
  case notion
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
