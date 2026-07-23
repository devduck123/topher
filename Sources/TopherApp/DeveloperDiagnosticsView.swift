import SwiftUI
import TopherCore

struct DeveloperDiagnosticsView: View {
  @ObservedObject var diagnostics: DeveloperDiagnosticsController

  @State private var isExpanded = false
  @State private var pendingConfirmation: Confirmation?

  init(
    diagnostics: DeveloperDiagnosticsController,
    startsExpanded: Bool = false
  ) {
    self.diagnostics = diagnostics
    _isExpanded = State(initialValue: startsExpanded)
  }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      VStack(alignment: .leading, spacing: 10) {
        Toggle(
          "Record final commands and dictation",
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
          "When enabled, exact final voice commands, manual commands, and non-secure dictation are retained locally for development."
        )

        Text(
          "Exact requests may include queries, URLs, pasted content, or secrets. Secure-field dictation is excluded. Topher does not separately append audio, partial speech, page or screen context, constructed URLs, or detailed errors."
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

      if let reason = record.dictationFailureReason {
        Text("Insertion fallback: \(reason.displayName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if let evidence = record.dictationPreparationEvidence {
        Text(preparationEvidenceSummary(evidence))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      if let evidence = record.dictationInsertionEvidence {
        Text(insertionEvidenceSummary(evidence))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }

      if let reason = record.captureFailureReason {
        Text("Capture failure: \(reason.displayName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if record.maximumDurationReached == true {
        Text("Automatically finalized at the maximum duration")
          .font(.caption2)
          .foregroundStyle(.orange)
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
        if record.source == .voice || record.source == .dictation {
          feedbackControl(
            label: "Transcript",
            value: record.transcriptWasAccurate,
            record: record,
            dimension: .transcriptAccuracy
          )
        }
        feedbackControl(
          label: record.source == .dictation ? "Insertion" : "Action",
          value: record.actionWasCorrect,
          record: record,
          dimension: .actionCorrectness
        )

        if record.actionWasCorrect == false {
          actionIssueMenu(record)
        }
      }
      .padding(.top, 2)
    }
    .accessibilityElement(children: .contain)
  }

  private func actionIssueMenu(_ record: DeveloperTranscriptRecord) -> some View {
    Menu {
      ForEach(DeveloperActionIssueReason.allCases, id: \.self) { reason in
        Button {
          diagnostics.setActionIssueReason(for: record, reason: reason)
        } label: {
          if record.actionIssueReason == reason {
            Label(reason.displayName, systemImage: "checkmark")
          } else {
            Text(reason.displayName)
          }
        }
      }

      if record.actionIssueReason != nil {
        Divider()
        Button("Clear reason") {
          diagnostics.setActionIssueReason(for: record, reason: nil)
        }
      }
    } label: {
      Label(record.actionIssueReason?.displayName ?? "Why?", systemImage: "tag")
        .font(.caption2)
    }
    .menuStyle(.borderlessButton)
    .disabled(diagnostics.isUpdating)
    .accessibilityLabel("Incorrect action reason")
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

  private func insertionEvidenceSummary(_ evidence: FocusedTextInsertionEvidence) -> String {
    var summary =
      "Adapter: \(evidence.method.rawValue) · \(evidence.verification.rawValue) · \(evidence.target.role.rawValue)"
    if let application = evidence.target.application {
      summary += " · \(application.displayName)"
    }
    if let selectionRelation = evidence.selectionRelation {
      summary += " · \(selectionRelation.displayName)"
    }
    if let decision = evidence.wholeValueDecision {
      summary += " · \(decision.displayName)"
    }
    if evidence.placeholderState == .matchesValue {
      summary += " · Placeholder-backed value"
    }
    if let attributeDecision = evidence.attributeDecision,
      attributeDecision != .notEvaluated
    {
      summary += " · \(attributeDecision.displayName)"
    }
    if let semanticDecision = evidence.semanticContentDecision,
      semanticDecision != .notEvaluated
    {
      summary += " · \(semanticDecision.displayName)"
      if let state = evidence.semanticSuggestionAttributeState {
        summary += " · suggestion=\(state.rawValue)"
      }
      if let state = evidence.semanticCharacterCountState {
        summary += " · characters=\(state.rawValue)"
      }
      if let state = evidence.semanticTextMarkerState {
        summary += " · marker=\(state.rawValue)"
      }
      if let state = evidence.semanticKnownSuggestionState {
        summary += " · known-suggestion=\(state.rawValue)"
      }
    }
    return summary
  }

  private func preparationEvidenceSummary(_ evidence: FocusedTextPreparationEvidence) -> String {
    var parts = ["Target preparation"]
    if let application = evidence.targetApplication {
      parts.append(application.displayName)
    }
    if let source = evidence.focusSource {
      parts.append(source == .systemWide ? "system focus" : "application focus")
    }
    if let reason = evidence.failureReason {
      parts.append(reason.rawValue)
    }
    return parts.joined(separator: " · ")
  }

  private func confirmationAlert(_ confirmation: Confirmation) -> Alert {
    switch confirmation {
    case .enable:
      Alert(
        title: Text("Enable transcript diagnostics?"),
        message: Text(
          "Topher will save the exact final text you speak or type, except dictation targeting secure fields. Records may include queries, URLs, pasted content, or secrets; they stay on this Mac and are automatically pruned."
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
    case .dictationDisfluencyCleanup:
      "Repeated speech removed"
    case .dictationPauseJoin:
      "Short-pause sentence joined"
    case .dictationSpokenPunctuation:
      "Spoken punctuation"
    case .speechAlternative:
      "Speech alternative"
    case .vocabularyCorrection:
      "Vocabulary correction"
    }
  }
}

extension FocusedTextWholeValueDecision {
  fileprivate var displayName: String {
    switch self {
    case .eligibleTextField:
      "Text field value eligible"
    case .eligibleEmptyTextArea:
      "Empty text area eligible"
    case .eligibleFullValueReplacement:
      "Full selection eligible"
    case .eligiblePlainWebComposer:
      "Plain web composer eligible"
    case .eligiblePlainWebSelection:
      "Plain web caret insertion eligible"
    case .eligibleSemanticallyEmptyWebComposer:
      "Semantically empty web composer eligible"
    case .rejectedValueUnavailableOrInconsistent:
      "Value unavailable or inconsistent"
    case .rejectedValueNotSettable:
      "Value is not writable"
    case .rejectedUnsupportedRole:
      "Unsupported target role"
    case .rejectedNonWebTextArea:
      "No bounded web ancestor"
    case .rejectedOversizedWebValue:
      "Web value exceeds safety bound"
    case .rejectedObjectBearingWebValue:
      "Web value contains an object"
    case .rejectedRichWebValue:
      "Web value has mixed formatting"
    case .rejectedAmbiguousWebSelection:
      "Web selection is ambiguous"
    case .rejectedPlaceholderBackedValue:
      "Value matches placeholder"
    }
  }
}

extension FocusedTextTargetApplication {
  fileprivate var displayName: String {
    switch self {
    case .chrome:
      "Chrome"
    case .codexOrChatGPT:
      "Codex/ChatGPT"
    case .notion:
      "Notion"
    case .notes:
      "Notes"
    case .safari:
      "Safari"
    case .terminal:
      "Terminal"
    case .visualStudioCode:
      "Visual Studio Code"
    case .other:
      "Other app"
    case .unknown:
      "Unknown app"
    }
  }
}

extension FocusedTextSemanticContentDecision {
  fileprivate var displayName: String {
    switch self {
    case .notEvaluated:
      "Semantic content not evaluated"
    case .explicitSuggestionOnly:
      "Suggestion-only content"
    case .corroboratedLogicalEmpty:
      "Logically empty editor"
    case .knownApplicationSuggestion:
      "Known application suggestion"
    case .mixedSuggestionAndContent:
      "Mixed suggestion and authored content"
    case .logicalContentPresent:
      "Authored content present"
    case .markedTextActive:
      "Marked text active"
    case .evidenceUnavailable:
      "Semantic evidence unavailable"
    case .evidenceInconsistent:
      "Semantic evidence inconsistent"
    }
  }
}

extension FocusedTextSelectionRelation {
  fileprivate var displayName: String {
    switch self {
    case .emptyValue:
      "Empty value"
    case .caretAtStart:
      "Caret at start"
    case .caretAtEnd:
      "Caret at end"
    case .caretInMiddle:
      "Caret in middle"
    case .fullValue:
      "Full selection"
    case .partialSelection:
      "Partial selection"
    }
  }
}

extension FocusedTextAttributeDecision {
  fileprivate var displayName: String {
    switch self {
    case .notEvaluated:
      "Attributes not evaluated"
    case .eligibleFontOnly:
      "Font-only plain text"
    case .eligibleUniformPresentation:
      "Uniform presentation"
    case .rejectedUnavailableOrInconsistent:
      "Attributed value unavailable"
    case .rejectedMixedPresentation:
      "Mixed presentation"
    case .rejectedSemanticOrUnknownAttribute:
      "Semantic or unknown attribute"
    case .rejectedStyledFont:
      "Styled font"
    }
  }
}

extension UnsupportedCommandReason {
  fileprivate var displayName: String {
    switch self {
    case .ambiguousTarget:
      "Ambiguous target"
    case .applicationNotFound:
      "Application not found"
    case .compoundRequest:
      "Compound request"
    case .contextRequired:
      "Context required"
    case .dictationModeRequired:
      "Dictation shortcut required"
    case .emptyInput:
      "Empty input"
    case .missingValue:
      "Missing value"
    case .youTubeFeedRequired:
      "YouTube feed required"
    case .youTubeSelectionAmbiguous:
      "YouTube selection ambiguous"
    case .youTubeSelectionRequired:
      "YouTube selection required"
    case .uncertainDomain:
      "Uncertain spoken domain"
    case .unknownTarget:
      "Unknown target"
    case .unsupportedAction:
      "Unsupported target action"
    case .unsupportedPhrasing:
      "Unsupported phrasing"
    }
  }
}

extension DictationFailureReason {
  fileprivate var displayName: String {
    switch self {
    case .focusChanged:
      "Focus changed"
    case .mutationFailed:
      "Text mutation failed"
    case .mutationNotObserved:
      "Text mutation was not observed"
    case .mutationUnverified:
      "Text mutation could not be verified"
    case .noFocusedElement:
      "No focused field"
    case .noPreparedTarget:
      "Prepared field unavailable"
    case .selectionChanged:
      "Selection changed"
    case .tooLong:
      "Text exceeded insertion bound"
    case .unsupportedField:
      "Unsupported field"
    }
  }
}

extension DeveloperActionIssueReason {
  var displayName: String {
    switch self {
    case .duplicatedText:
      "Duplicated text"
    case .missingText:
      "Missing text"
    case .other:
      "Other"
    case .spacingOrPunctuation:
      "Spacing or punctuation"
    case .unremovedDisfluency:
      "Stutter or filler not cleaned"
    case .wrongDestination:
      "Wrong destination"
    case .wrongField:
      "Wrong field"
    case .wrongPosition:
      "Wrong position"
    }
  }
}

extension PushToTalkCaptureFailure {
  fileprivate var displayName: String {
    switch self {
    case .microphonePermissionRequired:
      "Microphone permission required"
    case .microphoneDenied:
      "Microphone denied"
    case .microphoneRestricted:
      "Microphone restricted"
    case .speechModelNotReady:
      "Speech model unavailable"
    case .speechAssetPreparationFailed:
      "Speech asset preparation failed"
    case .startFailed:
      "Capture start failed"
    case .resultStreamEnded:
      "Result stream ended"
    case .resultStreamFailed:
      "Result stream failed"
    case .finalizationFailed:
      "Finalization failed"
    case .finalizationTimedOut:
      "Finalization timed out"
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
