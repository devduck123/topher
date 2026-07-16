import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuContentView: View {
  @ObservedObject var model: TopherModel
  @ObservedObject var diagnostics: DeveloperDiagnosticsController

  @State private var isAssistantShortcutConfigured =
    KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
  @State private var isDictationShortcutConfigured =
    KeyboardShortcuts.getShortcut(for: .dictation) != nil

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          phaseHeader

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
      .frame(maxHeight: 520)

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
    .frame(width: 380)
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

  private func refreshReadiness() {
    isAssistantShortcutConfigured = KeyboardShortcuts.getShortcut(for: .pushToTalk) != nil
    isDictationShortcutConfigured = KeyboardShortcuts.getShortcut(for: .dictation) != nil
    model.refreshVoiceReadiness()
    model.refreshAccessibilityPermission()
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
