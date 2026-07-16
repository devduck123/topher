import AppKit
import TopherCore

@MainActor
struct FrontmostApplicationWorkspace {
  let applicationName: () -> String?

  static var live: Self {
    Self(applicationName: {
      NSWorkspace.shared.frontmostApplication?.localizedName
    })
  }
}

/// Reads only the identity macOS already exposes for the active application.
/// This does not inspect windows, tabs, accessibility trees, or screen pixels.
@MainActor
final class FrontmostApplicationCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "frontmostApplication",
    access: .readsState,
    risk: .readOnly
  )

  private let workspace: FrontmostApplicationWorkspace

  init(workspace: FrontmostApplicationWorkspace? = nil) {
    self.workspace = workspace ?? .live
  }

  func execute() -> ActionOutcome {
    guard
      let name = workspace.applicationName()?.trimmingCharacters(in: .whitespacesAndNewlines),
      !name.isEmpty
    else {
      return .failed(message: "I couldn't identify the app you're using.")
    }
    return .succeeded(message: "You're using \(name).")
  }
}
