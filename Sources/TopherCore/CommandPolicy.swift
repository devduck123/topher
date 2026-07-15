import Foundation

public enum PolicyDecision: Equatable, Sendable {
  case allowed
  case denied(reason: String)
}

/// The policy boundary is independent of how a command was proposed.
public struct CommandPolicy: Sendable {
  private let injectedEvaluation: (@Sendable (TopherCommand) -> PolicyDecision)?

  public init() {
    injectedEvaluation = nil
  }

  /// A focused test seam. Production uses the exhaustive registered-command
  /// policy below so adding a command still requires an explicit policy choice.
  init(evaluate: @escaping @Sendable (TopherCommand) -> PolicyDecision) {
    injectedEvaluation = evaluate
  }

  public func evaluate(_ command: TopherCommand) -> PolicyDecision {
    if let injectedEvaluation {
      return injectedEvaluation(command)
    }

    switch command {
    case .openApplication, .openWebsite, .searchWeb:
      return .allowed
    }
  }
}
