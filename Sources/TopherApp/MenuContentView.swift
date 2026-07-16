import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuContentView: View {
  @ObservedObject var model: TopherModel
  @ObservedObject var diagnostics: DeveloperDiagnosticsController
  @ObservedObject var vocabulary: SpeechVocabularyController
  @State private var isDictationShortcutConfigured =
    KeyboardShortcuts.getShortcut(for: .dictation) != nil
  @AppStorage(DictationPolishSettings.preferenceKey) private var isDictationPolishEnabled =
    DictationPolishSettings.defaultEnabled

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: model.phase.symbolName)
          .font(.title2)
          .symbolEffect(.pulse, isActive: model.phase.isListening)

        VStack(alignment: .leading, spacing: 2) {
          Text(model.phase.title)
            .font(.headline)
          Text(model.phase.detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      Divider()

      KeyboardShortcuts.Recorder(
        "Assistant command shortcut:",
        name: .pushToTalk
      )

      KeyboardShortcuts.Recorder(
        "Hold-to-dictate shortcut:",
        name: .dictation,
        onChange: { shortcut in
          isDictationShortcutConfigured = shortcut != nil
        }
      )

      if !isDictationShortcutConfigured {
        Label(
          "Dictation is not configured. Record a separate shortcut above to type into the focused field.",
          systemImage: "exclamationmark.triangle.fill"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      }

      Toggle("Clean repeated speech", isOn: $isDictationPolishEnabled)
        .font(.caption)
        .onChange(of: isDictationPolishEnabled) { _, enabled in
          model.setDictationPolishEnabled(enabled)
        }

      Text(
        "Fast local cleanup for clear stutters. Turn it off for presentation-only transcription; punctuation and grammar are not rewritten."
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Image(
          systemName: model.voiceReadiness == .ready
            ? "mic.circle.fill"
            : "mic.circle"
        )
        .foregroundStyle(model.voiceReadiness == .ready ? .green : .secondary)

        Text(model.voiceReadiness.title)
          .font(.caption)
          .foregroundStyle(.secondary)

        Spacer()

        if model.voiceReadiness.canPrepare {
          Button("Enable Voice") {
            model.prepareVoiceInput()
          }
          .controlSize(.small)
        } else if model.voiceReadiness.needsSettings {
          Button("Open Settings") {
            model.openMicrophoneSettings()
          }
          .controlSize(.small)
        }
      }

      HStack(spacing: 8) {
        Image(
          systemName: model.accessibilityPermissionState == .authorized
            ? "accessibility.fill"
            : "accessibility"
        )
        .foregroundStyle(
          model.accessibilityPermissionState == .authorized ? .green : .secondary
        )

        Text(
          model.accessibilityPermissionState == .authorized
            ? "Global text insertion ready"
            : "Accessibility required for dictation"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer()

        if model.accessibilityPermissionState == .notAuthorized {
          Button("Enable") {
            model.requestAccessibilityPermission()
          }
          .controlSize(.small)

          Button("Settings") {
            model.openAccessibilitySettings()
          }
          .controlSize(.small)
        }
      }

      if model.accessibilityPermissionState == .notAuthorized {
        Text(AccessibilityPermissionClient.recoveryInstructions)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      if let pendingDictationText = model.pendingDictationText {
        VStack(alignment: .leading, spacing: 6) {
          Text("Pending dictation")
            .font(.caption)
            .foregroundStyle(.secondary)

          Text(pendingDictationText)
            .font(.caption)
            .lineLimit(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

          HStack {
            Button("Copy") {
              model.copyPendingDictation()
            }
            .controlSize(.small)

            Button("Clear") {
              model.clearPendingDictation()
            }
            .controlSize(.small)

            Spacer()
          }
        }
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Manual transcript (development fallback)")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField("Open Safari or search YouTube…", text: $model.manualTranscript)
          .textFieldStyle(.roundedBorder)
          .onSubmit(model.runManually)
      }

      DeveloperDiagnosticsView(diagnostics: diagnostics)
      SpeechVocabularyView(vocabulary: vocabulary)

      HStack {
        Button("Run") {
          model.runManually()
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(model.phase.isBusy)

        if model.canUndoDictation {
          Button("Undo Dictation") {
            model.undoLastDictation()
          }
          .disabled(model.phase.isBusy)
        }

        Spacer()

        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 390)
    .onAppear {
      isDictationShortcutConfigured = KeyboardShortcuts.getShortcut(for: .dictation) != nil
      model.setDictationPolishEnabled(isDictationPolishEnabled)
      model.refreshVoiceReadiness()
      model.refreshAccessibilityPermission()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      model.refreshVoiceReadiness()
      model.refreshAccessibilityPermission()
    }
  }
}
