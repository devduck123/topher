import AppKit
import SwiftUI

struct VoiceFeedbackHUDPresenter: NSViewRepresentable {
  let phase: TopherModel.Phase

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.update(for: phase)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.update(for: phase)
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.hide()
  }

  @MainActor
  final class Coordinator {
    private let panel = VoiceFeedbackPanel()
    private var cachedTranscript = ""
    private var displayScreen: NSScreen?
    private var isVoicePhaseActive = false

    init() {
      configurePanel()
    }

    func update(for phase: TopherModel.Phase) {
      switch phase {
      case .listening(let transcript):
        if !isVoicePhaseActive {
          displayScreen = currentScreen()
        }
        cachedTranscript = transcript
        present(.listening(transcript: cachedTranscript))
      case .finalizingVoice:
        present(.transcribing(transcript: cachedTranscript))
      case .idle, .preparingVoice, .transcribing, .executing, .success, .failure:
        hide()
      }
    }

    func hide() {
      panel.orderOut(nil)
      cachedTranscript = ""
      displayScreen = nil
      isVoicePhaseActive = false
    }

    private func configurePanel() {
      panel.backgroundColor = .clear
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
      panel.hasShadow = true
      panel.hidesOnDeactivate = false
      panel.ignoresMouseEvents = true
      panel.isMovable = false
      panel.isOpaque = false
      panel.level = .statusBar
    }

    private func present(_ state: VoiceFeedbackHUDState) {
      isVoicePhaseActive = true
      panel.contentView = NSHostingView(
        rootView: VoiceFeedbackHUD(state: state)
          .frame(width: VoiceFeedbackHUDMetrics.width, height: VoiceFeedbackHUDMetrics.height)
      )
      positionPanel()

      if !panel.isVisible {
        panel.orderFrontRegardless()
      }
    }

    private func positionPanel() {
      guard let screen = displayScreen ?? currentScreen() else { return }

      let size = NSSize(
        width: VoiceFeedbackHUDMetrics.width, height: VoiceFeedbackHUDMetrics.height)
      let frame = NSRect(
        x: screen.visibleFrame.midX - (size.width / 2),
        y: screen.visibleFrame.minY + VoiceFeedbackHUDMetrics.bottomInset,
        width: size.width,
        height: size.height
      )
      panel.setFrame(frame, display: panel.isVisible)
    }

    private func currentScreen() -> NSScreen? {
      let mouseLocation = NSEvent.mouseLocation
      return
        NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        ?? NSScreen.main
        ?? NSScreen.screens.first
    }
  }
}

private final class VoiceFeedbackPanel: NSPanel {
  init() {
    super.init(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

private enum VoiceFeedbackHUDState: Equatable {
  case listening(transcript: String)
  case transcribing(transcript: String)

  var title: String {
    switch self {
    case .listening:
      "Listening"
    case .transcribing:
      "Finalizing"
    }
  }

  var transcript: String {
    switch self {
    case .listening(let transcript), .transcribing(let transcript):
      transcript
    }
  }

  var isListening: Bool {
    if case .listening = self { return true }
    return false
  }
}

private enum VoiceFeedbackHUDMetrics {
  static let width: CGFloat = 384
  static let height: CGFloat = 104
  static let bottomInset: CGFloat = 32
}

private struct VoiceFeedbackHUD: View {
  let state: VoiceFeedbackHUDState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        if state.isListening {
          VoiceWaveform()
        } else {
          ProgressView()
            .controlSize(.small)
            .frame(width: 38, height: 20)
        }

        Text(state.title)
          .font(.system(size: 13, weight: .semibold, design: .rounded))

        Spacer(minLength: 0)

        Text(state.isListening ? "Release to run" : "One moment")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(state.transcript.isEmpty ? "Speak now…" : state.transcript)
        .font(.system(size: 15, weight: .medium, design: .rounded))
        .foregroundStyle(state.transcript.isEmpty ? .secondary : .primary)
        .lineLimit(2)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(state.title)
    .accessibilityValue(state.transcript)
  }
}

private struct VoiceWaveform: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
      HStack(alignment: .center, spacing: 3) {
        ForEach(0..<7, id: \.self) { index in
          Capsule()
            .fill(.tint)
            .frame(width: 3, height: barHeight(index: index, date: timeline.date))
        }
      }
      .frame(width: 38, height: 20)
    }
  }

  private func barHeight(index: Int, date: Date) -> CGFloat {
    guard !reduceMotion else {
      return [7, 12, 17, 20, 17, 12, 7][index]
    }

    let time = date.timeIntervalSinceReferenceDate
    let wave = (sin((time * 6.5) + (Double(index) * 0.9)) + 1) / 2
    return 6 + (CGFloat(wave) * 14)
  }
}
