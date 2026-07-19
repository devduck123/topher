import AppKit
import OSLog
import SwiftUI
import TopherCore

@MainActor
private enum TopherRuntime {
  static let instanceLock = TopherSingleInstanceLock()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "dev.topher.app", category: "lifecycle")

  func applicationWillFinishLaunching(_ notification: Notification) {
    switch TopherRuntime.instanceLock.state {
    case .primary:
      return
    case .secondary:
      logger.notice("Exiting duplicate Topher process before shortcut registration")
    case .unavailable:
      logger.error("Exiting because the single-instance lock is unavailable")
    }
    NSApplication.shared.terminate(nil)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard TopherRuntime.instanceLock.isPrimary else { return }
    NSApplication.shared.setActivationPolicy(.accessory)
  }
}

@main
struct TopherApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var diagnostics: DeveloperDiagnosticsController
  @StateObject private var vocabulary: SpeechVocabularyController
  @StateObject private var model: TopherModel

  init() {
    let diagnostics = DeveloperDiagnosticsController()
    let vocabulary = SpeechVocabularyController()
    let installedApplications = InstalledApplicationCatalog.discover().applications
    let resolver = CommandResolver(installedApplications: installedApplications)
    let policy = CommandPolicy(installedApplications: installedApplications)
    let installedApplicationNames = installedApplications.map(\.displayName)
    _diagnostics = StateObject(wrappedValue: diagnostics)
    _vocabulary = StateObject(wrappedValue: vocabulary)
    _model = StateObject(
      wrappedValue: TopherModel(
        resolver: resolver,
        policy: policy,
        chromeContext: .live(),
        voiceTranscription: .live(contextualStrings: {
          Self.contextualStrings(
            personal: vocabulary.entries.map(\.canonicalTerm),
            installedApplications: installedApplicationNames,
            defaults: TranscriptVocabulary.developerDefaults.contextualStrings
          )
        }),
        developerDiagnostics: diagnostics,
        vocabularyProvider: { vocabulary.vocabulary },
        listenForShortcutEvents: TopherRuntime.instanceLock.isPrimary
      )
    )
  }

  private static func contextualStrings(
    personal: [String],
    installedApplications: [String],
    defaults: [String]
  ) -> [String] {
    var seen = Set<String>()
    return (personal + installedApplications + defaults)
      .filter {
        let key = $0.folding(
          options: [.caseInsensitive, .diacriticInsensitive],
          locale: .current
        )
        return !key.isEmpty && seen.insert(key).inserted
      }
      .prefix(TranscriptVocabulary.maximumContextualStringCount)
      .map { $0 }
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContentView(model: model, diagnostics: diagnostics, vocabulary: vocabulary)
    } label: {
      ZStack(alignment: .topTrailing) {
        Image(systemName: model.phase.symbolName)

        if diagnostics.isEnabled {
          Circle()
            .fill(.orange)
            .frame(width: 5, height: 5)
            .offset(x: 3, y: -2)
            .accessibilityHidden(true)
        }
      }
      .accessibilityLabel("Topher")
      .accessibilityValue(
        diagnostics.isEnabled
          ? "\(model.phase.title), transcript diagnostics on"
          : model.phase.title
      )
      .background {
        VoiceFeedbackHUDPresenter(feedback: model.voiceFeedback)
          .frame(width: 0, height: 0)
          .accessibilityHidden(true)
      }
    }
    .menuBarExtraStyle(.window)
  }
}
