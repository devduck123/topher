import AVFoundation

enum MicrophonePermissionState: Equatable, Sendable {
  case notDetermined
  case authorized
  case denied
  case restricted
}

/// The test seam around macOS microphone authorization.
///
/// Reading `authorizationStatus` never prompts. The live request closure is only
/// invoked by `MicrophonePermissionClient.requestAuthorization()`.
@MainActor
struct MicrophonePermissionEnvironment {
  let authorizationStatus: () -> AVAuthorizationStatus
  let requestAccess: () async -> Bool

  static let live = Self(
    authorizationStatus: {
      AVCaptureDevice.authorizationStatus(for: .audio)
    },
    requestAccess: {
      await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      }
    }
  )
}

@MainActor
struct MicrophonePermissionClient {
  private let environment: MicrophonePermissionEnvironment

  init(environment: MicrophonePermissionEnvironment? = nil) {
    self.environment = environment ?? .live
  }

  /// Returns the current state without displaying a system permission prompt.
  var currentState: MicrophonePermissionState {
    Self.state(for: environment.authorizationStatus())
  }

  /// Requests access only when macOS has not recorded a decision yet.
  ///
  /// Call this from an explicit user action, such as the first push-to-talk
  /// attempt. Calling it for an existing decision is a side-effect-free read.
  func requestAuthorization() async -> MicrophonePermissionState {
    let state = currentState
    guard state == .notDetermined else { return state }

    return await environment.requestAccess() ? .authorized : .denied
  }

  private static func state(for status: AVAuthorizationStatus) -> MicrophonePermissionState {
    switch status {
    case .notDetermined:
      .notDetermined
    case .authorized:
      .authorized
    case .denied:
      .denied
    case .restricted:
      .restricted
    @unknown default:
      // Unknown future states must fail closed rather than enabling capture.
      .restricted
    }
  }
}
