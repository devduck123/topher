import Foundation

public enum PolicyDecision: Equatable, Sendable {
  case allowed
  case denied(reason: String)
}

/// The policy boundary is independent of how a command was proposed.
public struct CommandPolicy: Sendable {
  private let injectedEvaluation: (@Sendable (TopherCommand) -> PolicyDecision)?
  private let installedApplications: Set<InstalledApplicationTarget>

  public init(installedApplications: [InstalledApplicationTarget] = []) {
    injectedEvaluation = nil
    self.installedApplications = Set(installedApplications)
  }

  /// A focused test seam. Production uses the exhaustive registered-command
  /// policy below so adding a command still requires an explicit policy choice.
  init(evaluate: @escaping @Sendable (TopherCommand) -> PolicyDecision) {
    injectedEvaluation = evaluate
    installedApplications = []
  }

  public func evaluate(_ command: TopherCommand) -> PolicyDecision {
    if let injectedEvaluation {
      return injectedEvaluation(command)
    }

    switch command {
    case .activateChromeTab, .identifyActiveChromeTab, .identifyFrontmostApplication,
      .listChromeTabs, .openYouTubeFeedItem, .readYouTubeFeed:
      return .allowed
    case .openInstalledApplication(let target):
      guard installedApplications.contains(target) else {
        return .denied(reason: "That application is not in this launch's catalog.")
      }
      return .allowed
    case .openApplication, .openBrowserRoute, .openDomain, .openWebsite, .searchWeb,
      .searchUnknownDestination:
      return .allowed
    }
  }
}
