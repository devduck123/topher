import Darwin
import Foundation
import OSLog
import TopherCore

enum DeveloperTranscriptSource: String, Codable, Equatable, Sendable {
  case manual
  case voice

  var displayName: String {
    switch self {
    case .manual:
      "Manual"
    case .voice:
      "Voice"
    }
  }
}

enum AssistantCommandKind: String, Codable, Equatable, Sendable {
  case activateChromeTab
  case identifyActiveChromeTab
  case identifyFrontmostApplication
  case listChromeTabs
  case openApplication
  case openInstalledApplication
  case openBrowserRoute
  case openDomain
  case openWebsite
  case searchWeb
  case searchUnknownDestination
}

enum AssistantCommandTraceOutcome: String, Codable, Equatable, Sendable {
  case capabilityFailed
  case capabilitySucceeded
  case noUsableSpeech
  case policyDenied
  case unsupported

  var displayName: String {
    switch self {
    case .capabilityFailed:
      "Capability failed"
    case .capabilitySucceeded:
      "Succeeded"
    case .noUsableSpeech:
      "No usable speech"
    case .policyDenied:
      "Policy denied"
    case .unsupported:
      "Unsupported"
    }
  }
}

struct AssistantCommandTrace: Equatable, Sendable {
  let outcome: AssistantCommandTraceOutcome
  let commandKind: AssistantCommandKind?
  let capabilityIdentifier: String?
  let unsupportedReason: UnsupportedCommandReason?

  init(
    outcome: AssistantCommandTraceOutcome,
    commandKind: AssistantCommandKind?,
    capabilityIdentifier: String?,
    unsupportedReason: UnsupportedCommandReason? = nil
  ) {
    self.outcome = outcome
    self.commandKind = commandKind
    self.capabilityIdentifier = capabilityIdentifier
    self.unsupportedReason = unsupportedReason
  }
}

enum DeveloperDiagnosticFeedbackDimension: Equatable, Sendable {
  case transcriptAccuracy
  case actionCorrectness
}

struct DeveloperTranscriptRecord: Codable, Equatable, Identifiable, Sendable {
  static let currentSchemaVersion = 1

  let schemaVersion: Int
  let id: UUID
  let launchSessionID: UUID?
  let recordedAt: Date
  let source: DeveloperTranscriptSource
  let transcript: String
  let transcriptWasTruncated: Bool
  let interpretedTranscript: String?
  let interpretationReason: TranscriptInterpretationReason?
  let transcriptionConfidence: Double?
  let holdToListeningMilliseconds: UInt64?
  let listeningToFirstTranscriptMilliseconds: UInt64?
  let keyUpToFinalMilliseconds: UInt64?
  let outcome: AssistantCommandTraceOutcome
  let commandKind: AssistantCommandKind?
  let capabilityIdentifier: String?
  let unsupportedReason: UnsupportedCommandReason?
  var transcriptWasAccurate: Bool?
  var actionWasCorrect: Bool?
  let processingDurationMilliseconds: UInt64
  let appVersion: String
  let appBuild: String
}

struct DeveloperTranscriptRecordDraft: Equatable, Sendable {
  let recordedAt: Date
  let launchSessionID: UUID?
  let source: DeveloperTranscriptSource
  let transcript: String
  let interpretedTranscript: String?
  let interpretationReason: TranscriptInterpretationReason?
  let transcriptionConfidence: Double?
  let holdToListeningMilliseconds: UInt64?
  let listeningToFirstTranscriptMilliseconds: UInt64?
  let keyUpToFinalMilliseconds: UInt64?
  let trace: AssistantCommandTrace
  let processingDurationMilliseconds: UInt64
  let appVersion: String
  let appBuild: String

  init(
    recordedAt: Date,
    launchSessionID: UUID? = nil,
    source: DeveloperTranscriptSource,
    transcript: String,
    interpretedTranscript: String? = nil,
    interpretationReason: TranscriptInterpretationReason? = nil,
    transcriptionConfidence: Double? = nil,
    holdToListeningMilliseconds: UInt64? = nil,
    listeningToFirstTranscriptMilliseconds: UInt64? = nil,
    keyUpToFinalMilliseconds: UInt64? = nil,
    trace: AssistantCommandTrace,
    processingDurationMilliseconds: UInt64,
    appVersion: String,
    appBuild: String
  ) {
    self.recordedAt = recordedAt
    self.launchSessionID = launchSessionID
    self.source = source
    self.transcript = transcript
    self.interpretedTranscript = interpretedTranscript
    self.interpretationReason = interpretationReason
    self.transcriptionConfidence = transcriptionConfidence
    self.holdToListeningMilliseconds = holdToListeningMilliseconds
    self.listeningToFirstTranscriptMilliseconds = listeningToFirstTranscriptMilliseconds
    self.keyUpToFinalMilliseconds = keyUpToFinalMilliseconds
    self.trace = trace
    self.processingDurationMilliseconds = processingDurationMilliseconds
    self.appVersion = appVersion
    self.appBuild = appBuild
  }
}

struct DeveloperDiagnosticsSnapshot: Equatable, Sendable {
  let revision: UInt64
  let isEnabled: Bool
  let records: [DeveloperTranscriptRecord]
  let hasPendingStorageMaintenance: Bool
  let storageFileURL: URL
}

struct DeveloperDiagnosticsTraceToken: Equatable, Sendable {
  fileprivate let generation: UInt64
}

struct DeveloperDiagnosticsRetentionPolicy: Equatable, Sendable {
  static let standard = DeveloperDiagnosticsRetentionPolicy(
    maximumAge: 24 * 60 * 60,
    maximumRecordCount: 200,
    maximumFileSizeBytes: 1_048_576,
    maximumTranscriptBytes: 4_096
  )

  let maximumAge: TimeInterval
  let maximumRecordCount: Int
  let maximumFileSizeBytes: Int
  let maximumTranscriptBytes: Int
}

actor DeveloperDiagnosticsStore {
  static let preferenceKey = "developerDiagnostics.transcriptRecordingEnabled"

  nonisolated let initialEnabled: Bool
  nonisolated let storageDirectoryURL: URL
  nonisolated let storageFileURL: URL

  private static let documentSchemaVersion = 1
  private static let maximumStageTimingMilliseconds: UInt64 = 10 * 60 * 1_000

  private let fileManager = FileManager.default
  private let retention: DeveloperDiagnosticsRetentionPolicy
  private let now: @Sendable () -> Date
  private let persistEnabled: @Sendable (Bool) -> Void
  private let logger = Logger(subsystem: "dev.topher.app", category: "developer-diagnostics")

  private var isEnabled: Bool
  private var generation: UInt64 = 0
  private var revision: UInt64 = 0
  private var records: [DeveloperTranscriptRecord]?
  private var needsPersistence = false

  init(
    storageDirectoryURL: URL,
    initialEnabled: Bool,
    retention: DeveloperDiagnosticsRetentionPolicy = .standard,
    now: @escaping @Sendable () -> Date = Date.init,
    persistEnabled: @escaping @Sendable (Bool) -> Void = { _ in }
  ) {
    self.storageDirectoryURL = storageDirectoryURL
    storageFileURL = storageDirectoryURL.appendingPathComponent(
      "transcript-diagnostics.json",
      isDirectory: false
    )
    self.initialEnabled = initialEnabled
    self.isEnabled = initialEnabled
    self.retention = retention
    self.now = now
    self.persistEnabled = persistEnabled
  }

  static func live(userDefaults: UserDefaults = .standard) -> DeveloperDiagnosticsStore {
    let defaults = SendableUserDefaults(userDefaults)
    let fileManager = FileManager.default
    let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    let directoryURL =
      cachesURL
      .appendingPathComponent("dev.topher.app", isDirectory: true)
      .appendingPathComponent("TranscriptDiagnostics", isDirectory: true)
    // Local dogfood builds favor useful evidence: record by default until the
    // user explicitly opts out. A persisted false value always wins.
    let enabled = defaults.bool(forKey: preferenceKey, defaultValue: true)

    return DeveloperDiagnosticsStore(
      storageDirectoryURL: directoryURL,
      initialEnabled: enabled,
      persistEnabled: { value in
        defaults.set(value, forKey: preferenceKey)
      }
    )
  }

  func beginTrace() -> DeveloperDiagnosticsTraceToken? {
    guard isEnabled else { return nil }
    return DeveloperDiagnosticsTraceToken(generation: generation)
  }

  func setEnabled(_ enabled: Bool) throws -> DeveloperDiagnosticsSnapshot {
    if enabled {
      try ensureStorageDirectory()
      try loadIfNeeded()
      try pruneAndPersistIfNeeded()

      generation &+= 1
      isEnabled = true
      persistEnabled(true)
      revision &+= 1
      return currentSnapshot()
    }

    generation &+= 1
    isEnabled = false
    persistEnabled(false)

    do {
      try loadIfNeeded()
      try pruneAndPersistIfNeeded()
    } catch {
      logger.error("Developer diagnostics maintenance failed while disabling")
    }
    revision &+= 1
    return currentSnapshot()
  }

  func snapshot() throws -> DeveloperDiagnosticsSnapshot {
    try loadIfNeeded()
    try pruneAndPersistIfNeeded()
    revision &+= 1
    return currentSnapshot()
  }

  func record(
    _ draft: DeveloperTranscriptRecordDraft,
    using token: DeveloperDiagnosticsTraceToken
  ) throws -> DeveloperDiagnosticsSnapshot {
    guard isEnabled, token.generation == generation else {
      return currentSnapshot()
    }

    try loadIfNeeded()
    let previousRecords = records ?? []

    let boundedTranscript = Self.boundedUTF8(
      draft.transcript,
      maximumBytes: retention.maximumTranscriptBytes
    )
    let boundedInterpretation = draft.interpretedTranscript.map {
      Self.boundedUTF8($0, maximumBytes: retention.maximumTranscriptBytes)
    }
    let record = DeveloperTranscriptRecord(
      schemaVersion: DeveloperTranscriptRecord.currentSchemaVersion,
      id: UUID(),
      launchSessionID: draft.launchSessionID,
      recordedAt: draft.recordedAt,
      source: draft.source,
      transcript: boundedTranscript.value,
      transcriptWasTruncated: boundedTranscript.wasTruncated,
      interpretedTranscript: boundedInterpretation?.value,
      interpretationReason: draft.interpretationReason,
      transcriptionConfidence: draft.transcriptionConfidence,
      holdToListeningMilliseconds: Self.validatedTiming(draft.holdToListeningMilliseconds),
      listeningToFirstTranscriptMilliseconds: Self.validatedTiming(
        draft.listeningToFirstTranscriptMilliseconds
      ),
      keyUpToFinalMilliseconds: Self.validatedTiming(draft.keyUpToFinalMilliseconds),
      outcome: draft.trace.outcome,
      commandKind: draft.trace.commandKind,
      capabilityIdentifier: draft.trace.capabilityIdentifier,
      unsupportedReason: draft.trace.unsupportedReason,
      transcriptWasAccurate: nil,
      actionWasCorrect: nil,
      processingDurationMilliseconds: draft.processingDurationMilliseconds,
      appVersion: draft.appVersion,
      appBuild: draft.appBuild
    )

    records?.append(record)
    needsPersistence = true
    do {
      try applyRetentionBounds()
      try persistPendingRecords()
    } catch {
      let writeError = error
      records = previousRecords
      needsPersistence = true
      try? persistPendingRecords()
      throw writeError
    }
    revision &+= 1
    return currentSnapshot()
  }

  func setFeedback(
    recordID: UUID,
    dimension: DeveloperDiagnosticFeedbackDimension,
    value: Bool?
  ) throws -> DeveloperDiagnosticsSnapshot {
    try loadIfNeeded()
    guard let index = records?.firstIndex(where: { $0.id == recordID }) else {
      return currentSnapshot()
    }

    let previousRecords = records ?? []
    switch dimension {
    case .transcriptAccuracy:
      guard records?[index].transcriptWasAccurate != value else {
        return currentSnapshot()
      }
      records?[index].transcriptWasAccurate = value
    case .actionCorrectness:
      guard records?[index].actionWasCorrect != value else {
        return currentSnapshot()
      }
      records?[index].actionWasCorrect = value
    }

    needsPersistence = true
    do {
      try applyRetentionBounds()
      try persistPendingRecords()
    } catch {
      let writeError = error
      records = previousRecords
      needsPersistence = true
      try? persistPendingRecords()
      throw writeError
    }
    revision &+= 1
    return currentSnapshot()
  }

  func clear() throws -> DeveloperDiagnosticsSnapshot {
    generation &+= 1
    records = []
    needsPersistence = true
    try persistPendingRecords()
    revision &+= 1
    return currentSnapshot()
  }

  private func currentSnapshot() -> DeveloperDiagnosticsSnapshot {
    DeveloperDiagnosticsSnapshot(
      revision: revision,
      isEnabled: isEnabled,
      records: records ?? [],
      hasPendingStorageMaintenance: needsPersistence,
      storageFileURL: storageFileURL
    )
  }

  private func loadIfNeeded() throws {
    guard records == nil else { return }

    try verifyExistingStorageDirectoryHierarchy()
    guard try status(at: storageFileURL) != nil else {
      records = []
      needsPersistence = false
      return
    }

    let document: Document
    do {
      try ensureStorageDirectory()
      try verifyRegularFile(storageFileURL)
      try fileManager.setAttributes(
        [.posixPermissions: NSNumber(value: Int16(0o600))],
        ofItemAtPath: storageFileURL.path
      )

      let attributes = try fileManager.attributesOfItem(atPath: storageFileURL.path)
      if let fileSize = attributes[.size] as? NSNumber,
        fileSize.intValue > retention.maximumFileSizeBytes
      {
        throw DeveloperDiagnosticsStoreError.invalidDocument
      }

      let data = try Data(contentsOf: storageFileURL)
      document = try Self.decoder.decode(Document.self, from: data)
      guard document.schemaVersion == Self.documentSchemaVersion else {
        throw DeveloperDiagnosticsStoreError.invalidDocument
      }
    } catch DeveloperDiagnosticsStoreError.unsafePath {
      records = nil
      needsPersistence = false
      throw DeveloperDiagnosticsStoreError.unsafePath
    } catch {
      records = []
      needsPersistence = true
      try persistPendingRecords()
      logger.error("Developer diagnostics storage was unreadable and cleared")
      return
    }

    let decodedRecords = document.records
    records = decodedRecords.compactMap(normalizedRecord)
    try applyRetentionBounds()
    if records != decodedRecords {
      needsPersistence = true
    }
    try persistPendingRecords()
  }

  private func pruneAndPersistIfNeeded() throws {
    let previousRecords = records ?? []
    try applyRetentionBounds()
    if previousRecords != records {
      needsPersistence = true
    }
    try persistPendingRecords()
  }

  private func applyRetentionBounds() throws {
    guard var retainedRecords = records else { return }

    let cutoff = now().addingTimeInterval(-retention.maximumAge)
    retainedRecords = retainedRecords.filter { $0.recordedAt >= cutoff }

    if retainedRecords.count > retention.maximumRecordCount {
      retainedRecords = Array(retainedRecords.suffix(retention.maximumRecordCount))
    }

    while !retainedRecords.isEmpty,
      try encodedDocument(for: retainedRecords).count > retention.maximumFileSizeBytes
    {
      retainedRecords.removeFirst()
    }

    records = retainedRecords
  }

  private func normalizedRecord(
    _ record: DeveloperTranscriptRecord
  ) -> DeveloperTranscriptRecord? {
    guard record.schemaVersion == DeveloperTranscriptRecord.currentSchemaVersion else {
      return nil
    }

    let boundedTranscript = Self.boundedUTF8(
      record.transcript,
      maximumBytes: retention.maximumTranscriptBytes
    )
    let boundedInterpretation = record.interpretedTranscript.map {
      Self.boundedUTF8($0, maximumBytes: retention.maximumTranscriptBytes)
    }
    let contentWasTruncated =
      boundedTranscript.wasTruncated || boundedInterpretation?.wasTruncated == true
    let holdToListeningMilliseconds = Self.validatedTiming(
      record.holdToListeningMilliseconds
    )
    let listeningToFirstTranscriptMilliseconds = Self.validatedTiming(
      record.listeningToFirstTranscriptMilliseconds
    )
    let keyUpToFinalMilliseconds = Self.validatedTiming(record.keyUpToFinalMilliseconds)
    let timingWasInvalid =
      holdToListeningMilliseconds != record.holdToListeningMilliseconds
      || listeningToFirstTranscriptMilliseconds != record.listeningToFirstTranscriptMilliseconds
      || keyUpToFinalMilliseconds != record.keyUpToFinalMilliseconds
    guard contentWasTruncated || timingWasInvalid else { return record }

    return DeveloperTranscriptRecord(
      schemaVersion: record.schemaVersion,
      id: record.id,
      launchSessionID: record.launchSessionID,
      recordedAt: record.recordedAt,
      source: record.source,
      transcript: boundedTranscript.value,
      transcriptWasTruncated: record.transcriptWasTruncated || contentWasTruncated,
      interpretedTranscript: boundedInterpretation?.value,
      interpretationReason: record.interpretationReason,
      transcriptionConfidence: record.transcriptionConfidence,
      holdToListeningMilliseconds: holdToListeningMilliseconds,
      listeningToFirstTranscriptMilliseconds: listeningToFirstTranscriptMilliseconds,
      keyUpToFinalMilliseconds: keyUpToFinalMilliseconds,
      outcome: record.outcome,
      commandKind: record.commandKind,
      capabilityIdentifier: record.capabilityIdentifier,
      unsupportedReason: record.unsupportedReason,
      transcriptWasAccurate: record.transcriptWasAccurate,
      actionWasCorrect: record.actionWasCorrect,
      processingDurationMilliseconds: record.processingDurationMilliseconds,
      appVersion: record.appVersion,
      appBuild: record.appBuild
    )
  }

  private static func validatedTiming(_ value: UInt64?) -> UInt64? {
    guard let value, value <= maximumStageTimingMilliseconds else { return nil }
    return value
  }

  private func persistCurrentRecords() throws {
    let currentRecords = records ?? []
    guard !currentRecords.isEmpty else {
      try removeStorageFileIfPresent()
      return
    }

    try ensureStorageDirectory()
    if try status(at: storageFileURL) != nil {
      try verifyRegularFile(storageFileURL)
    }

    let data = try encodedDocument(for: currentRecords)
    guard data.count <= retention.maximumFileSizeBytes else {
      throw DeveloperDiagnosticsStoreError.invalidDocument
    }

    try data.write(to: storageFileURL, options: .atomic)
    try fileManager.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o600))],
      ofItemAtPath: storageFileURL.path
    )
    try excludeFromBackup(storageFileURL)
    try verifyRegularFile(storageFileURL)
  }

  private func persistPendingRecords() throws {
    guard needsPersistence else { return }
    try persistCurrentRecords()
    needsPersistence = false
  }

  private func encodedDocument(for records: [DeveloperTranscriptRecord]) throws -> Data {
    try Self.encoder.encode(
      Document(schemaVersion: Self.documentSchemaVersion, records: records)
    )
  }

  private func ensureStorageDirectory() throws {
    let appDirectoryURL = storageDirectoryURL.deletingLastPathComponent()
    try ensureOwnedDirectory(appDirectoryURL)
    try ensureOwnedDirectory(storageDirectoryURL)
    try excludeFromBackup(appDirectoryURL)
    try excludeFromBackup(storageDirectoryURL)
  }

  private func ensureOwnedDirectory(_ url: URL) throws {
    if try status(at: url) == nil {
      try fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
      )
    }

    try verifyDirectoryIfPresent(url)
    try fileManager.setAttributes(
      [.posixPermissions: NSNumber(value: Int16(0o700))],
      ofItemAtPath: url.path
    )
  }

  private func verifyDirectoryIfPresent(_ url: URL) throws {
    guard let itemStatus = try status(at: url) else { return }
    guard
      itemStatus.st_mode & S_IFMT == S_IFDIR,
      itemStatus.st_uid == getuid()
    else {
      throw DeveloperDiagnosticsStoreError.unsafePath
    }
  }

  private func verifyRegularFile(_ url: URL) throws {
    guard let itemStatus = try status(at: url) else {
      throw DeveloperDiagnosticsStoreError.storageUnavailable
    }
    guard
      itemStatus.st_mode & S_IFMT == S_IFREG,
      itemStatus.st_uid == getuid(),
      itemStatus.st_nlink == 1
    else {
      throw DeveloperDiagnosticsStoreError.unsafePath
    }
  }

  private func removeStorageFileIfPresent() throws {
    try verifyExistingStorageDirectoryHierarchy()
    guard try status(at: storageFileURL) != nil else { return }
    try verifyRegularFile(storageFileURL)
    try fileManager.removeItem(at: storageFileURL)
  }

  private func verifyExistingStorageDirectoryHierarchy() throws {
    let appDirectoryURL = storageDirectoryURL.deletingLastPathComponent()
    guard try status(at: appDirectoryURL) != nil else { return }
    try verifyDirectoryIfPresent(appDirectoryURL)
    guard try status(at: storageDirectoryURL) != nil else { return }
    try verifyDirectoryIfPresent(storageDirectoryURL)
  }

  private func excludeFromBackup(_ url: URL) throws {
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try mutableURL.setResourceValues(values)
  }

  private func status(at url: URL) throws -> stat? {
    var itemStatus = stat()
    let result = url.withUnsafeFileSystemRepresentation { path -> Int32 in
      guard let path else {
        errno = EINVAL
        return -1
      }
      return lstat(path, &itemStatus)
    }

    if result == 0 {
      return itemStatus
    }
    if errno == ENOENT {
      return nil
    }
    throw DeveloperDiagnosticsStoreError.storageUnavailable
  }

  private static func boundedUTF8(
    _ value: String,
    maximumBytes: Int
  ) -> (value: String, wasTruncated: Bool) {
    guard value.utf8.count > maximumBytes else { return (value, false) }

    var bounded = ""
    var byteCount = 0
    for character in value {
      let characterByteCount = String(character).utf8.count
      guard byteCount + characterByteCount <= maximumBytes else { break }
      bounded.append(character)
      byteCount += characterByteCount
    }
    return (bounded, true)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}

extension DeveloperDiagnosticsStore {
  private struct Document: Codable {
    let schemaVersion: Int
    let records: [DeveloperTranscriptRecord]
  }
}

private enum DeveloperDiagnosticsStoreError: Error {
  case invalidDocument
  case storageUnavailable
  case unsafePath
}

private final class SendableUserDefaults: @unchecked Sendable {
  private let userDefaults: UserDefaults

  init(_ userDefaults: UserDefaults) {
    self.userDefaults = userDefaults
  }

  func bool(forKey key: String, defaultValue: Bool) -> Bool {
    guard userDefaults.object(forKey: key) != nil else { return defaultValue }
    return userDefaults.bool(forKey: key)
  }

  func set(_ value: Bool, forKey key: String) {
    userDefaults.set(value, forKey: key)
  }
}
