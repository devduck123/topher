import Darwin
import Foundation
import OSLog
import TopherCore

struct ChromeBridgeRuntimePaths: Sendable {
  let directoryURL: URL
  let socketURL: URL
  let sessionTokenURL: URL

  static func live(fileManager: FileManager = .default) -> Self {
    let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let directory =
      caches
      .appendingPathComponent("dev.topher.app", isDirectory: true)
      .appendingPathComponent(ChromeBridgeConstants.runtimeDirectoryName, isDirectory: true)
    return Self(
      directoryURL: directory,
      socketURL: directory.appendingPathComponent(ChromeBridgeConstants.socketFileName),
      sessionTokenURL: directory.appendingPathComponent(
        ChromeBridgeConstants.sessionTokenFileName
      )
    )
  }
}

private struct ChromeBridgeHello: Codable {
  let version: Int
  let type: String
  let sessionToken: String
  let extensionOrigin: String
}

struct ChromeNativeHostManifest: Codable, Equatable {
  let name: String
  let description: String?
  let path: String
  let type: String
  let allowedOrigins: [String]

  enum CodingKeys: String, CodingKey {
    case name
    case description
    case path
    case type
    case allowedOrigins = "allowed_origins"
  }
}

struct ChromeNativeHostRegistrationValidator: Sendable {
  let manifestURL: URL
  let expectedHelperURL: URL

  static func live(fileManager: FileManager = .default, bundle: Bundle = .main) -> Self {
    let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    )[0]
    let manifestURL =
      applicationSupport
      .appendingPathComponent("Google/Chrome/NativeMessagingHosts", isDirectory: true)
      .appendingPathComponent("\(ChromeBridgeConstants.nativeHostName).json")
    let helperURL =
      bundle.bundleURL
      .appendingPathComponent("Contents/Helpers", isDirectory: true)
      .appendingPathComponent(ChromeBridgeConstants.helperExecutableName)
    return Self(manifestURL: manifestURL, expectedHelperURL: helperURL)
  }

  func validates(extensionOrigin: String) -> Bool {
    guard
      Self.isExactExtensionOrigin(extensionOrigin),
      let manifestData = try? Data(contentsOf: manifestURL),
      manifestData.count <= 8_192,
      let manifest = try? JSONDecoder().decode(ChromeNativeHostManifest.self, from: manifestData),
      manifest.name == ChromeBridgeConstants.nativeHostName,
      manifest.type == "stdio",
      manifest.allowedOrigins == [extensionOrigin],
      manifest.path.hasPrefix("/"),
      URL(fileURLWithPath: manifest.path).standardizedFileURL
        == expectedHelperURL.standardizedFileURL,
      Self.isSecureRegularFile(
        manifestURL,
        mustBeExecutable: false,
        requiresCurrentUserOwnership: true
      ),
      Self.isSecureRegularFile(
        expectedHelperURL,
        mustBeExecutable: true,
        requiresCurrentUserOwnership: false
      )
    else { return false }
    return true
  }

  static func isExactExtensionOrigin(_ value: String) -> Bool {
    guard
      value.hasPrefix("chrome-extension://"),
      value.hasSuffix("/"),
      value.count == "chrome-extension://".count + 32 + 1
    else { return false }
    let identifierStart = value.index(value.startIndex, offsetBy: "chrome-extension://".count)
    let identifierEnd = value.index(identifierStart, offsetBy: 32)
    return value[identifierStart..<identifierEnd].allSatisfy { ("a"..."p").contains($0) }
  }

  static func isSecureRegularFile(
    _ url: URL,
    mustBeExecutable: Bool,
    requiresCurrentUserOwnership: Bool
  ) -> Bool {
    var information = stat()
    guard lstat(url.path, &information) == 0 else { return false }
    guard (information.st_mode & S_IFMT) == S_IFREG else { return false }
    if requiresCurrentUserOwnership, information.st_uid != geteuid() { return false }
    guard (information.st_mode & (S_IWGRP | S_IWOTH)) == 0 else { return false }
    if mustBeExecutable, access(url.path, X_OK) != 0 { return false }
    return true
  }
}

private enum ChromeSocketRelayError: Error {
  case invalidRuntimeDirectory
  case invalidSocketPath
  case socketFailure
}

/// Owns the local, same-user Unix socket. The socket carries only framed JSON
/// between Topher and the native host; it never mirrors tab state.
final class ChromeSocketRelay: @unchecked Sendable {
  private let paths: ChromeBridgeRuntimePaths
  private let registration: ChromeNativeHostRegistrationValidator
  private let sessionToken: String
  private let listenerFD: Int32
  private let stateLock = NSLock()
  private let queue = DispatchQueue(label: "dev.topher.chrome-bridge.socket")
  private var connectionFD: Int32 = -1
  private var stopped = false
  private let onMessage: @Sendable (Data) -> Void
  private let onConnect: @Sendable () -> Void
  private let onDisconnect: @Sendable () -> Void

  init(
    paths: ChromeBridgeRuntimePaths,
    registration: ChromeNativeHostRegistrationValidator,
    onMessage: @escaping @Sendable (Data) -> Void,
    onConnect: @escaping @Sendable () -> Void,
    onDisconnect: @escaping @Sendable () -> Void
  ) throws {
    self.paths = paths
    self.registration = registration
    self.onMessage = onMessage
    self.onConnect = onConnect
    self.onDisconnect = onDisconnect
    sessionToken = UUID().uuidString.lowercased()

    try Self.prepareRuntime(paths: paths, sessionToken: sessionToken)
    listenerFD = try Self.makeListener(socketPath: paths.socketURL.path)
    queue.async { [weak self] in
      self?.run()
    }
  }

  deinit {
    stop()
  }

  func send(_ data: Data) -> Bool {
    guard data.count <= ChromeBridgeConstants.maximumMessageByteCount else { return false }
    return stateLock.withLock {
      guard !stopped, connectionFD >= 0 else { return false }
      return Self.writeFrame(data, to: connectionFD)
    }
  }

  func stop() {
    stateLock.withLock {
      guard !stopped else { return }
      stopped = true
      if connectionFD >= 0 {
        Darwin.shutdown(connectionFD, SHUT_RDWR)
        Darwin.close(connectionFD)
        connectionFD = -1
      }
      Darwin.shutdown(listenerFD, SHUT_RDWR)
      Darwin.close(listenerFD)
    }
  }

  private func run() {
    while true {
      if stateLock.withLock({ stopped }) { return }
      let candidateFD = Darwin.accept(listenerFD, nil, nil)
      if candidateFD < 0 {
        if errno == EINTR { continue }
        if stateLock.withLock({ stopped }) { return }
        continue
      }

      guard
        Self.configureConnectedSocket(candidateFD),
        validatePeer(candidateFD),
        validateHello(candidateFD),
        Self.clearReceiveTimeout(candidateFD)
      else {
        Darwin.close(candidateFD)
        continue
      }

      stateLock.withLock {
        if connectionFD >= 0 {
          Darwin.shutdown(connectionFD, SHUT_RDWR)
          Darwin.close(connectionFD)
        }
        connectionFD = candidateFD
      }
      onConnect()

      while let data = Self.readFrame(
        from: candidateFD,
        maximumByteCount: ChromeBridgeConstants.maximumMessageByteCount
      ) {
        onMessage(data)
      }

      let disconnected = stateLock.withLock { () -> Bool in
        guard connectionFD == candidateFD else { return false }
        Darwin.close(connectionFD)
        connectionFD = -1
        return true
      }
      if disconnected { onDisconnect() }
    }
  }

  private func validatePeer(_ fileDescriptor: Int32) -> Bool {
    var effectiveUserID: uid_t = 0
    var effectiveGroupID: gid_t = 0
    guard getpeereid(fileDescriptor, &effectiveUserID, &effectiveGroupID) == 0 else {
      return false
    }
    return effectiveUserID == geteuid()
  }

  private func validateHello(_ fileDescriptor: Int32) -> Bool {
    guard
      let data = Self.readFrame(from: fileDescriptor, maximumByteCount: 4_096),
      let hello = try? JSONDecoder().decode(ChromeBridgeHello.self, from: data),
      hello.version == ChromeBridgeRequest.protocolVersion,
      hello.type == "bridgeHello",
      hello.sessionToken == sessionToken,
      registration.validates(extensionOrigin: hello.extensionOrigin)
    else { return false }
    return true
  }

  private static func prepareRuntime(
    paths: ChromeBridgeRuntimePaths,
    sessionToken: String,
    fileManager: FileManager = .default
  ) throws {
    try fileManager.createDirectory(
      at: paths.directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )

    var directoryInformation = stat()
    guard
      lstat(paths.directoryURL.path, &directoryInformation) == 0,
      (directoryInformation.st_mode & S_IFMT) == S_IFDIR,
      directoryInformation.st_uid == geteuid(),
      chmod(paths.directoryURL.path, 0o700) == 0
    else { throw ChromeSocketRelayError.invalidRuntimeDirectory }

    var socketInformation = stat()
    if lstat(paths.socketURL.path, &socketInformation) == 0 {
      guard
        (socketInformation.st_mode & S_IFMT) == S_IFSOCK,
        socketInformation.st_uid == geteuid()
      else { throw ChromeSocketRelayError.invalidRuntimeDirectory }
      try fileManager.removeItem(at: paths.socketURL)
    } else if errno != ENOENT {
      throw ChromeSocketRelayError.invalidRuntimeDirectory
    }

    try Data(sessionToken.utf8).write(to: paths.sessionTokenURL, options: .atomic)
    guard chmod(paths.sessionTokenURL.path, 0o600) == 0 else {
      throw ChromeSocketRelayError.invalidRuntimeDirectory
    }
    var tokenInformation = stat()
    guard
      lstat(paths.sessionTokenURL.path, &tokenInformation) == 0,
      (tokenInformation.st_mode & S_IFMT) == S_IFREG,
      tokenInformation.st_uid == geteuid(),
      (tokenInformation.st_mode & (S_IRWXG | S_IRWXO)) == 0,
      tokenInformation.st_size > 0,
      tokenInformation.st_size <= 128
    else { throw ChromeSocketRelayError.invalidRuntimeDirectory }
  }

  private static func makeListener(socketPath: String) throws -> Int32 {
    let pathBytes = Array(socketPath.utf8CString)
    guard pathBytes.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
      throw ChromeSocketRelayError.invalidSocketPath
    }

    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw ChromeSocketRelayError.socketFailure }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
      destination.copyBytes(from: pathBytes.map { UInt8(bitPattern: $0) })
    }
    let length = socklen_t(
      MemoryLayout.size(ofValue: address.sun_len)
        + MemoryLayout.size(ofValue: address.sun_family)
        + pathBytes.count
    )
    address.sun_len = UInt8(length)

    let bindResult = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, length)
      }
    }
    guard bindResult == 0, listen(descriptor, 1) == 0, chmod(socketPath, 0o600) == 0 else {
      Darwin.close(descriptor)
      throw ChromeSocketRelayError.socketFailure
    }
    return descriptor
  }

  private static func configureConnectedSocket(_ fileDescriptor: Int32) -> Bool {
    var enabled: Int32 = 1
    let noSignalConfigured =
      withUnsafePointer(to: &enabled) { pointer in
        setsockopt(
          fileDescriptor,
          SOL_SOCKET,
          SO_NOSIGPIPE,
          pointer,
          socklen_t(MemoryLayout<Int32>.size)
        )
      } == 0
    var sendTimeout = timeval(tv_sec: 1, tv_usec: 0)
    let sendTimeoutConfigured =
      withUnsafePointer(to: &sendTimeout) { pointer in
        setsockopt(
          fileDescriptor,
          SOL_SOCKET,
          SO_SNDTIMEO,
          pointer,
          socklen_t(MemoryLayout<timeval>.size)
        )
      } == 0
    var receiveTimeout = timeval(tv_sec: 2, tv_usec: 0)
    let receiveTimeoutConfigured =
      withUnsafePointer(to: &receiveTimeout) { pointer in
        setsockopt(
          fileDescriptor,
          SOL_SOCKET,
          SO_RCVTIMEO,
          pointer,
          socklen_t(MemoryLayout<timeval>.size)
        )
      } == 0
    return noSignalConfigured && sendTimeoutConfigured && receiveTimeoutConfigured
  }

  private static func clearReceiveTimeout(_ fileDescriptor: Int32) -> Bool {
    var timeout = timeval(tv_sec: 0, tv_usec: 0)
    return withUnsafePointer(to: &timeout) { pointer in
      setsockopt(
        fileDescriptor,
        SOL_SOCKET,
        SO_RCVTIMEO,
        pointer,
        socklen_t(MemoryLayout<timeval>.size)
      )
    } == 0
  }

  private static func readFrame(from fileDescriptor: Int32, maximumByteCount: Int) -> Data? {
    guard let lengthData = readExact(4, from: fileDescriptor) else { return nil }
    let length = lengthData.withUnsafeBytes { bytes in
      UInt32(littleEndian: bytes.loadUnaligned(as: UInt32.self))
    }
    guard length > 0, length <= maximumByteCount else { return nil }
    return readExact(Int(length), from: fileDescriptor)
  }

  private static func readExact(_ byteCount: Int, from fileDescriptor: Int32) -> Data? {
    var data = Data(count: byteCount)
    var offset = 0
    let succeeded = data.withUnsafeMutableBytes { bytes -> Bool in
      guard let baseAddress = bytes.baseAddress else { return false }
      while offset < byteCount {
        let count = Darwin.read(
          fileDescriptor, baseAddress.advanced(by: offset), byteCount - offset)
        if count > 0 {
          offset += count
        } else if count < 0, errno == EINTR {
          continue
        } else {
          return false
        }
      }
      return true
    }
    return succeeded ? data : nil
  }

  private static func writeFrame(_ data: Data, to fileDescriptor: Int32) -> Bool {
    var length = UInt32(data.count).littleEndian
    let prefix = withUnsafeBytes(of: &length) { Data($0) }
    return writeExact(prefix, to: fileDescriptor) && writeExact(data, to: fileDescriptor)
  }

  private static func writeExact(_ data: Data, to fileDescriptor: Int32) -> Bool {
    var offset = 0
    return data.withUnsafeBytes { bytes -> Bool in
      guard let baseAddress = bytes.baseAddress else { return false }
      while offset < data.count {
        let count = Darwin.write(
          fileDescriptor,
          baseAddress.advanced(by: offset),
          data.count - offset
        )
        if count > 0 {
          offset += count
        } else if count < 0, errno == EINTR {
          continue
        } else {
          return false
        }
      }
      return true
    }
  }
}

func chromeBridgeDisconnectError(
  operation: ChromeBridgeOperation,
  wasSent: Bool
) -> ChromeContextError {
  if operation == .activateTab, wasSent {
    return .activationOutcomeUnknown
  }
  if operation == .openYouTubeVideo, wasSent {
    return .navigationOutcomeUnknown
  }
  return .bridgeUnavailable
}

private actor ChromeNativeMessagingBroker {
  private static let logger = Logger(
    subsystem: "dev.topher.app",
    category: "chrome-context"
  )
  private struct PendingResponse {
    let data: Data
    let operation: ChromeBridgeOperation
    let continuation: CheckedContinuation<ChromeBridgeResponse, any Error>
    var wasSent: Bool
  }

  private var pendingResponses: [UUID: PendingResponse] = [:]
  private var relay: ChromeSocketRelay?
  private var didAttemptSetup = false

  static func liveExchange() -> ChromeBridgeExchange {
    let broker = ChromeNativeMessagingBroker()
    return ChromeBridgeExchange(
      send: { request in try await broker.exchange(request) }
    )
  }

  private init() {}

  private func startIfNeeded() {
    guard !didAttemptSetup else { return }
    didAttemptSetup = true
    do {
      relay = try ChromeSocketRelay(
        paths: .live(),
        registration: .live(),
        onMessage: { [weak self] data in
          Task { await self?.receive(data) }
        },
        onConnect: { [weak self] in
          Task { await self?.connected() }
        },
        onDisconnect: { [weak self] in
          Task { await self?.disconnected() }
        }
      )
    } catch {
      Self.logger.error("Chrome bridge socket setup failed")
      relay = nil
    }
  }

  private func exchange(_ request: ChromeBridgeRequest) async throws -> ChromeBridgeResponse {
    startIfNeeded()
    guard let relay else { throw ChromeContextError.bridgeUnavailable }
    let data = try JSONEncoder().encode(request)
    guard data.count <= ChromeBridgeConstants.maximumMessageByteCount else {
      throw ChromeContextError.malformedResponse
    }

    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        guard pendingResponses[request.requestID] == nil else {
          continuation.resume(throwing: ChromeContextError.busy)
          return
        }
        pendingResponses[request.requestID] = PendingResponse(
          data: data,
          operation: request.operation,
          continuation: continuation,
          wasSent: false
        )
        if relay.send(data) {
          pendingResponses[request.requestID]?.wasSent = true
        }
      }
    } onCancel: {
      Task { await self.cancel(requestID: request.requestID) }
    }
  }

  private func receive(_ data: Data) {
    guard
      data.count <= ChromeBridgeConstants.maximumMessageByteCount,
      let response = try? JSONDecoder().decode(ChromeBridgeResponse.self, from: data)
    else {
      Self.logger.error("Chrome bridge rejected malformed response metadata")
      return
    }
    guard let pending = pendingResponses.removeValue(forKey: response.requestID) else {
      Self.logger.notice("Chrome bridge ignored unmatched or duplicate response metadata")
      return
    }
    pending.continuation.resume(returning: response)
  }

  private func connected() {
    guard let relay else { return }
    for (requestID, pending) in pendingResponses where !pending.wasSent {
      if relay.send(pending.data) {
        pendingResponses[requestID]?.wasSent = true
      }
    }
  }

  private func disconnected() {
    let pending = pendingResponses.values
    pendingResponses.removeAll()
    for response in pending {
      response.continuation.resume(
        throwing: chromeBridgeDisconnectError(
          operation: response.operation,
          wasSent: response.wasSent
        )
      )
    }
    Self.logger.notice("Chrome native messaging bridge disconnected")
  }

  private func cancel(requestID: UUID) {
    if let pending = pendingResponses.removeValue(forKey: requestID) {
      pending.continuation.resume(throwing: CancellationError())
    }
    guard
      let relay,
      let data = try? JSONEncoder().encode(
        ChromeBridgeRequest.cancel(requestID: requestID)
      ),
      data.count <= ChromeBridgeConstants.maximumMessageByteCount
    else { return }
    _ = relay.send(data)
  }
}

extension ChromeContextCapabilities {
  static func live() -> Self {
    Self(
      client: ChromeBridgeClient(
        exchange: ChromeNativeMessagingBroker.liveExchange()
      )
    )
  }
}
