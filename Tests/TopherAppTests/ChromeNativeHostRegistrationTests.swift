import Darwin
import Foundation
import TopherCore
import XCTest

@testable import TopherApp

final class ChromeNativeHostRegistrationTests: XCTestCase {
  private let origin = "chrome-extension://abcdefghijklmnopabcdefghijklmnop/"

  func testRequiresExactOriginAndAbsoluteCheckedBundledHelperPath() throws {
    try withRegistration { validator, manifestURL, helperURL in
      XCTAssertTrue(validator.validates(extensionOrigin: origin))
      XCTAssertFalse(
        validator.validates(
          extensionOrigin: "chrome-extension://abcdefghijklmnopabcdefghijklmnpo/"
        )
      )

      try writeManifest(
        at: manifestURL,
        helperPath: helperURL.path,
        allowedOrigins: [origin, "chrome-extension://pppppppppppppppppppppppppppppppp/"]
      )
      XCTAssertFalse(validator.validates(extensionOrigin: origin))

      try writeManifest(
        at: manifestURL,
        helperPath: "/tmp/different/TopherChromeBridgeHost",
        allowedOrigins: [origin]
      )
      XCTAssertFalse(validator.validates(extensionOrigin: origin))
    }
  }

  func testControllerInstallsAndRepairsThePackagedExtensionRegistration() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let manifestURL = root.appendingPathComponent(
      "NativeMessagingHosts/dev.topher.chrome_bridge.json"
    )
    let helperURL = root.appendingPathComponent(
      "Topher.app/Contents/Helpers/TopherChromeBridgeHost"
    )
    try FileManager.default.createDirectory(
      at: helperURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    XCTAssertTrue(FileManager.default.createFile(atPath: helperURL.path, contents: Data()))
    XCTAssertEqual(chmod(helperURL.path, 0o755), 0)
    defer { try? FileManager.default.removeItem(at: root) }

    let controller = ChromeNativeHostRegistrationController(
      manifestURL: manifestURL,
      expectedHelperURL: helperURL,
      fileManager: .default
    )
    XCTAssertEqual(controller.readiness(), .needsRegistration)

    try controller.installOrRepair()
    XCTAssertEqual(controller.readiness(), .ready)
    let installed = try JSONDecoder().decode(
      ChromeNativeHostManifest.self,
      from: Data(contentsOf: manifestURL)
    )
    XCTAssertEqual(installed.allowedOrigins, [ChromeBridgeConstants.extensionOrigin])
    XCTAssertEqual(installed.path, helperURL.standardizedFileURL.path)
    XCTAssertEqual(
      try FileManager.default.attributesOfItem(atPath: manifestURL.path)[.posixPermissions]
        as? NSNumber,
      NSNumber(value: 0o600)
    )

    try writeManifest(
      at: manifestURL,
      helperPath: "/Applications/Previous/Topher.app/Contents/Helpers/TopherChromeBridgeHost",
      allowedOrigins: [ChromeBridgeConstants.extensionOrigin]
    )
    XCTAssertEqual(controller.readiness(), .needsRepair)
    try controller.installOrRepair()
    XCTAssertEqual(controller.readiness(), .ready)
  }

  func testControllerMigratesALegacyTopherExtensionOrigin() throws {
    try withRegistration { _, manifestURL, helperURL in
      let controller = ChromeNativeHostRegistrationController(
        manifestURL: manifestURL,
        expectedHelperURL: helperURL,
        fileManager: .default
      )
      XCTAssertEqual(controller.readiness(), .needsRepair)
      try controller.installOrRepair()
      XCTAssertEqual(controller.readiness(), .ready)
      let migrated = try JSONDecoder().decode(
        ChromeNativeHostManifest.self,
        from: Data(contentsOf: manifestURL)
      )
      XCTAssertEqual(migrated.allowedOrigins, [ChromeBridgeConstants.extensionOrigin])
    }
  }

  func testControllerRefusesAConflictingHelperRegistration() throws {
    try withRegistration { _, manifestURL, helperURL in
      try writeManifest(
        at: manifestURL,
        helperPath: "/Applications/Other.app/Contents/Helpers/OtherHost",
        allowedOrigins: [origin]
      )
      let controller = ChromeNativeHostRegistrationController(
        manifestURL: manifestURL,
        expectedHelperURL: helperURL,
        fileManager: .default
      )
      XCTAssertEqual(controller.readiness(), .blocked)
      XCTAssertThrowsError(try controller.installOrRepair())
      let original =
        try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
        as? [String: Any]
      XCTAssertEqual(
        original?["path"] as? String,
        "/Applications/Other.app/Contents/Helpers/OtherHost"
      )
    }
  }

  func testRejectsSymlinkedManifestAndHelper() throws {
    try withRegistration { validator, manifestURL, helperURL in
      let realManifest = manifestURL.deletingLastPathComponent().appendingPathComponent("real.json")
      try FileManager.default.moveItem(at: manifestURL, to: realManifest)
      try FileManager.default.createSymbolicLink(at: manifestURL, withDestinationURL: realManifest)
      XCTAssertFalse(validator.validates(extensionOrigin: origin))

      try FileManager.default.removeItem(at: manifestURL)
      try FileManager.default.moveItem(at: realManifest, to: manifestURL)
      let realHelper = helperURL.deletingLastPathComponent().appendingPathComponent("real-host")
      try FileManager.default.moveItem(at: helperURL, to: realHelper)
      try FileManager.default.createSymbolicLink(at: helperURL, withDestinationURL: realHelper)
      XCTAssertFalse(validator.validates(extensionOrigin: origin))
    }
  }

  func testRejectsGroupWritableManifestAndHelper() throws {
    try withRegistration { validator, manifestURL, helperURL in
      XCTAssertEqual(chmod(manifestURL.path, 0o620), 0)
      XCTAssertFalse(validator.validates(extensionOrigin: origin))
      XCTAssertEqual(chmod(manifestURL.path, 0o600), 0)
      XCTAssertEqual(chmod(helperURL.path, 0o775), 0)
      XCTAssertFalse(validator.validates(extensionOrigin: origin))
    }
  }

  func testSocketRelayRejectsWrongOriginThenExchangesBoundedFrames() async throws {
    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
      .appendingPathComponent("topher-\(UUID().uuidString.prefix(8))")
    let manifestURL = root.appendingPathComponent("dev.topher.chrome_bridge.json")
    let helperURL = root.appendingPathComponent("TopherChromeBridgeHost")
    let runtimeDirectory = root.appendingPathComponent("runtime", isDirectory: true)
    let paths = ChromeBridgeRuntimePaths(
      directoryURL: runtimeDirectory,
      socketURL: runtimeDirectory.appendingPathComponent("bridge.sock"),
      sessionTokenURL: runtimeDirectory.appendingPathComponent("token")
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    XCTAssertTrue(FileManager.default.createFile(atPath: helperURL.path, contents: Data()))
    XCTAssertEqual(chmod(helperURL.path, 0o755), 0)
    try writeManifest(at: manifestURL, helperPath: helperURL.path, allowedOrigins: [origin])
    defer { try? FileManager.default.removeItem(at: root) }

    let connected = expectation(description: "Authenticated native host connected")
    let received = expectation(description: "Native host frame received")
    let receivedData = LockedDataBox()
    let relay = try ChromeSocketRelay(
      paths: paths,
      registration: ChromeNativeHostRegistrationValidator(
        manifestURL: manifestURL,
        expectedHelperURL: helperURL
      ),
      onMessage: { data in
        receivedData.set(data)
        received.fulfill()
      },
      onConnect: { connected.fulfill() },
      onDisconnect: {}
    )
    defer { relay.stop() }

    let runtimeAttributes = try FileManager.default.attributesOfItem(
      atPath: runtimeDirectory.path
    )
    let tokenAttributes = try FileManager.default.attributesOfItem(
      atPath: paths.sessionTokenURL.path
    )
    XCTAssertEqual(runtimeAttributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o700))
    XCTAssertEqual(tokenAttributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))

    let wrongOriginDescriptor = try connectUnixSocket(path: paths.socketURL.path)
    XCTAssertTrue(
      writeFrame(
        jsonData([
          "version": ChromeBridgeRequest.protocolVersion,
          "type": "bridgeHello",
          "sessionToken": try String(contentsOf: paths.sessionTokenURL, encoding: .utf8),
          "extensionOrigin": "chrome-extension://pppppppppppppppppppppppppppppppp/",
        ]),
        to: wrongOriginDescriptor
      )
    )
    XCTAssertEqual(Darwin.shutdown(wrongOriginDescriptor, SHUT_WR), 0)
    // Wait until the relay has consumed and rejected this connection before
    // filling the one-entry listener backlog with the authenticated client.
    XCTAssertNil(readFrame(from: wrongOriginDescriptor))
    Darwin.close(wrongOriginDescriptor)

    let descriptor = try connectUnixSocket(path: paths.socketURL.path)
    defer { Darwin.close(descriptor) }
    XCTAssertTrue(
      writeFrame(
        jsonData([
          "version": ChromeBridgeRequest.protocolVersion,
          "type": "bridgeHello",
          "sessionToken": try String(contentsOf: paths.sessionTokenURL, encoding: .utf8),
          "extensionOrigin": origin,
        ]),
        to: descriptor
      )
    )
    await fulfillment(of: [connected], timeout: 1)

    let request = jsonData([
      "version": ChromeBridgeRequest.protocolVersion,
      "requestID": UUID().uuidString,
    ])
    XCTAssertTrue(writeFrame(request, to: descriptor))
    await fulfillment(of: [received], timeout: 1)
    XCTAssertEqual(receivedData.value, request)

    let response = jsonData([
      "version": ChromeBridgeRequest.protocolVersion,
      "status": "success",
    ])
    XCTAssertTrue(relay.send(response))
    XCTAssertEqual(readFrame(from: descriptor), response)
  }

  private func withRegistration(
    _ body: (
      ChromeNativeHostRegistrationValidator,
      URL,
      URL
    ) throws -> Void
  ) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let manifestURL = root.appendingPathComponent("dev.topher.chrome_bridge.json")
    let helperURL = root.appendingPathComponent(
      "Topher.app/Contents/Helpers/TopherChromeBridgeHost")
    try FileManager.default.createDirectory(
      at: helperURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    XCTAssertTrue(FileManager.default.createFile(atPath: helperURL.path, contents: Data()))
    XCTAssertEqual(chmod(helperURL.path, 0o755), 0)
    try writeManifest(at: manifestURL, helperPath: helperURL.path, allowedOrigins: [origin])
    defer { try? FileManager.default.removeItem(at: root) }

    try body(
      ChromeNativeHostRegistrationValidator(
        manifestURL: manifestURL,
        expectedHelperURL: helperURL
      ),
      manifestURL,
      helperURL
    )
  }

  private func writeManifest(
    at url: URL,
    helperPath: String,
    allowedOrigins: [String]
  ) throws {
    let document: [String: Any] = [
      "name": "dev.topher.chrome_bridge",
      "description": "test",
      "path": helperPath,
      "type": "stdio",
      "allowed_origins": allowedOrigins,
    ]
    try JSONSerialization.data(withJSONObject: document).write(to: url, options: .atomic)
    XCTAssertEqual(chmod(url.path, 0o600), 0)
  }
}

private final class LockedDataBox: @unchecked Sendable {
  private let lock = NSLock()
  private var data: Data?

  var value: Data? {
    lock.withLock { data }
  }

  func set(_ value: Data) {
    lock.withLock { data = value }
  }
}

private enum SocketTestError: Error {
  case connectionFailed
}

private func connectUnixSocket(path: String) throws -> Int32 {
  let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
  guard descriptor >= 0 else { throw SocketTestError.connectionFailed }

  let pathBytes = Array(path.utf8CString)
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
  let result = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(descriptor, $0, length)
    }
  }
  guard result == 0 else {
    Darwin.close(descriptor)
    throw SocketTestError.connectionFailed
  }
  return descriptor
}

private func jsonData(_ object: [String: Any]) -> Data {
  try! JSONSerialization.data(withJSONObject: object)
}

private func writeFrame(_ data: Data, to descriptor: Int32) -> Bool {
  var length = UInt32(data.count).littleEndian
  let prefix = withUnsafeBytes(of: &length) { Data($0) }
  return writeExact(prefix, to: descriptor) && writeExact(data, to: descriptor)
}

private func writeExact(_ data: Data, to descriptor: Int32) -> Bool {
  var offset = 0
  return data.withUnsafeBytes { bytes -> Bool in
    guard let baseAddress = bytes.baseAddress else { return false }
    while offset < data.count {
      let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
      guard count > 0 else { return false }
      offset += count
    }
    return true
  }
}

private func readFrame(from descriptor: Int32) -> Data? {
  guard let prefix = readExact(4, from: descriptor) else { return nil }
  let length = prefix.withUnsafeBytes {
    UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
  }
  return readExact(Int(length), from: descriptor)
}

private func readExact(_ byteCount: Int, from descriptor: Int32) -> Data? {
  var data = Data(count: byteCount)
  var offset = 0
  let succeeded = data.withUnsafeMutableBytes { bytes -> Bool in
    guard let baseAddress = bytes.baseAddress else { return false }
    while offset < byteCount {
      let count = Darwin.read(descriptor, baseAddress.advanced(by: offset), byteCount - offset)
      guard count > 0 else { return false }
      offset += count
    }
    return true
  }
  return succeeded ? data : nil
}
