import Darwin
import Foundation

/// Owns the per-user process lifetime for global shortcut registration.
///
/// LaunchServices normally reuses one application process, but callers can
/// force duplicates with `open -n` or by invoking the executable directly.
/// A nonblocking BSD lock keeps that launch detail from becoming duplicate
/// command authority.
@MainActor
final class TopherSingleInstanceLock {
  enum State: Equatable {
    case primary
    case secondary
    case unavailable
  }

  let state: State

  var isPrimary: Bool { state == .primary }

  private var descriptor: Int32 = -1

  convenience init() {
    let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    self.init(
      directoryURL:
        cachesURL
        .appendingPathComponent("dev.topher.app", isDirectory: true)
        .appendingPathComponent("Runtime", isDirectory: true)
    )
  }

  init(directoryURL: URL) {
    let fileManager = FileManager.default
    let directoryPath = directoryURL.standardizedFileURL.path

    do {
      try fileManager.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      state = .unavailable
      return
    }

    var directoryInfo = stat()
    guard
      lstat(directoryPath, &directoryInfo) == 0,
      (directoryInfo.st_mode & S_IFMT) == S_IFDIR,
      directoryInfo.st_uid == geteuid()
    else {
      state = .unavailable
      return
    }
    guard chmod(directoryPath, S_IRWXU) == 0 else {
      state = .unavailable
      return
    }

    let lockPath = directoryURL.appendingPathComponent("topher.lock").path
    let openedDescriptor = Darwin.open(
      lockPath,
      O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
      S_IRUSR | S_IWUSR
    )
    guard openedDescriptor >= 0 else {
      state = .unavailable
      return
    }

    var lockInfo = stat()
    guard
      fstat(openedDescriptor, &lockInfo) == 0,
      (lockInfo.st_mode & S_IFMT) == S_IFREG,
      lockInfo.st_uid == geteuid()
    else {
      Darwin.close(openedDescriptor)
      state = .unavailable
      return
    }
    guard fchmod(openedDescriptor, S_IRUSR | S_IWUSR) == 0 else {
      Darwin.close(openedDescriptor)
      state = .unavailable
      return
    }

    if flock(openedDescriptor, LOCK_EX | LOCK_NB) == 0 {
      descriptor = openedDescriptor
      state = .primary
    } else {
      Darwin.close(openedDescriptor)
      state = errno == EWOULDBLOCK ? .secondary : .unavailable
    }
  }

  deinit {
    guard descriptor >= 0 else { return }
    _ = flock(descriptor, LOCK_UN)
    Darwin.close(descriptor)
  }
}
