import SwiftUI
import TopherCore

struct DeveloperDiagnosticsView: View {
  @ObservedObject var diagnostics: DeveloperDiagnosticsController

  @State private var isExpanded = false
  @State private var pendingConfirmation: Confirmation?

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        Toggle(
          "Record final command transcripts",
          isOn: Binding(
            get: { diagnostics.isEnabled },
            set: { enabled in
              if enabled {
                pendingConfirmation = .enable
              } else {
                diagnostics.setEnabled(false)
              }
            }
          )
        )
        .disabled(diagnostics.isUpdating)
        .accessibilityHint(
          "When enabled, exact final voice and manual commands are retained locally for development."
        )

        Text(
          "Exact commands may include queries, URLs, pasted content, or secrets. Topher does not separately append audio, partial speech, page or screen context, constructed URLs, or detailed errors."
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

        Text(diagnostics.retentionSummary)
          .font(.caption2)
          .foregroundStyle(.secondary)

        if !diagnostics.latestRecords.isEmpty {
          Divider()

          Text("Latest requests")
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(diagnostics.latestRecords) { record in
            recordRow(record)
          }
        }

        HStack {
          Text(
            diagnostics.records.count == 1
              ? "1 recent request"
              : "\(diagnostics.records.count) recent requests"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)

          Spacer()

          Button("Clear Now", role: .destructive) {
            pendingConfirmation = .clear
          }
          .controlSize(.small)
          .disabled(
            (diagnostics.records.isEmpty && !diagnostics.hasPendingStorageMaintenance)
              || diagnostics.isUpdating
          )
        }

        if !diagnostics.isEnabled, !diagnostics.records.isEmpty {
          Text("Recording is off. Existing requests remain until they expire or you clear them.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        if let errorMessage = diagnostics.errorMessage {
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(errorMessage)
              .font(.caption2)
              .foregroundStyle(.red)
              .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("Dismiss") {
              diagnostics.dismissError()
            }
            .controlSize(.mini)
          }
        }
      }
      .padding(.top, 8)
    } label: {
      HStack(spacing: 8) {
        Label("Developer diagnostics", systemImage: "ladybug")
          .font(.caption)

        Spacer()

        if diagnostics.isEnabled {
          Circle()
            .fill(.orange)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
        }

        Text(diagnostics.isEnabled ? "On" : "Off")
          .font(.caption)
          .foregroundStyle(diagnostics.isEnabled ? .orange : .secondary)
      }
      .accessibilityElement(children: .combine)
      .accessibilityValue(diagnostics.isEnabled ? "Transcript recording on" : "Off")
    }
    .alert(item: $pendingConfirmation, content: confirmationAlert)
  }

  @ViewBuilder
  private func recordRow(_ record: DeveloperTranscriptRecord) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(record.transcript.isEmpty ? "(No usable speech)" : record.transcript)
        .font(.caption)
        .lineLimit(2)
        .help(record.transcript)

      if let interpretedTranscript = record.interpretedTranscript {
        Text(interpretationSummary(record, interpretedTranscript: interpretedTranscript))
          .font(.caption2)
          .foregroundStyle(.orange)
          .lineLimit(2)
          .help(interpretedTranscript)
      } else if let confidence = record.transcriptionConfidence {
        Text("Speech confidence: \(confidence.formatted(.percent.precision(.fractionLength(0))))")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if let reason = record.unsupportedReason {
        Text("Reason: \(reason.displayName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Text(
        "\(record.recordedAt.formatted(date: .omitted, time: .standard)) · \(record.source.displayName) · \(record.outcome.displayName) · v\(record.appVersion) (\(record.appBuild)) · \(record.processingDurationMilliseconds) ms"
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)

      if let timingSummary = timingSummary(record) {
        Text(timingSummary)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      HStack(spacing: 10) {
        if record.source == .voice {
          feedbackControl(
            label: "Transcript",
            value: record.transcriptWasAccurate,
            record: record,
            dimension: .transcriptAccuracy
          )
        }
        feedbackControl(
          label: "Action",
          value: record.actionWasCorrect,
          record: record,
          dimension: .actionCorrectness
        )
      }
      .padding(.top, 2)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private func feedbackControl(
    label: String,
    value: Bool?,
    record: DeveloperTranscriptRecord,
    dimension: DeveloperDiagnosticFeedbackDimension
  ) -> some View {
    HStack(spacing: 3) {
      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)

      feedbackButton(
        systemImage: value == true ? "hand.thumbsup.fill" : "hand.thumbsup",
        accessibilityLabel: "\(label) correct",
        isSelected: value == true
      ) {
        diagnostics.setFeedback(
          for: record,
          dimension: dimension,
          value: value == true ? nil : true
        )
      }

      feedbackButton(
        systemImage: value == false ? "hand.thumbsdown.fill" : "hand.thumbsdown",
        accessibilityLabel: "\(label) incorrect",
        isSelected: value == false
      ) {
        diagnostics.setFeedback(
          for: record,
          dimension: dimension,
          value: value == false ? nil : false
        )
      }
    }
  }

  private func feedbackButton(
    systemImage: String,
    accessibilityLabel: String,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.caption2)
        .foregroundStyle(isSelected ? .orange : .secondary)
    }
    .buttonStyle(.borderless)
    .disabled(diagnostics.isUpdating)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
  }

  private func timingSummary(_ record: DeveloperTranscriptRecord) -> String? {
    var parts: [String] = []
    if let duration = record.holdToListeningMilliseconds {
      parts.append("Hold→listen \(duration) ms")
    }
    if let duration = record.listeningToFirstTranscriptMilliseconds {
      parts.append("Listen→text \(duration) ms")
    }
    if let duration = record.keyUpToFinalMilliseconds {
      parts.append("Key-up→final \(duration) ms")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private func interpretationSummary(
    _ record: DeveloperTranscriptRecord,
    interpretedTranscript: String
  ) -> String {
    var summary = "Used: \(interpretedTranscript)"
    if let reason = record.interpretationReason {
      summary += " · \(reason.displayName)"
    }
    if let confidence = record.transcriptionConfidence {
      summary += " · \(confidence.formatted(.percent.precision(.fractionLength(0))))"
    }
    return summary
  }

  private func confirmationAlert(_ confirmation: Confirmation) -> Alert {
    switch confirmation {
    case .enable:
      Alert(
        title: Text("Enable transcript diagnostics?"),
        message: Text(
          "Topher will save the exact final text you speak or type, which may include queries, URLs, pasted content, or secrets. Records stay on this Mac and are automatically pruned."
        ),
        primaryButton: .default(Text("Enable")) {
          diagnostics.setEnabled(true)
        },
        secondaryButton: .cancel()
      )
    case .clear:
      Alert(
        title: Text("Clear recent transcript diagnostics?"),
        message: Text("This deletes Topher’s retained transcript records from its local cache."),
        primaryButton: .destructive(Text("Clear")) {
          diagnostics.clear()
        },
        secondaryButton: .cancel()
      )
    }
  }
}

extension TranscriptInterpretationReason {
  fileprivate var displayName: String {
    switch self {
    case .speechAlternative:
      "Speech alternative"
    case .vocabularyCorrection:
      "Vocabulary correction"
    }
  }
}

extension UnsupportedCommandReason {
  fileprivate var displayName: String {
    switch self {
    case .compoundRequest:
      "Compound request"
    case .contextRequired:
      "Context required"
    case .emptyInput:
      "Empty input"
    case .missingValue:
      "Missing value"
    case .unknownTarget:
      "Unknown target"
    case .unsupportedAction:
      "Unsupported target action"
    case .unsupportedPhrasing:
      "Unsupported phrasing"
    }
  }
}

extension DeveloperDiagnosticsView {
  private enum Confirmation: Int, Identifiable {
    case clear
    case enable

    var id: Int { rawValue }
  }
}
