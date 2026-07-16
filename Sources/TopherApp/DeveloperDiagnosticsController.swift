import Combine
import Foundation
import OSLog
import TopherCore

@MainActor
final class DeveloperDiagnosticsController: ObservableObject {
  @Published private(set) var isEnabled: Bool
  @Published private(set) var records: [DeveloperTranscriptRecord] = []
  @Published private(set) var isUpdating = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var hasPendingStorageMaintenance = false

  let storageFileURL: URL

  var latestRecords: [DeveloperTranscriptRecord] {
    Array(records.suffix(3).reversed())
  }

  var retentionSummary: String {
    "Keeps up to 200 requests for 24 hours (1 MB total, 4 KB each)."
  }

  private let store: DeveloperDiagnosticsStore
  private let now: @Sendable () -> Date
  private let appVersion: String
  private let appBuild: String
  private let logger = Logger(subsystem: "dev.topher.app", category: "developer-diagnostics")
  private var maintenanceTask: Task<Void, Never>?
  private var lastAppliedRevision: UInt64?

  private static let pendingMaintenanceMessage =
    "Local diagnostics cleanup is pending. Clear Now will retry it."

  init(
    store: DeveloperDiagnosticsStore = .live(),
    now: @escaping @Sendable () -> Date = Date.init,
    appVersion: String? = nil,
    appBuild: String? = nil,
    maintenanceInterval: Duration? = .seconds(60 * 60)
  ) {
    self.store = store
    self.now = now
    self.appVersion =
      appVersion
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "development"
    self.appBuild =
      appBuild
      ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
      ?? "development"
    isEnabled = store.initialEnabled
    storageFileURL = store.storageFileURL

    Task { [weak self] in
      await self?.refresh()
    }

    if let maintenanceInterval {
      maintenanceTask = Task { [weak self] in
        while !Task.isCancelled {
          do {
            try await Task.sleep(for: maintenanceInterval)
          } catch {
            return
          }
          await self?.refresh()
        }
      }
    }
  }

  deinit {
    maintenanceTask?.cancel()
  }

  func setEnabled(_ enabled: Bool) {
    guard !isUpdating, enabled != isEnabled else { return }
    isUpdating = true
    errorMessage = nil

    Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await store.setEnabled(enabled)
        apply(snapshot)
      } catch {
        errorMessage = "Couldn’t update transcript diagnostics. No transcript was saved."
        logger.error("Developer diagnostics setting update failed")
      }
      isUpdating = false
    }
  }

  func clear() {
    guard !isUpdating else { return }
    isUpdating = true
    errorMessage = nil

    Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await store.clear()
        apply(snapshot)
      } catch {
        errorMessage = "Couldn’t clear transcript diagnostics."
        hasPendingStorageMaintenance = true
        logger.error("Developer diagnostics clear failed")
      }
      isUpdating = false
    }
  }

  func dismissError() {
    errorMessage = nil
  }

  func setFeedback(
    for record: DeveloperTranscriptRecord,
    dimension: DeveloperDiagnosticFeedbackDimension,
    value: Bool?
  ) {
    guard !isUpdating else { return }
    isUpdating = true
    errorMessage = nil

    Task { [weak self] in
      guard let self else { return }
      do {
        let snapshot = try await store.setFeedback(
          recordID: record.id,
          dimension: dimension,
          value: value
        )
        apply(snapshot)
      } catch {
        errorMessage = "Couldn’t save diagnostic feedback."
        hasPendingStorageMaintenance = true
        logger.error("Developer diagnostics feedback write failed")
      }
      isUpdating = false
    }
  }

  func beginTrace() async -> DeveloperDiagnosticsTraceToken? {
    await store.beginTrace()
  }

  func record(
    transcript: String,
    interpretedTranscript: String? = nil,
    interpretationReason: TranscriptInterpretationReason? = nil,
    transcriptionConfidence: Double? = nil,
    captureMetrics: VoiceCaptureMetrics? = nil,
    source: DeveloperTranscriptSource,
    trace: AssistantCommandTrace,
    processingDurationMilliseconds: UInt64,
    using token: DeveloperDiagnosticsTraceToken
  ) async {
    let draft = DeveloperTranscriptRecordDraft(
      recordedAt: now(),
      source: source,
      transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
      interpretedTranscript: interpretedTranscript?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      interpretationReason: interpretationReason,
      transcriptionConfidence: transcriptionConfidence.flatMap {
        $0.isFinite ? min(max($0, 0), 1) : nil
      },
      holdToListeningMilliseconds: captureMetrics?.holdToListeningMilliseconds,
      listeningToFirstTranscriptMilliseconds: captureMetrics?
        .listeningToFirstTranscriptMilliseconds,
      keyUpToFinalMilliseconds: captureMetrics?.keyUpToFinalMilliseconds,
      trace: trace,
      processingDurationMilliseconds: processingDurationMilliseconds,
      appVersion: appVersion,
      appBuild: appBuild
    )

    do {
      let snapshot = try await store.record(draft, using: token)
      apply(snapshot)
    } catch {
      errorMessage =
        "Couldn’t save the latest transcript diagnostic. The command still ran; Clear Now can retry cleanup."
      hasPendingStorageMaintenance = true
      logger.error("Developer diagnostics record write failed")
    }
  }

  func refresh() async {
    do {
      let snapshot = try await store.snapshot()
      apply(snapshot)
    } catch {
      errorMessage = "Couldn’t read transcript diagnostics."
      logger.error("Developer diagnostics refresh failed")
    }
  }

  private func apply(_ snapshot: DeveloperDiagnosticsSnapshot) {
    if let lastAppliedRevision, snapshot.revision <= lastAppliedRevision {
      return
    }
    lastAppliedRevision = snapshot.revision
    isEnabled = snapshot.isEnabled
    records = snapshot.records
    hasPendingStorageMaintenance = snapshot.hasPendingStorageMaintenance
    if snapshot.hasPendingStorageMaintenance {
      errorMessage = Self.pendingMaintenanceMessage
    } else if errorMessage == Self.pendingMaintenanceMessage {
      errorMessage = nil
    }
  }
}
