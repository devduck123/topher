import AppKit
import KeyboardShortcuts
import SwiftUI
import TopherCore

struct MenuContentView: View {
  static let panelSize = CGSize(width: 380, height: 460)

  @ObservedObject var model: TopherModel
  @ObservedObject var diagnostics: DeveloperDiagnosticsController

  @Environment(\.openSettings) private var openSettings

  @State private var isAssistantShortcutConfigured =
    KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
  @State private var isDictationShortcutConfigured =
    KeyboardShortcuts.getShortcut(for: .dictation) != nil

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          phaseHeader

          if let youTubeFeedSnapshot = model.youTubeFeedSnapshot {
            YouTubeFeedResultsCard(
              snapshot: youTubeFeedSnapshot,
              clear: model.clearYouTubeFeedResults,
              open: model.openYouTubeFeedItem
            )
            .disabled(model.phase.isBusy)
          }

          if !diagnostics.latestRecords.isEmpty {
            MenuRecentActivityView(
              diagnostics: diagnostics,
              viewAll: openDeveloperSettings
            )
          }

          VStack(spacing: 8) {
            ShortcutModeRow(
              title: "Assistant",
              subtitle: "Commands, apps, and web actions",
              systemImage: "sparkles",
              shortcutName: .pushToTalk,
              isConfigured: isAssistantShortcutConfigured,
              onChange: { isAssistantShortcutConfigured = $0 != nil }
            )

            ShortcutModeRow(
              title: "Dictation",
              subtitle: "Type into the focused text field",
              systemImage: "text.cursor",
              shortcutName: .dictation,
              isConfigured: isDictationShortcutConfigured,
              onChange: { isDictationShortcutConfigured = $0 != nil }
            )
          }

          readinessCard

          if let pendingDictationText = model.pendingDictationText {
            PendingDictationCard(
              text: pendingDictationText,
              copy: model.copyPendingDictation,
              clear: model.clearPendingDictation
            )
          }

          if model.canUndoDictation {
            Button {
              model.undoLastDictation()
            } label: {
              Label("Undo last dictation", systemImage: "arrow.uturn.backward")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(model.phase.isBusy)
          }
        }
        .padding(16)
      }
      .scrollIndicators(.hidden)
      .frame(maxHeight: .infinity)

      Divider()

      HStack(spacing: 12) {
        SettingsLink {
          Label("Settings", systemImage: "gearshape")
        }
        .buttonStyle(.plain)

        if diagnostics.isEnabled {
          Label("Diagnostics on", systemImage: "record.circle")
            .font(.caption)
            .foregroundStyle(.orange)
            .help("Final commands and non-secure dictation are retained locally for dogfooding.")
        }

        Spacer()

        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
      }
      .font(.caption)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .frame(width: Self.panelSize.width, height: Self.panelSize.height)
    .onAppear(perform: refreshReadiness)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      refreshReadiness()
    }
  }

  private var phaseHeader: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle()
          .fill(phaseTint.opacity(0.14))
        Image(systemName: model.phase.symbolName)
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(phaseTint)
          .symbolEffect(.pulse, isActive: model.phase.isListening)
      }
      .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 3) {
        Text(model.phase.title)
          .font(.headline)
        Text(model.phase.detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .lineLimit(3)
      }

      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(model.phase.title)
    .accessibilityValue(model.phase.detail)
  }

  private var readinessCard: some View {
    VStack(spacing: 0) {
      readinessRow(
        title: model.voiceReadiness.title,
        systemImage: model.voiceReadiness == .ready ? "mic.fill" : "mic",
        tint: voiceReadinessTint
      ) {
        if model.voiceReadiness.canPrepare {
          Button("Set Up") {
            model.prepareVoiceInput()
          }
          .controlSize(.small)
        } else if model.voiceReadiness.needsSettings {
          Button("Microphone Settings") {
            model.openMicrophoneSettings()
          }
          .controlSize(.small)
        }
      }

      Divider()
        .padding(.leading, 42)

      readinessRow(
        title: model.chromeIntegrationReadiness == .ready
          ? model.chromeExtensionReadiness.title
          : model.chromeIntegrationReadiness.title,
        systemImage: model.chromeIntegrationReadiness == .ready
          && model.chromeExtensionReadiness == .ready
          ? "checkmark.circle.fill"
          : "puzzlepiece.extension",
        tint: chromeIntegrationTint
      ) {
        if model.chromeIntegrationReadiness.canConfigure {
          Button(model.chromeIntegrationReadiness == .needsRepair ? "Repair" : "Set Up") {
            model.configureChromeIntegration()
          }
          .controlSize(.small)
        }
      }

      Divider()
        .padding(.leading, 42)

      readinessRow(
        title: model.accessibilityPermissionState == .authorized
          ? "Global text insertion ready"
          : "Accessibility required for dictation",
        systemImage: "accessibility",
        tint: model.accessibilityPermissionState == .authorized ? .green : .orange
      ) {
        if model.accessibilityPermissionState == .notAuthorized {
          HStack(spacing: 6) {
            Button("Enable") {
              model.requestAccessibilityPermission()
            }
            .controlSize(.small)

            Button {
              model.openAccessibilitySettings()
            } label: {
              Image(systemName: "gearshape")
            }
            .controlSize(.small)
            .help("Open Accessibility Settings")
            .accessibilityLabel("Open Accessibility Settings")
          }
        }
      }

      if model.accessibilityPermissionState == .notAuthorized {
        Divider()
          .padding(.leading, 42)

        Text(AccessibilityPermissionClient.recoveryInstructions)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 10)
          .padding(.vertical, 9)
      }
    }
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
  }

  private func readinessRow<Action: View>(
    title: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder action: () -> Action
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 22, height: 22)
        .background(tint.opacity(0.12), in: Circle())

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)

      Spacer(minLength: 8)

      action()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
  }

  private var phaseTint: Color {
    switch model.phase {
    case .idle:
      .accentColor
    case .preparingVoice, .listening, .finalizingVoice, .transcribing, .executing:
      .blue
    case .success:
      .green
    case .failure:
      .orange
    }
  }

  private var voiceReadinessTint: Color {
    switch model.voiceReadiness {
    case .ready:
      .green
    case .checking, .preparing:
      .blue
    case .needsPermission, .needsAssets, .denied, .restricted:
      .orange
    case .unavailable:
      .red
    }
  }

  private var chromeIntegrationTint: Color {
    switch model.chromeIntegrationReadiness {
    case .ready:
      switch model.chromeExtensionReadiness {
      case .ready:
        .green
      case .checking:
        .blue
      case .youtubeAccessRequired:
        .orange
      case .disconnected, .unavailable:
        .red
      }
    case .needsRegistration, .needsRepair:
      .orange
    case .blocked, .unavailable:
      .red
    }
  }

  private func refreshReadiness() {
    isAssistantShortcutConfigured = KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
    isDictationShortcutConfigured = KeyboardShortcuts.getShortcut(for: .dictation) != nil
    model.refreshVoiceReadiness()
    model.refreshAccessibilityPermission()
    model.refreshChromeIntegrationReadiness()
  }

  private func openDeveloperSettings() {
    UserDefaults.standard.set(
      TopherSettingsSection.developer.rawValue,
      forKey: TopherSettingsSection.preferenceKey
    )
    openSettings()
  }
}

private struct YouTubeFeedResultsCard: View {
  let snapshot: YouTubeFeedSnapshot
  let clear: () -> Void
  let open: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Label("YouTube feed", systemImage: "play.rectangle.fill")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.red)

        Spacer()

        Button("Clear", action: clear)
          .buttonStyle(.plain)
          .font(.caption2)
          .foregroundStyle(Color.accentColor)
          .accessibilityLabel("Clear YouTube feed results")
      }

      ForEach(snapshot.items, id: \.observationID.value) { item in
        Button {
          open(item.position)
        } label: {
          HStack(alignment: .top, spacing: 9) {
            Text("\(item.position)")
              .font(.caption.monospacedDigit().weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
              Text(item.title)
                .font(.caption.weight(.medium))
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
              Text(item.channel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right.square")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .accessibilityHidden(true)
          }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(item.position). \(item.title), by \(item.channel)")
      }

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(
          systemName: snapshot.presentationWasTruncated
            ? "rectangle.stack.badge.minus"
            : "clock"
        )
        .accessibilityHidden(true)
        Text(
          youTubeFollowUpHint
        )
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.red.opacity(0.16))
    }
    .accessibilityElement(children: .contain)
  }

  private var youTubeFollowUpHint: String {
    if !snapshot.titleObservationWasComplete {
      return
        "Bounded view. Use a shown number within 90 seconds; title uniqueness was not complete."
    }
    if snapshot.presentationWasTruncated {
      return "Bounded view. Within 90 seconds, say a shown number or one unique exact title."
    }
    return "Within 90 seconds, say “the third one,” “number three,” or one exact title."
  }
}

private struct MenuRecentActivityView: View {
  @ObservedObject var diagnostics: DeveloperDiagnosticsController
  let viewAll: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Recent activity", systemImage: "clock.arrow.circlepath")
          .font(.caption.weight(.semibold))

        Spacer()

        Button("View all", action: viewAll)
          .buttonStyle(.plain)
          .font(.caption2)
          .foregroundStyle(Color.accentColor)
      }

      ForEach(diagnostics.latestRecords) { record in
        MenuRecentActivityRow(record: record, diagnostics: diagnostics)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
  }
}

private struct MenuRecentActivityRow: View {
  let record: DeveloperTranscriptRecord
  @ObservedObject var diagnostics: DeveloperDiagnosticsController

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(record.transcript.isEmpty ? "(No usable speech)" : record.transcript)
          .font(.caption)
          .lineLimit(2)
          .help(record.transcript)

        Spacer(minLength: 4)

        Text(record.outcome.displayName)
          .font(.caption2.weight(.medium))
          .foregroundStyle(outcomeTint)
      }

      HStack(spacing: 10) {
        if record.source == .voice || record.source == .dictation {
          feedbackControl(
            label: "Transcript",
            value: record.transcriptWasAccurate,
            dimension: .transcriptAccuracy
          )
        }

        feedbackControl(
          label: record.source == .dictation ? "Insertion" : "Action",
          value: record.actionWasCorrect,
          dimension: .actionCorrectness
        )

        if record.actionWasCorrect == false {
          issueMenu
        }

        Spacer(minLength: 0)

        Text(record.recordedAt, style: .time)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .contain)
  }

  private func feedbackControl(
    label: String,
    value: Bool?,
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
        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
    }
    .buttonStyle(.plain)
    .disabled(diagnostics.isUpdating)
    .accessibilityLabel(accessibilityLabel)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
  }

  private var issueMenu: some View {
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
    } label: {
      Image(systemName: record.actionIssueReason == nil ? "tag" : "tag.fill")
        .font(.caption2)
    }
    .menuStyle(.borderlessButton)
    .disabled(diagnostics.isUpdating)
    .accessibilityLabel("Incorrect action reason")
  }

  private var outcomeTint: Color {
    switch record.outcome {
    case .capabilitySucceeded, .dictationInserted:
      .green
    case .dictationFallback, .unsupported, .policyDenied, .noUsableSpeech:
      .orange
    case .captureFailed, .capabilityFailed, .dictationFailed:
      .red
    }
  }
}

private struct ShortcutModeRow: View {
  let title: String
  let subtitle: String
  let systemImage: String
  let shortcutName: KeyboardShortcuts.Name
  let isConfigured: Bool
  let onChange: (KeyboardShortcuts.Shortcut?) -> Void

  var body: some View {
    HStack(spacing: 11) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(isConfigured ? Color.accentColor : Color.orange)
        .frame(width: 30, height: 30)
        .background(
          (isConfigured ? Color.accentColor : Color.orange).opacity(0.11),
          in: RoundedRectangle(cornerRadius: 8)
        )

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(isConfigured ? subtitle : "Choose a shortcut to enable")
          .font(.caption2)
          .foregroundStyle(isConfigured ? Color.secondary : Color.orange)
      }

      Spacer(minLength: 6)

      KeyboardShortcuts.Recorder(
        "\(title) shortcut",
        name: shortcutName,
        onChange: onChange
      )
      .labelsHidden()
    }
    .padding(11)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    .accessibilityElement(children: .contain)
  }
}

private struct PendingDictationCard: View {
  let text: String
  let copy: () -> Void
  let clear: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("Dictation needs your review", systemImage: "doc.text.magnifyingglass")
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)

      Text(text)
        .font(.caption)
        .lineLimit(4)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack {
        Button("Copy", action: copy)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
        Button("Clear", action: clear)
          .controlSize(.small)
        Spacer()
      }
    }
    .padding(12)
    .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.orange.opacity(0.22))
    }
  }
}
