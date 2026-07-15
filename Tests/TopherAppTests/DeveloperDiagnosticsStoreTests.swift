import Foundation
import XCTest

@testable import TopherApp

final class DeveloperDiagnosticsStoreTests: XCTestCase {
  private var temporaryRoot: URL!
  private var storageDirectory: URL!

  override func setUpWithError() throws {
    temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
      "TopherDeveloperDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: temporaryRoot,
      withIntermediateDirectories: false
    )
    storageDirectory =
      temporaryRoot
      .appendingPathComponent("dev.topher.app", isDirectory: true)
      .appendingPathComponent("TranscriptDiagnostics", isDirectory: true)
  }

  override func tearDownWithError() throws {
    if let temporaryRoot, FileManager.default.fileExists(atPath: temporaryRoot.path) {
      try FileManager.default.removeItem(at: temporaryRoot)
    }
    temporaryRoot = nil
    storageDirectory = nil
  }

  func testDisabledStoreDoesNotCreateStorage() async throws {
    let store = makeStore(initialEnabled: false)

    let token = await store.beginTrace()
    let snapshot = try await store.snapshot()

    XCTAssertNil(token)
    XCTAssertFalse(snapshot.isEnabled)
    XCTAssertTrue(snapshot.records.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: storageDirectory.path))
  }

  func testEnabledStorePersistsBoundedRecordWithPrivatePermissions() async throws {
    // The backup-exclusion resource value does not reliably round-trip on /tmp.
    // Exercise this storage guarantee on the same volume/domain used in production.
    let cachesRoot = try XCTUnwrap(
      FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    )
    let appDirectory = cachesRoot.appendingPathComponent(
      "TopherDeveloperDiagnosticsTests-\(UUID().uuidString)",
      isDirectory: true
    )
    let cachesStorageDirectory = appDirectory.appendingPathComponent(
      "TranscriptDiagnostics",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: appDirectory) }

    let store = DeveloperDiagnosticsStore(
      storageDirectoryURL: cachesStorageDirectory,
      initialEnabled: false,
      now: { Date(timeIntervalSince1970: 500) }
    )
    _ = try await store.setEnabled(true)
    let token = try await traceToken(for: store)

    let snapshot = try await store.record(
      draft(transcript: "Bring me to YouTube", recordedAt: Date(timeIntervalSince1970: 100)),
      using: token
    )

    let record = try XCTUnwrap(snapshot.records.first)
    XCTAssertEqual(record.transcript, "Bring me to YouTube")
    XCTAssertFalse(record.transcriptWasTruncated)
    XCTAssertEqual(record.source, .voice)
    XCTAssertEqual(record.outcome, .unsupported)
    XCTAssertEqual(record.processingDurationMilliseconds, 42)

    let directoryAttributes = try FileManager.default.attributesOfItem(
      atPath: cachesStorageDirectory.path
    )
    let fileAttributes = try FileManager.default.attributesOfItem(
      atPath: snapshot.storageFileURL.path
    )
    XCTAssertEqual(permissionBits(directoryAttributes), 0o700)
    XCTAssertEqual(permissionBits(fileAttributes), 0o600)

    let directoryValues = try cachesStorageDirectory.resourceValues(
      forKeys: [.isExcludedFromBackupKey]
    )
    let fileValues = try snapshot.storageFileURL.resourceValues(
      forKeys: [.isExcludedFromBackupKey]
    )
    XCTAssertEqual(directoryValues.isExcludedFromBackup, true)
    XCTAssertEqual(fileValues.isExcludedFromBackup, true)
  }

  func testDisableStopsStaleTraceWithoutDeletingExistingRecords() async throws {
    let preference = PreferenceBox(false)
    let store = makeStore(
      initialEnabled: false,
      persistEnabled: { preference.value = $0 }
    )
    _ = try await store.setEnabled(true)
    let firstToken = try await traceToken(for: store)
    _ = try await store.record(draft(transcript: "first"), using: firstToken)
    let staleToken = try await traceToken(for: store)

    let disabledSnapshot = try await store.setEnabled(false)
    let staleWriteSnapshot = try await store.record(
      draft(transcript: "must not persist"),
      using: staleToken
    )

    XCTAssertFalse(preference.value)
    XCTAssertFalse(disabledSnapshot.isEnabled)
    XCTAssertEqual(staleWriteSnapshot.records.map(\.transcript), ["first"])
    XCTAssertTrue(FileManager.default.fileExists(atPath: staleWriteSnapshot.storageFileURL.path))
  }

  func testClearInvalidatesQueuedWritesAndDeletesTheFile() async throws {
    let store = makeStore(initialEnabled: false)
    _ = try await store.setEnabled(true)
    let firstToken = try await traceToken(for: store)
    let firstSnapshot = try await store.record(draft(transcript: "first"), using: firstToken)
    let staleToken = try await traceToken(for: store)

    let clearedSnapshot = try await store.clear()
    let staleWriteSnapshot = try await store.record(
      draft(transcript: "must not return"),
      using: staleToken
    )

    XCTAssertTrue(clearedSnapshot.records.isEmpty)
    XCTAssertTrue(staleWriteSnapshot.records.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: firstSnapshot.storageFileURL.path))
  }

  func testAgeAndCountBoundsKeepOnlyTheNewestEligibleRecords() async throws {
    let currentDate = Date(timeIntervalSince1970: 1_000)
    let retention = DeveloperDiagnosticsRetentionPolicy(
      maximumAge: 100,
      maximumRecordCount: 2,
      maximumFileSizeBytes: 1_048_576,
      maximumTranscriptBytes: 4_096
    )
    let store = makeStore(
      initialEnabled: false,
      retention: retention,
      now: { currentDate }
    )
    _ = try await store.setEnabled(true)
    let token = try await traceToken(for: store)

    for (text, timestamp) in [
      ("expired", 899.0),
      ("eligible-oldest", 930.0),
      ("newer", 950.0),
      ("newest", 975.0),
    ] {
      _ = try await store.record(
        draft(transcript: text, recordedAt: Date(timeIntervalSince1970: timestamp)),
        using: token
      )
    }

    let snapshot = try await store.snapshot()
    XCTAssertEqual(snapshot.records.map(\.transcript), ["newer", "newest"])
  }

  func testReloadPersistsAgePruningAndDeletesExpiredFile() async throws {
    let writeDate = Date(timeIntervalSince1970: 1_000)
    let retention = DeveloperDiagnosticsRetentionPolicy(
      maximumAge: 100,
      maximumRecordCount: 200,
      maximumFileSizeBytes: 1_048_576,
      maximumTranscriptBytes: 4_096
    )
    let writingStore = makeStore(
      initialEnabled: true,
      retention: retention,
      now: { writeDate }
    )
    let token = try await traceToken(for: writingStore)
    let writtenSnapshot = try await writingStore.record(
      draft(transcript: "expires", recordedAt: writeDate),
      using: token
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: writtenSnapshot.storageFileURL.path))

    let reloadedStore = makeStore(
      initialEnabled: false,
      retention: retention,
      now: { writeDate.addingTimeInterval(101) }
    )
    let prunedSnapshot = try await reloadedStore.snapshot()

    XCTAssertTrue(prunedSnapshot.records.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: prunedSnapshot.storageFileURL.path))
  }

  func testFailedAgePruneRetriesAfterStorageRecovers() async throws {
    let clock = DateBox(Date(timeIntervalSince1970: 1_000))
    let retention = DeveloperDiagnosticsRetentionPolicy(
      maximumAge: 100,
      maximumRecordCount: 200,
      maximumFileSizeBytes: 1_048_576,
      maximumTranscriptBytes: 4_096
    )
    let store = makeStore(
      initialEnabled: false,
      retention: retention,
      now: { clock.value }
    )
    _ = try await store.setEnabled(true)
    let token = try await traceToken(for: store)
    let writtenSnapshot = try await store.record(
      draft(transcript: "expires", recordedAt: clock.value),
      using: token
    )

    let parkedDirectory =
      storageDirectory
      .deletingLastPathComponent()
      .appendingPathComponent("TranscriptDiagnostics-parked", isDirectory: true)
    try FileManager.default.moveItem(at: storageDirectory, to: parkedDirectory)
    try FileManager.default.createSymbolicLink(
      at: storageDirectory,
      withDestinationURL: parkedDirectory
    )
    clock.value = Date(timeIntervalSince1970: 1_101)

    do {
      _ = try await store.snapshot()
      XCTFail("Pruning through a symlinked storage directory must fail")
    } catch {
      // Expected: the expired record remains pending deletion in actor state.
    }
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: parkedDirectory.appendingPathComponent("transcript-diagnostics.json").path
      )
    )

    try FileManager.default.removeItem(at: storageDirectory)
    try FileManager.default.moveItem(at: parkedDirectory, to: storageDirectory)
    let recoveredSnapshot = try await store.snapshot()

    XCTAssertTrue(recoveredSnapshot.records.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: writtenSnapshot.storageFileURL.path))
  }

  func testTranscriptLimitPreservesWholeUnicodeCharacters() async throws {
    let retention = DeveloperDiagnosticsRetentionPolicy(
      maximumAge: 100,
      maximumRecordCount: 20,
      maximumFileSizeBytes: 10_000,
      maximumTranscriptBytes: 5
    )
    let store = makeStore(initialEnabled: false, retention: retention)
    _ = try await store.setEnabled(true)
    let token = try await traceToken(for: store)

    let snapshot = try await store.record(
      draft(transcript: "ééé"),
      using: token
    )

    let record = try XCTUnwrap(snapshot.records.first)
    XCTAssertEqual(record.transcript, "éé")
    XCTAssertTrue(record.transcriptWasTruncated)
    XCTAssertLessThanOrEqual(record.transcript.utf8.count, 5)
  }

  func testReloadReappliesTranscriptLimitAndPersistsBoundedRecord() async throws {
    let permissiveRetention = DeveloperDiagnosticsRetentionPolicy(
      maximumAge: 1_000,
      maximumRecordCount: 20,
      maximumFileSizeBytes: 10_000,
      maximumTranscriptBytes: 100
    )
    let writingStore = makeStore(initialEnabled: true, retention: permissiveRetention)
    let token = try await traceToken(for: writingStore)
    _ = try await writingStore.record(draft(transcript: "ééé"), using: token)

    let strictRetention = DeveloperDiagnosticsRetentionPolicy(
      maximumAge: 1_000,
      maximumRecordCount: 20,
      maximumFileSizeBytes: 10_000,
      maximumTranscriptBytes: 5
    )
    let reloadedStore = makeStore(initialEnabled: false, retention: strictRetention)
    let reloadedSnapshot = try await reloadedStore.snapshot()

    let record = try XCTUnwrap(reloadedSnapshot.records.first)
    XCTAssertEqual(record.transcript, "éé")
    XCTAssertTrue(record.transcriptWasTruncated)

    let secondReload = makeStore(initialEnabled: false, retention: strictRetention)
    let persistedSnapshot = try await secondReload.snapshot()
    XCTAssertEqual(persistedSnapshot.records, reloadedSnapshot.records)
  }

  func testFileSizeBoundEvictsOldestRecords() async throws {
    let retention = DeveloperDiagnosticsRetentionPolicy(
      maximumAge: 1_000,
      maximumRecordCount: 200,
      maximumFileSizeBytes: 2_500,
      maximumTranscriptBytes: 500
    )
    let store = makeStore(initialEnabled: false, retention: retention)
    _ = try await store.setEnabled(true)
    let token = try await traceToken(for: store)

    for index in 0..<10 {
      _ = try await store.record(
        draft(transcript: "\(index)-" + String(repeating: "x", count: 450)),
        using: token
      )
    }

    let snapshot = try await store.snapshot()
    let fileSize = try XCTUnwrap(
      FileManager.default.attributesOfItem(atPath: snapshot.storageFileURL.path)[.size]
        as? NSNumber
    )
    XCTAssertLessThan(snapshot.records.count, 10)
    XCTAssertFalse(snapshot.records.isEmpty)
    XCTAssertLessThanOrEqual(fileSize.intValue, retention.maximumFileSizeBytes)
    XCTAssertTrue(snapshot.records.last?.transcript.hasPrefix("9-") == true)
  }

  func testCorruptDocumentIsRemovedWithoutCrashing() async throws {
    let store = makeStore(initialEnabled: false)
    _ = try await store.setEnabled(true)
    let token = try await traceToken(for: store)
    let snapshot = try await store.record(draft(transcript: "synthetic"), using: token)
    try Data("not-json".utf8).write(to: snapshot.storageFileURL)

    let reloadedStore = makeStore(initialEnabled: false)
    let reloadedSnapshot = try await reloadedStore.snapshot()

    XCTAssertTrue(reloadedSnapshot.records.isEmpty)
    XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.storageFileURL.path))
  }

  func testSymlinkedStorageDirectoryIsRejectedWithoutWritingOutside() async throws {
    let appDirectory = storageDirectory.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: appDirectory,
      withIntermediateDirectories: false
    )
    let outsideDirectory = temporaryRoot.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outsideDirectory,
      withIntermediateDirectories: false
    )
    try FileManager.default.createSymbolicLink(
      at: storageDirectory,
      withDestinationURL: outsideDirectory
    )
    let preference = PreferenceBox(false)
    let store = makeStore(
      initialEnabled: false,
      persistEnabled: { preference.value = $0 }
    )

    do {
      _ = try await store.setEnabled(true)
      XCTFail("A symlinked diagnostics directory must be rejected")
    } catch {
      // Expected: the actor must not follow the link or enable recording.
    }

    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: outsideDirectory.appendingPathComponent("transcript-diagnostics.json").path
      )
    )
    let token = await store.beginTrace()
    XCTAssertNil(token)
    XCTAssertFalse(preference.value)
  }

  func testFailedRecordRetriesCleanupWithoutRetainingTranscript() async throws {
    let store = makeStore(initialEnabled: false)
    _ = try await store.setEnabled(true)
    let emptySnapshot = try await store.snapshot()
    XCTAssertTrue(emptySnapshot.records.isEmpty)

    try FileManager.default.removeItem(at: storageDirectory)
    let outsideDirectory = temporaryRoot.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outsideDirectory,
      withIntermediateDirectories: false
    )
    try FileManager.default.createSymbolicLink(
      at: storageDirectory,
      withDestinationURL: outsideDirectory
    )
    let token = try await traceToken(for: store)

    do {
      _ = try await store.record(draft(transcript: "retry after recovery"), using: token)
      XCTFail("A record write through a symlinked directory must fail")
    } catch {
      // Expected: only rollback/cleanup remains pending after the failure.
    }

    let disabledSnapshot = try await store.setEnabled(false)
    XCTAssertFalse(disabledSnapshot.isEnabled)
    XCTAssertTrue(disabledSnapshot.hasPendingStorageMaintenance)

    try FileManager.default.removeItem(at: storageDirectory)
    try FileManager.default.createDirectory(
      at: storageDirectory,
      withIntermediateDirectories: false
    )
    let recoveredSnapshot = try await store.snapshot()
    XCTAssertTrue(recoveredSnapshot.records.isEmpty)
    XCTAssertFalse(recoveredSnapshot.hasPendingStorageMaintenance)
    XCTAssertFalse(FileManager.default.fileExists(atPath: recoveredSnapshot.storageFileURL.path))
  }

  func testClearRejectsSymlinkedStorageWithoutDeletingOutsideFile() async throws {
    let appDirectory = storageDirectory.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: appDirectory,
      withIntermediateDirectories: false
    )
    let outsideDirectory = temporaryRoot.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outsideDirectory,
      withIntermediateDirectories: false
    )
    let outsideFile = outsideDirectory.appendingPathComponent("transcript-diagnostics.json")
    let sentinel = Data("must remain".utf8)
    try sentinel.write(to: outsideFile)
    try FileManager.default.createSymbolicLink(
      at: storageDirectory,
      withDestinationURL: outsideDirectory
    )
    let store = makeStore(initialEnabled: false)

    do {
      _ = try await store.clear()
      XCTFail("Clear must reject a symlinked diagnostics directory")
    } catch {
      // Expected: clearing must not follow the link to an outside file.
    }

    XCTAssertEqual(try Data(contentsOf: outsideFile), sentinel)
  }

  func testConcurrentWritesRemainValidAndBounded() async throws {
    let store = makeStore(initialEnabled: false)
    _ = try await store.setEnabled(true)
    let token = try await traceToken(for: store)
    let drafts = (0..<100).map { index in
      draft(transcript: "synthetic-\(index)")
    }

    try await withThrowingTaskGroup(of: Void.self) { group in
      for draft in drafts {
        group.addTask {
          _ = try await store.record(draft, using: token)
        }
      }
      try await group.waitForAll()
    }

    let snapshot = try await store.snapshot()
    XCTAssertEqual(snapshot.records.count, 100)
    XCTAssertEqual(Set(snapshot.records.map(\.transcript)).count, 100)
    XCTAssertNoThrow(try Data(contentsOf: snapshot.storageFileURL))
  }

  private func makeStore(
    initialEnabled: Bool,
    retention: DeveloperDiagnosticsRetentionPolicy = .standard,
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 500) },
    persistEnabled: @escaping @Sendable (Bool) -> Void = { _ in }
  ) -> DeveloperDiagnosticsStore {
    DeveloperDiagnosticsStore(
      storageDirectoryURL: storageDirectory,
      initialEnabled: initialEnabled,
      retention: retention,
      now: now,
      persistEnabled: persistEnabled
    )
  }

  private func traceToken(
    for store: DeveloperDiagnosticsStore
  ) async throws -> DeveloperDiagnosticsTraceToken {
    let token = await store.beginTrace()
    return try XCTUnwrap(token)
  }

  private func draft(
    transcript: String,
    recordedAt: Date = Date(timeIntervalSince1970: 499)
  ) -> DeveloperTranscriptRecordDraft {
    DeveloperTranscriptRecordDraft(
      recordedAt: recordedAt,
      source: .voice,
      transcript: transcript,
      trace: AssistantCommandTrace(
        outcome: .unsupported,
        commandKind: nil,
        capabilityIdentifier: nil
      ),
      processingDurationMilliseconds: 42,
      appVersion: "test",
      appBuild: "1"
    )
  }

  private func permissionBits(_ attributes: [FileAttributeKey: Any]) -> Int {
    (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
  }
}

private final class PreferenceBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Bool

  init(_ value: Bool) {
    storedValue = value
  }

  var value: Bool {
    get { lock.withLock { storedValue } }
    set { lock.withLock { storedValue = newValue } }
  }
}

private final class DateBox: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue: Date

  init(_ value: Date) {
    storedValue = value
  }

  var value: Date {
    get { lock.withLock { storedValue } }
    set { lock.withLock { storedValue = newValue } }
  }
}
