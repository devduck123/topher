import Foundation

public enum ChromeBridgeConstants {
  public static let extensionID = "mhbppdheppcibhhcnhnfockmfpcfhndj"
  public static let extensionOrigin = "chrome-extension://\(extensionID)/"
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

/// A YouTube video identifier accepted only at Topher's typed browser boundary.
/// Watch destinations are constructed from this value; page-provided URLs never
/// cross into the mutation request.
public struct YouTubeVideoID: Codable, Equatable, Hashable, Sendable {
  public static let characterCount = 11

  public let value: String

  public init?(_ value: String) {
    guard
      value.count == Self.characterCount,
      value.unicodeScalars.allSatisfy({
        CharacterSet(
          charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
        )
        .contains($0)
      })
    else { return nil }
    self.value = value
  }

  public var watchURL: URL {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.youtube.com"
    components.path = "/watch"
    components.queryItems = [URLQueryItem(name: "v", value: value)]
    return components.url!
  }
}

public struct YouTubeObservationID: Codable, Equatable, Hashable, Sendable {
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

/// The only page route whose DOM Topher may inspect in this slice.
public struct YouTubeFeedSourceURL: Equatable, Sendable {
  public static let maximumUTF8ByteCount = 2_048

  public let absoluteString: String

  public init?(_ value: String) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      trimmed.utf8.count <= Self.maximumUTF8ByteCount,
      !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      let components = URLComponents(string: trimmed),
      components.scheme?.lowercased() == "https",
      components.host?.lowercased() == "www.youtube.com",
      components.port == nil,
      components.user == nil,
      components.password == nil,
      components.fragment == nil,
      components.path.isEmpty || components.path == "/"
    else { return nil }

    absoluteString = trimmed
  }
}

public struct YouTubeVideoTitleQuery: Equatable, Sendable {
  public static let maximumUTF8ByteCount = 512

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
    let decomposed = value
      .decomposedStringWithCompatibilityMapping
      .lowercased(with: Locale(identifier: "en_US_POSIX"))
    let withoutMarks = String(
      decomposed.unicodeScalars.filter {
        !CharacterSet.nonBaseCharacters.contains($0)
      }
    )
    return
      withoutMarks
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

public enum YouTubeFeedSelection: Equatable, Sendable {
  case ordinal(Int)
  case title(YouTubeVideoTitleQuery)

  public var kind: YouTubeFeedSelectionKind {
    switch self {
    case .ordinal: .ordinal
    case .title: .title
    }
  }
}

public enum YouTubeFeedSelectionKind: String, Codable, Equatable, Sendable {
  case ordinal
  case title
}

public struct YouTubeFeedItem: Equatable, Sendable {
  public static let maximumTitleUTF8ByteCount = 512
  public static let maximumChannelUTF8ByteCount = 256

  public let position: Int
  public let videoID: YouTubeVideoID
  public let title: String
  public let channel: String
  public let observationID: YouTubeObservationID
  public let titleMatchIsUnique: Bool

  public init?(
    position: Int,
    videoID: YouTubeVideoID,
    title: String,
    channel: String,
    observationID: YouTubeObservationID,
    titleMatchIsUnique: Bool
  ) {
    let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedChannel = channel.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      (1...ChromeBridgeRequest.maximumYouTubeFeedItemCount).contains(position),
      !trimmedTitle.isEmpty,
      trimmedTitle.utf8.count <= Self.maximumTitleUTF8ByteCount,
      !trimmedTitle.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
      !trimmedChannel.isEmpty,
      trimmedChannel.utf8.count <= Self.maximumChannelUTF8ByteCount,
      !trimmedChannel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    else { return nil }

    self.position = position
    self.videoID = videoID
    self.title = trimmedTitle
    self.channel = trimmedChannel
    self.observationID = observationID
    self.titleMatchIsUnique = titleMatchIsUnique
  }
}

public struct YouTubeFeedSnapshot: Equatable, Sendable {
  public static let maximumLifetimeMilliseconds: Int64 = 90_000

  public let sourceTabID: Int
  public let sourceWindowID: Int
  public let sourceURL: YouTubeFeedSourceURL
  public let sourceFingerprint: ChromeTabFingerprint
  public let feedObservationID: YouTubeObservationID
  public let capturedAtMilliseconds: Int64
  public let expiresAtMilliseconds: Int64
  public let presentationWasTruncated: Bool
  public let titleObservationWasComplete: Bool
  public let items: [YouTubeFeedItem]

  public init?(
    sourceTabID: Int,
    sourceWindowID: Int,
    sourceURL: YouTubeFeedSourceURL,
    sourceFingerprint: ChromeTabFingerprint,
    feedObservationID: YouTubeObservationID,
    capturedAtMilliseconds: Int64,
    expiresAtMilliseconds: Int64,
    presentationWasTruncated: Bool,
    titleObservationWasComplete: Bool,
    items: [YouTubeFeedItem]
  ) {
    guard
      sourceTabID >= 0,
      sourceWindowID >= 0,
      capturedAtMilliseconds > 0,
      expiresAtMilliseconds > capturedAtMilliseconds,
      expiresAtMilliseconds - capturedAtMilliseconds <= Self.maximumLifetimeMilliseconds,
      !items.isEmpty,
      items.count <= ChromeBridgeRequest.maximumYouTubeFeedItemCount,
      items.enumerated().allSatisfy({ $0.element.position == $0.offset + 1 }),
      Set(items.map(\.videoID)).count == items.count,
      Set(items.map(\.observationID)).count == items.count
    else { return nil }

    self.sourceTabID = sourceTabID
    self.sourceWindowID = sourceWindowID
    self.sourceURL = sourceURL
    self.sourceFingerprint = sourceFingerprint
    self.feedObservationID = feedObservationID
    self.capturedAtMilliseconds = capturedAtMilliseconds
    self.expiresAtMilliseconds = expiresAtMilliseconds
    self.presentationWasTruncated = presentationWasTruncated
    self.titleObservationWasComplete = titleObservationWasComplete
    self.items = items
  }

  public func openTarget(
    for item: YouTubeFeedItem,
    selection: YouTubeFeedSelection
  ) -> YouTubeVideoOpenTarget {
    YouTubeVideoOpenTarget(
      sourceTabID: sourceTabID,
      sourceWindowID: sourceWindowID,
      sourceURL: sourceURL.absoluteString,
      sourceFingerprint: sourceFingerprint,
      feedObservationID: feedObservationID,
      capturedAtMilliseconds: capturedAtMilliseconds,
      expiresAtMilliseconds: expiresAtMilliseconds,
      position: item.position,
      videoID: item.videoID,
      itemObservationID: item.observationID,
      selectionKind: selection.kind
    )
  }
}

public struct YouTubeVideoOpenTarget: Codable, Equatable, Sendable {
  public let sourceTabID: Int
  public let sourceWindowID: Int
  public let sourceURL: String
  public let sourceFingerprint: ChromeTabFingerprint
  public let feedObservationID: YouTubeObservationID
  public let capturedAtMilliseconds: Int64
  public let expiresAtMilliseconds: Int64
  public let position: Int
  public let videoID: YouTubeVideoID
  public let itemObservationID: YouTubeObservationID
  public let selectionKind: YouTubeFeedSelectionKind

  public init(
    sourceTabID: Int,
    sourceWindowID: Int,
    sourceURL: String,
    sourceFingerprint: ChromeTabFingerprint,
    feedObservationID: YouTubeObservationID,
    capturedAtMilliseconds: Int64,
    expiresAtMilliseconds: Int64,
    position: Int,
    videoID: YouTubeVideoID,
    itemObservationID: YouTubeObservationID,
    selectionKind: YouTubeFeedSelectionKind
  ) {
    self.sourceTabID = sourceTabID
    self.sourceWindowID = sourceWindowID
    self.sourceURL = sourceURL
    self.sourceFingerprint = sourceFingerprint
    self.feedObservationID = feedObservationID
    self.capturedAtMilliseconds = capturedAtMilliseconds
    self.expiresAtMilliseconds = expiresAtMilliseconds
    self.position = position
    self.videoID = videoID
    self.itemObservationID = itemObservationID
    self.selectionKind = selectionKind
  }
}

public enum ChromeBridgeOperation: String, Codable, Equatable, Sendable {
  case activateTab
  case cancel
  case getActiveTab
  case getIntegrationStatus
  case getYouTubeFeed
  case listTabs
  case openYouTubeVideo
}

public struct ChromeBridgeRequest: Codable, Equatable, Sendable {
  public static let protocolVersion = 3
  public static let maximumTabCount = 50
  public static let maximumYouTubeFeedItemCount = 20

  public let version: Int
  public let requestID: UUID
  public let operation: ChromeBridgeOperation
  public let maximumTabCount: Int?
  public let target: ChromeTabActivationTarget?
  public let youTubeTarget: YouTubeVideoOpenTarget?
  public let cancellationRequestID: UUID?

  private init(
    requestID: UUID,
    operation: ChromeBridgeOperation,
    maximumTabCount: Int? = nil,
    target: ChromeTabActivationTarget? = nil,
    youTubeTarget: YouTubeVideoOpenTarget? = nil,
    cancellationRequestID: UUID? = nil
  ) {
    version = Self.protocolVersion
    self.requestID = requestID
    self.operation = operation
    self.maximumTabCount = maximumTabCount
    self.target = target
    self.youTubeTarget = youTubeTarget
    self.cancellationRequestID = cancellationRequestID
  }

  public static func activeTab(requestID: UUID = UUID()) -> Self {
    Self(requestID: requestID, operation: .getActiveTab)
  }

  public static func integrationStatus(requestID: UUID = UUID()) -> Self {
    Self(requestID: requestID, operation: .getIntegrationStatus)
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

  public static func youTubeFeed(requestID: UUID = UUID()) -> Self {
    Self(requestID: requestID, operation: .getYouTubeFeed)
  }

  public static func openYouTubeVideo(
    _ target: YouTubeVideoOpenTarget,
    requestID: UUID = UUID()
  ) -> Self {
    Self(requestID: requestID, operation: .openYouTubeVideo, youTubeTarget: target)
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
  case navigationOutcomeUnknown
  case noActiveTab
  case staleTab
  case staleYouTubeFeed
  case targetNotFound
  case unsupportedOperation
  case unsupportedVersion
  case unsupportedYouTubePage
  case youTubeFeedChanged
  case youTubeFeedUnavailable
  case youTubePermissionRequired
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

public struct ChromeBridgeWireYouTubeFeedItem: Codable, Equatable, Sendable {
  public let position: Int
  public let videoID: String
  public let title: String
  public let channel: String
  public let observationID: String
  public let titleMatchIsUnique: Bool

  public init(
    position: Int,
    videoID: String,
    title: String,
    channel: String,
    observationID: String,
    titleMatchIsUnique: Bool
  ) {
    self.position = position
    self.videoID = videoID
    self.title = title
    self.channel = channel
    self.observationID = observationID
    self.titleMatchIsUnique = titleMatchIsUnique
  }

  public var validatedItem: YouTubeFeedItem? {
    guard
      let videoID = YouTubeVideoID(videoID),
      let observationID = YouTubeObservationID(observationID)
    else { return nil }
    return YouTubeFeedItem(
      position: position,
      videoID: videoID,
      title: title,
      channel: channel,
      observationID: observationID,
      titleMatchIsUnique: titleMatchIsUnique
    )
  }
}

public struct ChromeBridgeWireYouTubeFeedSnapshot: Codable, Equatable, Sendable {
  public let sourceTabID: Int
  public let sourceWindowID: Int
  public let sourceURL: String
  public let sourceFingerprint: String
  public let feedObservationID: String
  public let capturedAtMilliseconds: Int64
  public let expiresAtMilliseconds: Int64
  public let presentationWasTruncated: Bool
  public let titleObservationWasComplete: Bool
  public let items: [ChromeBridgeWireYouTubeFeedItem]

  public init(
    sourceTabID: Int,
    sourceWindowID: Int,
    sourceURL: String,
    sourceFingerprint: String,
    feedObservationID: String,
    capturedAtMilliseconds: Int64,
    expiresAtMilliseconds: Int64,
    presentationWasTruncated: Bool,
    titleObservationWasComplete: Bool,
    items: [ChromeBridgeWireYouTubeFeedItem]
  ) {
    self.sourceTabID = sourceTabID
    self.sourceWindowID = sourceWindowID
    self.sourceURL = sourceURL
    self.sourceFingerprint = sourceFingerprint
    self.feedObservationID = feedObservationID
    self.capturedAtMilliseconds = capturedAtMilliseconds
    self.expiresAtMilliseconds = expiresAtMilliseconds
    self.presentationWasTruncated = presentationWasTruncated
    self.titleObservationWasComplete = titleObservationWasComplete
    self.items = items
  }

  public var validatedSnapshot: YouTubeFeedSnapshot? {
    guard
      let sourceURL = YouTubeFeedSourceURL(sourceURL),
      let sourceFingerprint = ChromeTabFingerprint(sourceFingerprint),
      let feedObservationID = YouTubeObservationID(feedObservationID)
    else { return nil }
    let validatedItems = items.compactMap(\.validatedItem)
    guard validatedItems.count == items.count else { return nil }
    return YouTubeFeedSnapshot(
      sourceTabID: sourceTabID,
      sourceWindowID: sourceWindowID,
      sourceURL: sourceURL,
      sourceFingerprint: sourceFingerprint,
      feedObservationID: feedObservationID,
      capturedAtMilliseconds: capturedAtMilliseconds,
      expiresAtMilliseconds: expiresAtMilliseconds,
      presentationWasTruncated: presentationWasTruncated,
      titleObservationWasComplete: titleObservationWasComplete,
      items: validatedItems
    )
  }
}

public struct ChromeBridgeResponse: Codable, Equatable, Sendable {
  public let version: Int
  public let requestID: UUID
  public let status: ChromeBridgeResponseStatus
  public let tab: ChromeBridgeWireTab?
  public let tabs: [ChromeBridgeWireTab]?
  public let youTubeFeed: ChromeBridgeWireYouTubeFeedSnapshot?
  public let excludedTabCount: Int?
  public let observationWasTruncated: Bool?
  public let youTubePermissionGranted: Bool?
  public let failureCode: ChromeBridgeFailureCode?

  public init(
    version: Int = ChromeBridgeRequest.protocolVersion,
    requestID: UUID,
    status: ChromeBridgeResponseStatus,
    tab: ChromeBridgeWireTab? = nil,
    tabs: [ChromeBridgeWireTab]? = nil,
    youTubeFeed: ChromeBridgeWireYouTubeFeedSnapshot? = nil,
    excludedTabCount: Int? = nil,
    observationWasTruncated: Bool? = nil,
    youTubePermissionGranted: Bool? = nil,
    failureCode: ChromeBridgeFailureCode? = nil
  ) {
    self.version = version
    self.requestID = requestID
    self.status = status
    self.tab = tab
    self.tabs = tabs
    self.youTubeFeed = youTubeFeed
    self.excludedTabCount = excludedTabCount
    self.observationWasTruncated = observationWasTruncated
    self.youTubePermissionGranted = youTubePermissionGranted
    self.failureCode = failureCode
  }
}
