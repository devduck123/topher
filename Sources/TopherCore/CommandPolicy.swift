import Foundation

public enum PolicyDecision: Equatable, Sendable {
  case allowed
  case denied(reason: String)
}

/// The policy boundary is independent of how a command was proposed.
public struct CommandPolicy: Sendable {
  public init() {}

  public func evaluate(_ command: TopherCommand) -> PolicyDecision {
    switch command {
    case .openApplication, .openWebsite, .searchWeb:
      .allowed
    case .unsupported:
      .denied(reason: "Topher only executes registered commands.")
    }
  }
}
