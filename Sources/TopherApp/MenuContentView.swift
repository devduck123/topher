import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuContentView: View {
  @ObservedObject var model: TopherModel

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: model.phase.symbolName)
          .font(.title2)
          .symbolEffect(.pulse, isActive: model.phase == .listening)

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
        "Push to talk:",
        name: .pushToTalk
      )

      VStack(alignment: .leading, spacing: 6) {
        Text("Mock transcript")
          .font(.caption)
          .foregroundStyle(.secondary)

        TextField("Open Safari or search YouTube…", text: $model.mockTranscript)
          .textFieldStyle(.roundedBorder)
          .onSubmit(model.runManually)
      }

      HStack {
        Text("Hold to simulate")
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { _ in model.beginPushToTalk() }
              .onEnded { _ in model.endPushToTalk() }
          )

        Button("Run") {
          model.runManually()
        }
        .keyboardShortcut(.return, modifiers: [])

        Spacer()

        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 360)
  }
}
