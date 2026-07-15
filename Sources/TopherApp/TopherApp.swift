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
    MenuBarExtra("Topher", systemImage: model.phase.symbolName) {
      MenuContentView(model: model)
    }
    .menuBarExtraStyle(.window)
  }
}
