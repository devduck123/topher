import AppKit
import ApplicationServices

enum AccessibilityPermissionState: Equatable, Sendable {
  case authorized
  case notAuthorized
}

/// The test seam around macOS Accessibility authorization.
///
/// `isProcessTrusted` is a side-effect-free read. `promptForTrust` is only
/// invoked by an explicit user action.
@MainActor
struct AccessibilityPermissionEnvironment {
  let isProcessTrusted: () -> Bool
  let promptForTrust: () -> Bool

  static let live = Self(
    isProcessTrusted: {
      AXIsProcessTrusted()
    },
    promptForTrust: {
      // The imported C global is not concurrency-annotated. Its documented
      // string value is stable and avoids treating that global as mutable state.
      let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
      return AXIsProcessTrustedWithOptions(options)
    }
  )
}

@MainActor
struct AccessibilityPermissionClient {
  private let environment: AccessibilityPermissionEnvironment

  init(environment: AccessibilityPermissionEnvironment? = nil) {
    self.environment = environment ?? .live
  }

  /// Returns the current state without displaying a system prompt.
  var currentState: AccessibilityPermissionState {
    environment.isProcessTrusted() ? .authorized : .notAuthorized
  }

  /// Asks macOS to explain the permission only after an explicit user action.
  /// The system prompt is asynchronous, so callers should refresh after Topher
  /// becomes active again.
  func requestAuthorization() -> AccessibilityPermissionState {
    environment.promptForTrust() ? .authorized : .notAuthorized
  }

  func openSettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      )
    else { return }

    NSWorkspace.shared.open(url)
  }
}
