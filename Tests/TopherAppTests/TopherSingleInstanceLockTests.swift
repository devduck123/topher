import Foundation
import XCTest

@testable import TopherApp

@MainActor
final class TopherSingleInstanceLockTests: XCTestCase {
  func testOnlyOneLockOwnsTheRuntimeDirectoryAtATime() throws {
    let directoryURL = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    let primary = TopherSingleInstanceLock(directoryURL: directoryURL)
    let duplicate = TopherSingleInstanceLock(directoryURL: directoryURL)

    XCTAssertEqual(primary.state, .primary)
    XCTAssertEqual(duplicate.state, .secondary)
  }

  func testLockCanBeReacquiredAfterThePrimaryReleasesIt() throws {
    let directoryURL = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }

    var primary: TopherSingleInstanceLock? = TopherSingleInstanceLock(
      directoryURL: directoryURL
    )
    XCTAssertEqual(primary?.state, .primary)
    primary = nil

    XCTAssertEqual(
      TopherSingleInstanceLock(directoryURL: directoryURL).state,
      .primary
    )
  }

  func testRejectsASymlinkedRuntimeDirectory() throws {
    let parentURL = temporaryDirectory()
    let targetURL = parentURL.appendingPathComponent("target", isDirectory: true)
    let linkedURL = parentURL.appendingPathComponent("linked", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: parentURL) }

    try FileManager.default.createDirectory(
      at: targetURL,
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: targetURL)

    XCTAssertEqual(
      TopherSingleInstanceLock(directoryURL: linkedURL).state,
      .unavailable
    )
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("topher-instance-lock-tests", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
  }
}
