import KeyboardShortcuts
import SwiftUI

struct TopherSettingsView: View {
  @ObservedObject var model: TopherModel
  @ObservedObject var diagnostics: DeveloperDiagnosticsController
  @ObservedObject var vocabulary: SpeechVocabularyController

  @State private var selection: TopherSettingsSection? = .general

  var body: some View {
    NavigationSplitView {
      List(TopherSettingsSection.allCases, selection: $selection) { section in
        Label(section.title, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationTitle("Topher")
      .navigationSplitViewColumnWidth(min: 170, ideal: 185, max: 210)
    } detail: {
      settingsPage(selection ?? .general)
    }
    .frame(minWidth: 760, minHeight: 540)
    .onAppear(perform: refreshReadiness)
  }

  @ViewBuilder
  private func settingsPage(_ section: TopherSettingsSection) -> some View {
    switch section {
    case .general:
      GeneralSettingsView(model: model)
    case .personalization:
      PersonalizationSettingsView(vocabulary: vocabulary)
    case .developer:
      DeveloperSettingsView(model: model, diagnostics: diagnostics)
    }
  }

  private func refreshReadiness() {
    model.refreshVoiceReadiness()
    model.refreshAccessibilityPermission()
  }
}

private enum TopherSettingsSection: String, CaseIterable, Identifiable {
  case general
  case personalization
  case developer

  var id: Self { self }

  var title: String {
    switch self {
    case .general:
      "General"
    case .personalization:
      "Personalization"
    case .developer:
      "Developer"
    }
  }

  var systemImage: String {
    switch self {
    case .general:
      "slider.horizontal.3"
    case .personalization:
      "text.book.closed"
    case .developer:
      "ladybug"
    }
  }
}

private struct GeneralSettingsView: View {
  @ObservedObject var model: TopherModel
  @AppStorage(DictationPolishSettings.preferenceKey) private var isDictationPolishEnabled =
    DictationPolishSettings.defaultEnabled

  var body: some View {
    SettingsPage(
      title: "General",
      subtitle: "Configure how you reach Topher and verify the permissions each mode needs."
    ) {
      SettingsCard(title: "Shortcuts", systemImage: "keyboard") {
        VStack(spacing: 0) {
          SettingsShortcutRow(
            title: "Assistant commands",
            detail: "Hold to run supported app and web requests.",
            name: .pushToTalk
          )

          Divider()

          SettingsShortcutRow(
            title: "Focused-field dictation",
            detail: "Hold to insert text without submitting or pressing Return.",
            name: .dictation
          )
        }
      }

      SettingsCard(title: "Permissions and readiness", systemImage: "checkmark.shield") {
        VStack(spacing: 0) {
          SettingsPermissionRow(
            title: "On-device voice input",
            detail: model.voiceReadiness.title,
            systemImage: model.voiceReadiness == .ready ? "mic.fill" : "mic",
            tint: voiceReadinessTint
          ) {
            if model.voiceReadiness.canPrepare {
              Button("Set Up") {
                model.prepareVoiceInput()
              }
            } else if model.voiceReadiness.needsSettings {
              Button("Open Microphone Settings") {
                model.openMicrophoneSettings()
              }
            }
          }

          Divider()

          SettingsPermissionRow(
            title: "Focused-field text insertion",
            detail: model.accessibilityPermissionState == .authorized
              ? "Accessibility access is ready."
              : "Accessibility is required only for dictation insertion.",
            systemImage: "accessibility",
            tint: model.accessibilityPermissionState == .authorized ? .green : .orange
          ) {
            if model.accessibilityPermissionState == .notAuthorized {
              HStack {
                Button("Enable") {
                  model.requestAccessibilityPermission()
                }
                Button("Open Settings") {
                  model.openAccessibilitySettings()
                }
              }
            }
          }

          if model.accessibilityPermissionState == .notAuthorized {
            Text(AccessibilityPermissionClient.recoveryInstructions)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
              .padding(.top, 6)
              .padding(.leading, 40)
          }
        }
      }

      SettingsCard(title: "App behavior", systemImage: "menubar.rectangle") {
        VStack(spacing: 0) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "waveform.badge.mic")
              .font(.title3)
              .foregroundStyle(.tint)
              .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
              Toggle("Clean repeated speech", isOn: $isDictationPolishEnabled)
                .font(.subheadline.weight(.semibold))
                .onChange(of: isDictationPolishEnabled) { _, enabled in
                  model.setDictationPolishEnabled(enabled)
                }
              Text(
                "Fast local cleanup removes clear adjacent restarts. Turn it off for presentation-only transcription; punctuation and grammar are not rewritten."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.bottom, 14)

          Divider()

          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "menubar.rectangle")
              .font(.title3)
              .foregroundStyle(.tint)
              .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
              Text("Menu-bar first")
                .font(.subheadline.weight(.semibold))
              Text(
                "Topher stays available from the menu bar and intentionally remains out of the Dock. Its shortcuts continue working while another app is focused."
              )
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
            }
          }
          .padding(.top, 14)
        }
      }
    }
    .onAppear {
      model.setDictationPolishEnabled(isDictationPolishEnabled)
    }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      model.refreshVoiceReadiness()
      model.refreshAccessibilityPermission()
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
}

private struct PersonalizationSettingsView: View {
  @ObservedObject var vocabulary: SpeechVocabularyController

  var body: some View {
    SettingsPage(
      title: "Personalization",
      subtitle: "Teach on-device recognition the names and developer terms that matter to you."
    ) {
      SettingsCard(title: "Personal vocabulary", systemImage: "text.book.closed") {
        SpeechVocabularyEditor(vocabulary: vocabulary)
      }
    }
  }
}

private struct DeveloperSettingsView: View {
  @ObservedObject var model: TopherModel
  @ObservedObject var diagnostics: DeveloperDiagnosticsController

  var body: some View {
    SettingsPage(
      title: "Developer",
      subtitle: "Exercise the command pipeline and inspect the bounded local dogfood trace."
    ) {
      SettingsCard(title: "Manual command", systemImage: "terminal") {
        VStack(alignment: .leading, spacing: 10) {
          Text(
            "Type a command to run through the same deterministic resolver, policy, and capability path as assistant speech."
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          TextField("Open Safari or search YouTube…", text: $model.manualTranscript)
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              if model.canRunManualCommand {
                model.runManually()
              }
            }

          HStack {
            Button("Run Command") {
              model.runManually()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canRunManualCommand)

            if model.canUndoDictation {
              Button("Undo Last Dictation") {
                model.undoLastDictation()
              }
              .disabled(model.phase.isBusy)
            }

            Spacer()
          }
        }
      }

      SettingsCard(title: "Local diagnostics", systemImage: "ladybug") {
        DeveloperDiagnosticsView(diagnostics: diagnostics, startsExpanded: true)
      }
    }
  }
}

private struct SettingsPage<Content: View>: View {
  let title: String
  let subtitle: String
  @ViewBuilder let content: Content

  init(
    title: String,
    subtitle: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    ScrollView {
      HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 4) {
            Text(title)
              .font(.largeTitle.weight(.semibold))
            Text(subtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          content
        }
        .frame(maxWidth: 680, alignment: .leading)

        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(28)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .navigationTitle(title)
  }
}

private struct SettingsCard<Content: View>: View {
  let title: String
  let systemImage: String
  @ViewBuilder let content: Content

  init(
    title: String,
    systemImage: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.systemImage = systemImage
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label(title, systemImage: systemImage)
        .font(.headline)

      Divider()

      content
    }
    .padding(16)
    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(Color.primary.opacity(0.07))
    }
  }
}

private struct SettingsShortcutRow: View {
  let title: String
  let detail: String
  let name: KeyboardShortcuts.Name

  var body: some View {
    HStack(spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      KeyboardShortcuts.Recorder("\(title) shortcut", name: name)
        .labelsHidden()
    }
    .padding(.vertical, 8)
  }
}

private struct SettingsPermissionRow<Action: View>: View {
  let title: String
  let detail: String
  let systemImage: String
  let tint: Color
  @ViewBuilder let action: Action

  init(
    title: String,
    detail: String,
    systemImage: String,
    tint: Color,
    @ViewBuilder action: () -> Action
  ) {
    self.title = title
    self.detail = detail
    self.systemImage = systemImage
    self.tint = tint
    self.action = action()
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 30, height: 30)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 3) {
        Text(title)
          .font(.subheadline.weight(.semibold))
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 12)

      action
    }
    .padding(.vertical, 8)
  }
}
