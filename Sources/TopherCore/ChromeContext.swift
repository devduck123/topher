import Foundation

public enum ChromeBridgeConstants {
  public static let nativeHostName = "dev.topher.chrome_bridge"
  public static let runtimeDirectoryName = "ChromeBridge"
  public static let socketFileName = "native-messaging.sock"
  public static let sessionTokenFileName = "session-token"
  public static let helperExecutableName = "TopherChromeBridgeHost"
  public static let maximumMessageByteCount = 65_536
}

/// A bounded user-authored title used only for exact deterministic tab matching.
public struct ChromeTabTitleQuery: Equatable, Sendable {
  public static let maximumUTF8ByteCount = 1_024

  public let value: String
  public let normalizedValue: String

  public init?(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      trimmed.utf8.count <= Self.maximumUTF8ByteCount,
      !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else { return nil }

    let normalized = Self.normalized(trimmed)
    guard !normalized.isEmpty else { return nil }
    self.value = trimmed
    normalizedValue = normalized
  }

  public func matches(_ title: String) -> Bool {
    Self.normalized(title) == normalizedValue
  }

  private static func normalized(_ value: String) -> String {
    value
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

/// A browser-supplied URL that has crossed Topher's typed validation boundary.
/// File, data, JavaScript, developer-tools, and other custom schemes are rejected.
public struct ChromeTabURL: Equatable, Sendable {
  public static let maximumUTF8ByteCount = 2_048
  public static let allowedSchemes = Set(["about", "chrome", "chrome-extension", "http", "https"])

  public let absoluteString: String

  public init?(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      trimmed.utf8.count <= Self.maximumUTF8ByteCount,
      !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      let components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      Self.allowedSchemes.contains(scheme),
      components.user == nil,
      components.password == nil
    else { return nil }

    switch scheme {
    case "http", "https", "chrome", "chrome-extension":
      guard let host = components.host, !host.isEmpty else { return nil }
    case "about":
      guard URL(string: trimmed) != nil else { return nil }
    default:
      return nil
    }

    absoluteString = trimmed
  }

  public var displayOrigin: String {
    guard
      let components = URLComponents(string: absoluteString),
      let scheme = components.scheme?.lowercased()
    else { return "supported Chrome page" }

    if scheme == "http" || scheme == "https" {
      return components.host ?? "supported web page"
    }
    if scheme == "about" {
      return absoluteString
    }
    return "\(scheme)://\(components.host ?? "page")"
  }
}

public struct ChromeTabFingerprint: Codable, Equatable, Sendable {
  public let value: String

  public init?(_ value: String) {
    guard
      value.count == 64,
      value.unicodeScalars.allSatisfy({
        CharacterSet(charactersIn: "0123456789abcdef").contains($0)
      })
    else { return nil }
    self.value = value
  }
}

public struct ChromeTabSnapshot: Equatable, Sendable {
  public static let maximumTitleUTF8ByteCount = 2_048

  public let tabID: Int
  public let windowID: Int
  public let index: Int
  public let active: Bool
  public let title: String
  public let url: ChromeTabURL
  public let fingerprint: ChromeTabFingerprint
  public let capturedAtMilliseconds: Int64

  public init?(
    tabID: Int,
    windowID: Int,
    index: Int,
    active: Bool,
    title: String,
    url: ChromeTabURL,
    fingerprint: ChromeTabFingerprint,
    capturedAtMilliseconds: Int64
  ) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      tabID >= 0,
      windowID >= 0,
      index >= 0,
      !trimmedTitle.isEmpty,
      trimmedTitle.utf8.count <= Self.maximumTitleUTF8ByteCount,
      !trimmedTitle.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      capturedAtMilliseconds > 0
    else { return nil }

    self.tabID = tabID
    self.windowID = windowID
    self.index = index
    self.active = active
    self.title = trimmedTitle
    self.url = url
    self.fingerprint = fingerprint
    self.capturedAtMilliseconds = capturedAtMilliseconds
  }

  public var activationTarget: ChromeTabActivationTarget {
    ChromeTabActivationTarget(
      tabID: tabID,
      windowID: windowID,
      fingerprint: fingerprint,
      capturedAtMilliseconds: capturedAtMilliseconds
    )
  }
}

public struct ChromeTabActivationTarget: Codable, Equatable, Sendable {
  public let tabID: Int
  public let windowID: Int
  public let fingerprint: ChromeTabFingerprint
  public let capturedAtMilliseconds: Int64

  public init(
    tabID: Int,
    windowID: Int,
    fingerprint: ChromeTabFingerprint,
    capturedAtMilliseconds: Int64
  ) {
    self.tabID = tabID
    self.windowID = windowID
    self.fingerprint = fingerprint
    self.capturedAtMilliseconds = capturedAtMilliseconds
  }
}

public enum ChromeBridgeOperation: String, Codable, Equatable, Sendable {
  case activateTab
  case cancel
  case getActiveTab
  case listTabs
}

public struct ChromeBridgeRequest: Codable, Equatable, Sendable {
  public static let protocolVersion = 1
  public static let maximumTabCount = 50

  public let version: Int
  public let requestID: UUID
  public let operation: ChromeBridgeOperation
  public let maximumTabCount: Int?
  public let target: ChromeTabActivationTarget?
  public let cancellationRequestID: UUID?

  private init(
    requestID: UUID,
    operation: ChromeBridgeOperation,
    maximumTabCount: Int? = nil,
    target: ChromeTabActivationTarget? = nil,
    cancellationRequestID: UUID? = nil
  ) {
    version = Self.protocolVersion
    self.requestID = requestID
    self.operation = operation
    self.maximumTabCount = maximumTabCount
    self.target = target
    self.cancellationRequestID = cancellationRequestID
  }

  public static func activeTab(requestID: UUID = UUID()) -> Self {
    Self(requestID: requestID, operation: .getActiveTab)
  }

  public static func listTabs(
    maximumTabCount: Int,
    requestID: UUID = UUID()
  ) -> Self? {
    guard (1...Self.maximumTabCount).contains(maximumTabCount) else { return nil }
    return Self(
      requestID: requestID,
      operation: .listTabs,
      maximumTabCount: maximumTabCount
    )
  }

  public static func activate(
    _ target: ChromeTabActivationTarget,
    requestID: UUID = UUID()
  ) -> Self {
    Self(requestID: requestID, operation: .activateTab, target: target)
  }

  public static func cancel(
    requestID: UUID,
    cancellationRequestID: UUID = UUID()
  ) -> Self {
    Self(
      requestID: cancellationRequestID,
      operation: .cancel,
      cancellationRequestID: requestID
    )
  }
}

public enum ChromeBridgeResponseStatus: String, Codable, Equatable, Sendable {
  case failure
  case success
}

public enum ChromeBridgeFailureCode: String, Codable, Equatable, Sendable {
  case activationOutcomeUnknown
  case browserFailure
  case canceled
  case duplicateRequest
  case excludedScheme
  case incognitoExcluded
  case invalidTarget
  case malformedRequest
  case messageTooLarge
  case noActiveTab
  case staleTab
  case targetNotFound
  case unsupportedOperation
  case unsupportedVersion
}

public struct ChromeBridgeWireTab: Codable, Equatable, Sendable {
  public let tabID: Int
  public let windowID: Int
  public let index: Int
  public let active: Bool
  public let title: String
  public let url: String
  public let fingerprint: String
  public let capturedAtMilliseconds: Int64

  public init(
    tabID: Int,
    windowID: Int,
    index: Int,
    active: Bool,
    title: String,
    url: String,
    fingerprint: String,
    capturedAtMilliseconds: Int64
  ) {
    self.tabID = tabID
    self.windowID = windowID
    self.index = index
    self.active = active
    self.title = title
    self.url = url
    self.fingerprint = fingerprint
    self.capturedAtMilliseconds = capturedAtMilliseconds
  }

  public var validatedSnapshot: ChromeTabSnapshot? {
    guard
      let url = ChromeTabURL(url),
      let fingerprint = ChromeTabFingerprint(fingerprint)
    else { return nil }
    return ChromeTabSnapshot(
      tabID: tabID,
      windowID: windowID,
      index: index,
      active: active,
      title: title,
      url: url,
      fingerprint: fingerprint,
      capturedAtMilliseconds: capturedAtMilliseconds
    )
  }
}

public struct ChromeBridgeResponse: Codable, Equatable, Sendable {
  public let version: Int
  public let requestID: UUID
  public let status: ChromeBridgeResponseStatus
  public let tab: ChromeBridgeWireTab?
  public let tabs: [ChromeBridgeWireTab]?
  public let excludedTabCount: Int?
  public let failureCode: ChromeBridgeFailureCode?

  public init(
    version: Int = ChromeBridgeRequest.protocolVersion,
    requestID: UUID,
    status: ChromeBridgeResponseStatus,
    tab: ChromeBridgeWireTab? = nil,
    tabs: [ChromeBridgeWireTab]? = nil,
    excludedTabCount: Int? = nil,
    failureCode: ChromeBridgeFailureCode? = nil
  ) {
    self.version = version
    self.requestID = requestID
    self.status = status
    self.tab = tab
    self.tabs = tabs
    self.excludedTabCount = excludedTabCount
    self.failureCode = failureCode
  }
}
