import Foundation

public enum TopherCommand: Equatable, Sendable {
  case activateChromeTab(ChromeTabTitleQuery)
  case identifyActiveChromeTab
  case listChromeTabs
  case readYouTubeFeed
  case openYouTubeFeedItem(YouTubeFeedSelection)
  case openApplication(ApplicationTarget)
  case openInstalledApplication(InstalledApplicationTarget)
  case openBrowserRoute(BrowserRouteTarget)
  case openDomain(HTTPSDomain)
  case openWebsite(WebsiteTarget)
  case searchWeb(provider: SearchProvider, query: SearchQuery)
  case searchUnknownDestination(SearchQuery)
  case identifyFrontmostApplication
}

public enum UnsupportedCommandReason: String, Codable, Equatable, Sendable {
  case ambiguousTarget
  case applicationNotFound
  case compoundRequest
  case contextRequired
  case dictationModeRequired
  case emptyInput
  case missingValue
  case youTubeFeedRequired
  case youTubeSelectionAmbiguous
  case youTubeSelectionRequired
  case uncertainDomain
  case unknownTarget
  case unsupportedAction
  case unsupportedPhrasing
}

/// Narrows otherwise ambiguous language to a recent YouTube feed turn. This
/// state never contains page data and never grants execution authority.
public enum YouTubeFollowUpScope: Equatable, Sendable {
  case unavailable
  case feedAvailable
}

public struct CommandResolutionContext: Equatable, Sendable {
  public static let none = Self(youTubeFollowUpScope: .unavailable, youTubeFeedItemCount: nil)

  public let youTubeFollowUpScope: YouTubeFollowUpScope
  public let youTubeFeedItemCount: Int?

  public init(
    youTubeFollowUpScope: YouTubeFollowUpScope,
    youTubeFeedItemCount: Int? = nil
  ) {
    self.youTubeFollowUpScope = youTubeFollowUpScope
    self.youTubeFeedItemCount = youTubeFeedItemCount
  }
}

/// The deterministic resolver either produces a typed executable proposal or
/// declines the text. Unsupported input never crosses the policy boundary as a
/// command.
public enum CommandResolution: Equatable, Sendable {
  case resolved(TopherCommand)
  case unsupported(reason: UnsupportedCommandReason)
}

public enum ActionRisk: String, Equatable, Sendable {
  case readOnly
  case lowRiskReversible
  case sensitive
  case destructive
}

public enum ActionAccess: String, Equatable, Sendable {
  case readsState
  case changesState
}

public struct CapabilityDescriptor: Equatable, Sendable {
  public let identifier: String
  public let access: ActionAccess
  public let risk: ActionRisk

  public init(identifier: String, access: ActionAccess, risk: ActionRisk) {
    self.identifier = identifier
    self.access = access
    self.risk = risk
  }
}

public enum ActionOutcome: Equatable, Sendable {
  case succeeded(message: String)
  case failed(message: String)
}
