import Foundation

public enum TopherCommand: Equatable, Sendable {
  case activateChromeTab(ChromeTabTitleQuery)
  case identifyActiveChromeTab
  case listChromeTabs
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
  case uncertainDomain
  case unknownTarget
  case unsupportedAction
  case unsupportedPhrasing
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
