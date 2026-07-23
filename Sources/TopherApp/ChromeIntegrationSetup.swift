import AppKit
import Darwin
import Foundation
import TopherCore

enum ChromeIntegrationReadiness: Equatable {
  case blocked
  case needsRegistration
  case needsRepair
  case ready
  case unavailable

  var title: String {
    switch self {
    case .blocked:
      "Chrome setup needs manual cleanup."
    case .needsRegistration:
      "Chrome bridge is not registered."
    case .needsRepair:
      "Chrome bridge points to another Topher build."
    case .ready:
      "Chrome bridge is registered for this Topher build."
    case .unavailable:
      "Chrome setup requires the signed Topher app bundle."
    }
  }

  var canConfigure: Bool {
    self == .needsRegistration || self == .needsRepair
  }
}

enum ChromeExtensionReadiness: Equatable {
  case checking
  case disconnected
  case ready
  case unavailable
  case youtubeAccessRequired

  var title: String {
    switch self {
    case .checking:
      "Checking the Topher extension…"
    case .disconnected:
      "Topher’s Chrome extension is not connected. Load or reload it in Chrome."
    case .ready:
      "Chrome extension connected; YouTube access is granted."
    case .unavailable:
      "Finish local Chrome bridge setup first."
    case .youtubeAccessRequired:
      "Chrome extension connected; grant YouTube access from its button."
    }
  }
}

enum ChromeIntegrationSetupError: Error {
  case blockedRegistration
  case helperUnavailable
  case insecureDirectory
  case registrationFailed
}

struct ChromeNativeHostRegistrationController {
  let manifestURL: URL
  let expectedHelperURL: URL
  let fileManager: FileManager

  static func live(fileManager: FileManager = .default, bundle: Bundle = .main) -> Self {
    let validator = ChromeNativeHostRegistrationValidator.live(
      fileManager: fileManager,
      bundle: bundle
    )
    return Self(
      manifestURL: validator.manifestURL,
      expectedHelperURL: validator.expectedHelperURL,
      fileManager: fileManager
    )
  }

  func readiness() -> ChromeIntegrationReadiness {
    guard
      ChromeNativeHostRegistrationValidator.isSecureRegularFile(
        expectedHelperURL,
        mustBeExecutable: true,
        requiresCurrentUserOwnership: false
      )
    else { return .unavailable }

    var information = stat()
    guard lstat(manifestURL.path, &information) == 0 else {
      return errno == ENOENT ? .needsRegistration : .blocked
    }

    let validator = ChromeNativeHostRegistrationValidator(
      manifestURL: manifestURL,
      expectedHelperURL: expectedHelperURL
    )
    if validator.validates(extensionOrigin: ChromeBridgeConstants.extensionOrigin) {
      return .ready
    }
    return repairableManifest() ? .needsRepair : .blocked
  }

  func installOrRepair() throws {
    guard
      ChromeNativeHostRegistrationValidator.isSecureRegularFile(
        expectedHelperURL,
        mustBeExecutable: true,
        requiresCurrentUserOwnership: false
      )
    else { throw ChromeIntegrationSetupError.helperUnavailable }

    switch readiness() {
    case .ready:
      return
    case .needsRegistration:
      break
    case .needsRepair:
      guard repairableManifest() else {
        throw ChromeIntegrationSetupError.blockedRegistration
      }
    case .blocked:
      throw ChromeIntegrationSetupError.blockedRegistration
    case .unavailable:
      throw ChromeIntegrationSetupError.helperUnavailable
    }

    let directoryURL = manifestURL.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: directoryURL.path) {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: NSNumber(value: 0o700)]
      )
    }
    guard secureOwnedDirectory(directoryURL) else {
      throw ChromeIntegrationSetupError.insecureDirectory
    }

    let manifest = ChromeNativeHostManifest(
      name: ChromeBridgeConstants.nativeHostName,
      description: "Topher Chrome context bridge",
      path: expectedHelperURL.standardizedFileURL.path,
      type: "stdio",
      allowedOrigins: [ChromeBridgeConstants.extensionOrigin]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(manifest)
    guard data.count <= 8_192 else {
      throw ChromeIntegrationSetupError.registrationFailed
    }
    try data.write(to: manifestURL, options: .atomic)
    guard chmod(manifestURL.path, 0o600) == 0 else {
      throw ChromeIntegrationSetupError.registrationFailed
    }

    let validator = ChromeNativeHostRegistrationValidator(
      manifestURL: manifestURL,
      expectedHelperURL: expectedHelperURL
    )
    guard validator.validates(extensionOrigin: ChromeBridgeConstants.extensionOrigin) else {
      throw ChromeIntegrationSetupError.registrationFailed
    }
  }

  private func repairableManifest() -> Bool {
    guard
      ChromeNativeHostRegistrationValidator.isSecureRegularFile(
        manifestURL,
        mustBeExecutable: false,
        requiresCurrentUserOwnership: true
      ),
      let information = try? fileManager.attributesOfItem(atPath: manifestURL.path),
      let size = information[.size] as? NSNumber,
      size.intValue <= 8_192,
      let data = try? Data(contentsOf: manifestURL),
      let manifest = try? JSONDecoder().decode(ChromeNativeHostManifest.self, from: data),
      manifest.name == ChromeBridgeConstants.nativeHostName,
      manifest.type == "stdio",
      manifest.allowedOrigins.count == 1,
      let origin = manifest.allowedOrigins.first,
      ChromeNativeHostRegistrationValidator.isExactExtensionOrigin(origin),
      manifest.path.hasPrefix("/"),
      isTopherHelperPath(manifest.path)
    else { return false }
    return true
  }

  private func isTopherHelperPath(_ path: String) -> Bool {
    let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
    return components.suffix(4) == [
      "Topher.app", "Contents", "Helpers", ChromeBridgeConstants.helperExecutableName,
    ]
  }

  private func secureOwnedDirectory(_ url: URL) -> Bool {
    var information = stat()
    guard lstat(url.path, &information) == 0 else { return false }
    return
      information.st_mode & S_IFMT == S_IFDIR
      && information.st_uid == geteuid()
      && information.st_mode & (S_IWGRP | S_IWOTH) == 0
  }
}

@MainActor
struct ChromeIntegrationSetupClient {
  let readiness: () -> ChromeIntegrationReadiness
  let configure: () throws -> Void
  let showExtensionFolder: () -> Bool
  let openExtensionManager: () async -> ActionOutcome

  static func live(
    controller: ChromeNativeHostRegistrationController = .live(),
    bundle: Bundle = .main,
    workspace: NSWorkspace = .shared
  ) -> Self {
    Self(
      readiness: controller.readiness,
      configure: controller.installOrRepair,
      showExtensionFolder: {
        guard
          let folderURL = bundle.resourceURL?.appendingPathComponent(
            "ChromeExtension",
            isDirectory: true
          ),
          FileManager.default.fileExists(atPath: folderURL.path)
        else { return false }
        workspace.activateFileViewerSelecting([folderURL])
        return true
      },
      openExtensionManager: {
        await BrowserRouteOpenCapability().execute(.chromeExtensions)
      }
    )
  }

  static let unavailable = Self(
    readiness: { .unavailable },
    configure: { throw ChromeIntegrationSetupError.helperUnavailable },
    showExtensionFolder: { false },
    openExtensionManager: {
      .failed(message: "Chrome Extensions could not be opened.")
    }
  )
}
