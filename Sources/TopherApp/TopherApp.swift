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
  @StateObject private var model = TopherModel()

  var body: some Scene {
    MenuBarExtra {
      MenuContentView(model: model)
    } label: {
      Image(systemName: model.phase.symbolName)
        .accessibilityLabel("Topher")
        .background {
          VoiceFeedbackHUDPresenter(feedback: model.voiceFeedback)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }
    .menuBarExtraStyle(.window)
  }
}
