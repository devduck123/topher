import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuContentView: View {
  @ObservedObject var model: TopherModel
  @ObservedObject var diagnostics: DeveloperDiagnosticsController

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

      VStack(alignment: .leading, spacing: 6) {
        Text("Manual transcript (development fallback)")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField("Open Safari or search YouTube…", text: $model.manualTranscript)
          .textFieldStyle(.roundedBorder)
          .onSubmit(model.runManually)
      }

      DeveloperDiagnosticsView(diagnostics: diagnostics)

      HStack {
        Button("Run") {
          model.runManually()
        }
        .keyboardShortcut(.return, modifiers: [])
        .disabled(model.phase.isBusy)

        Spacer()

        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 360)
    .onAppear {
      model.refreshVoiceReadiness()
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in
      model.refreshVoiceReadiness()
    }
  }
}
