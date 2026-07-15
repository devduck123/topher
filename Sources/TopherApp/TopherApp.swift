import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.setActivationPolicy(.accessory)
  }
}

@main
struct TopherApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var diagnostics: DeveloperDiagnosticsController
  @StateObject private var model: TopherModel

  init() {
    let diagnostics = DeveloperDiagnosticsController()
    _diagnostics = StateObject(wrappedValue: diagnostics)
    _model = StateObject(
      wrappedValue: TopherModel(developerDiagnostics: diagnostics)
    )
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContentView(model: model, diagnostics: diagnostics)
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
