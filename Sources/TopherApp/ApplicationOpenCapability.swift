import AppKit
import TopherCore

/// The smallest test seam around the shared `NSWorkspace` instance.
@MainActor
struct ApplicationWorkspace {
  let applicationURL: (String) -> URL?
  let openApplication: (URL) async throws -> Void

  static var live: Self {
    let workspace = NSWorkspace.shared
    return Self(
      applicationURL: { bundleIdentifier in
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
      },
      openApplication: { applicationURL in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true

        _ = try await workspace.openApplication(
          at: applicationURL,
          configuration: configuration
        )
      }
    )
  }
}

@MainActor
final class ApplicationOpenCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "openApplication",
    access: .changesState,
    risk: .lowRiskReversible
  )

  private let workspace: ApplicationWorkspace

  init(workspace: ApplicationWorkspace? = nil) {
    self.workspace = workspace ?? .live
  }

  func execute(_ target: ApplicationTarget) async -> ActionOutcome {
    guard
      let applicationURL = workspace.applicationURL(target.bundleIdentifier)
    else {
      return .failed(message: "\(target.displayName) is not installed.")
    }

    do {
      try await workspace.openApplication(applicationURL)
      return .succeeded(message: "Opened \(target.displayName).")
    } catch {
      return .failed(message: "Could not open \(target.displayName): \(error.localizedDescription)")
    }
  }
}
