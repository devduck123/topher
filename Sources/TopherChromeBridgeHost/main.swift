import Darwin
import Foundation
import TopherCore

private struct RuntimePaths {
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

private struct BridgeHello: Encodable {
  let version = ChromeBridgeRequest.protocolVersion
  let type = "bridgeHello"
  let sessionToken: String
  let extensionOrigin: String
}

private enum HostFailure: String, Error {
  case invalidCallerOrigin
  case invalidRuntimeState
  case nativeStreamEnded
  case relayFailed
}

private let maximumMessageByteCount = ChromeBridgeConstants.maximumMessageByteCount
private let extensionOriginPattern = try! NSRegularExpression(
  pattern: #"\Achrome-extension://[a-p]{32}/\z"#
)

private func fail(_ failure: HostFailure) -> Never {
  FileHandle.standardError.write(Data("Topher Chrome bridge: \(failure.rawValue)\n".utf8))
  exit(EXIT_FAILURE)
}

private func validatedOrigin(arguments: [String]) -> String? {
  guard arguments.count >= 2 else { return nil }
  let value = arguments[1]
  let range = NSRange(value.startIndex..<value.endIndex, in: value)
  guard extensionOriginPattern.firstMatch(in: value, range: range)?.range == range else {
    return nil
  }
  return value
}

private func readSessionToken(paths: RuntimePaths) -> String? {
  var directoryInformation = stat()
  var tokenInformation = stat()
  guard
    lstat(paths.directoryURL.path, &directoryInformation) == 0,
    (directoryInformation.st_mode & S_IFMT) == S_IFDIR,
    directoryInformation.st_uid == geteuid(),
    (directoryInformation.st_mode & (S_IRWXG | S_IRWXO)) == 0,
    lstat(paths.sessionTokenURL.path, &tokenInformation) == 0,
    (tokenInformation.st_mode & S_IFMT) == S_IFREG,
    tokenInformation.st_uid == geteuid(),
    (tokenInformation.st_mode & (S_IRWXG | S_IRWXO)) == 0,
    tokenInformation.st_size > 0,
    tokenInformation.st_size <= 128,
    let data = try? Data(contentsOf: paths.sessionTokenURL),
    let token = String(data: data, encoding: .utf8),
    UUID(uuidString: token) != nil
  else { return nil }
  return token.lowercased()
}

private func connectSocket(path: String) -> Int32? {
  let pathBytes = Array(path.utf8CString)
  guard pathBytes.count <= MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
    return nil
  }
  let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
  guard descriptor >= 0 else { return nil }

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
    return nil
  }
  return descriptor
}

private func waitForTopher(paths: RuntimePaths) -> (Int32, String)? {
  while true {
    var standardInputPoll = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0)
    let pollResult = Darwin.poll(&standardInputPoll, 1, 1_000)
    if pollResult > 0, (standardInputPoll.revents & Int16(POLLHUP)) != 0 {
      return nil
    }
    if let token = readSessionToken(paths: paths),
      let socket = connectSocket(path: paths.socketURL.path)
    {
      return (socket, token)
    }
  }
}

private func readExact(_ byteCount: Int, from descriptor: Int32) -> Data? {
  var data = Data(count: byteCount)
  var offset = 0
  let succeeded = data.withUnsafeMutableBytes { bytes -> Bool in
    guard let baseAddress = bytes.baseAddress else { return false }
    while offset < byteCount {
      var descriptorPoll = pollfd(fd: descriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
      guard Darwin.poll(&descriptorPoll, 1, 2_000) > 0 else { return false }
      let count = Darwin.read(descriptor, baseAddress.advanced(by: offset), byteCount - offset)
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

private func readFrame(from descriptor: Int32) -> Data? {
  guard let prefix = readExact(4, from: descriptor) else { return nil }
  let length = prefix.withUnsafeBytes {
    UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
  }
  guard length > 0, length <= maximumMessageByteCount else { return nil }
  return readExact(Int(length), from: descriptor)
}

private func writeExact(_ data: Data, to descriptor: Int32) -> Bool {
  var offset = 0
  return data.withUnsafeBytes { bytes -> Bool in
    guard let baseAddress = bytes.baseAddress else { return false }
    while offset < data.count {
      let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), data.count - offset)
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

private func writeFrame(_ data: Data, to descriptor: Int32) -> Bool {
  guard data.count > 0, data.count <= maximumMessageByteCount else { return false }
  var length = UInt32(data.count).littleEndian
  let prefix = withUnsafeBytes(of: &length) { Data($0) }
  return writeExact(prefix, to: descriptor) && writeExact(data, to: descriptor)
}

private func isJSONObject(_ data: Data) -> Bool {
  guard
    data.count <= maximumMessageByteCount,
    let value = try? JSONSerialization.jsonObject(with: data),
    value is [String: Any]
  else { return false }
  return true
}

signal(SIGPIPE, SIG_IGN)
guard let extensionOrigin = validatedOrigin(arguments: CommandLine.arguments) else {
  fail(.invalidCallerOrigin)
}

private let paths = RuntimePaths.live()
guard let (socketFD, sessionToken) = waitForTopher(paths: paths) else {
  fail(.nativeStreamEnded)
}
defer { Darwin.close(socketFD) }

private let hello = BridgeHello(sessionToken: sessionToken, extensionOrigin: extensionOrigin)
guard
  let helloData = try? JSONEncoder().encode(hello),
  writeFrame(helloData, to: socketFD)
else { fail(.invalidRuntimeState) }

while true {
  var descriptors = [
    pollfd(fd: STDIN_FILENO, events: Int16(POLLIN | POLLHUP), revents: 0),
    pollfd(fd: socketFD, events: Int16(POLLIN | POLLHUP), revents: 0),
  ]
  guard Darwin.poll(&descriptors, nfds_t(descriptors.count), -1) > 0 else {
    if errno == EINTR { continue }
    fail(.relayFailed)
  }

  if (descriptors[0].revents & Int16(POLLIN)) != 0 {
    guard let message = readFrame(from: STDIN_FILENO), isJSONObject(message) else {
      fail(.nativeStreamEnded)
    }
    guard writeFrame(message, to: socketFD) else { fail(.relayFailed) }
  }
  if (descriptors[1].revents & Int16(POLLIN)) != 0 {
    guard let message = readFrame(from: socketFD), isJSONObject(message) else {
      fail(.relayFailed)
    }
    guard writeFrame(message, to: STDOUT_FILENO) else { fail(.nativeStreamEnded) }
  }
  if (descriptors[0].revents & Int16(POLLHUP | POLLERR | POLLNVAL)) != 0
    || (descriptors[1].revents & Int16(POLLHUP | POLLERR | POLLNVAL)) != 0
  {
    fail(.nativeStreamEnded)
  }
}
