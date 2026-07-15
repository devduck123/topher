import Foundation

public enum TopherCommand: Equatable, Sendable {
  case openApplication(ApplicationTarget)
  case openWebsite(WebsiteTarget)
  case searchWeb(provider: SearchProvider, query: SearchQuery)
  case unsupported
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
