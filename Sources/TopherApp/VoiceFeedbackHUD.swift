import AppKit
import SwiftUI

struct VoiceFeedbackHUDPresenter: NSViewRepresentable {
  let feedback: TopherModel.VoiceFeedback

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let view = NSView(frame: .zero)
    context.coordinator.update(for: feedback)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.update(for: feedback)
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.hide()
  }

  @MainActor
  final class Coordinator {
    private let panel = VoiceFeedbackPanel()
    private let hostingView = NSHostingView(
      rootView: VoiceFeedbackHUDRoot(state: .preparing(detail: ""))
    )
    private var displayScreen: NSScreen?
    private var isVoicePhaseActive = false

    init() {
      configurePanel()
    }

    func update(for feedback: TopherModel.VoiceFeedback) {
      switch feedback {
      case .hidden:
        hide()
      case .preparing(let detail):
        if !isVoicePhaseActive {
          displayScreen = currentScreen()
        }
        present(.preparing(detail: detail))
      case .listening(let transcript):
        if !isVoicePhaseActive {
          displayScreen = currentScreen()
        }
        present(.listening(transcript: transcript))
      case .finalizing(let transcript):
        present(.finalizing(transcript: transcript))
      case .executing(let transcript):
        present(.executing(transcript: transcript))
      case .success(let message):
        present(.success(message: message))
      case .failure(let message):
        present(.failure(message: message))
      case .dictationPreparing(let detail):
        if !isVoicePhaseActive {
          displayScreen = currentScreen()
        }
        present(.dictationPreparing(detail: detail))
      case .dictationListening(let transcript):
        if !isVoicePhaseActive {
          displayScreen = currentScreen()
        }
        present(.dictationListening(transcript: transcript))
      case .dictationFinalizing(let transcript):
        present(.dictationFinalizing(transcript: transcript))
      case .dictationInserting(let transcript):
        present(.dictationInserting(transcript: transcript))
      }
    }

    func hide() {
      panel.orderOut(nil)
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
      panel.contentView = hostingView
    }

    private func present(_ state: VoiceFeedbackHUDState) {
      isVoicePhaseActive = true
      hostingView.rootView = VoiceFeedbackHUDRoot(state: state)
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
  case preparing(detail: String)
  case listening(transcript: String)
  case finalizing(transcript: String)
  case executing(transcript: String)
  case success(message: String)
  case failure(message: String)
  case dictationPreparing(detail: String)
  case dictationListening(transcript: String)
  case dictationFinalizing(transcript: String)
  case dictationInserting(transcript: String)

  var title: String {
    switch self {
    case .preparing:
      "Preparing voice"
    case .listening:
      "Listening"
    case .finalizing:
      "Finalizing"
    case .executing:
      "Running command"
    case .success:
      "Done"
    case .failure:
      "Couldn’t complete command"
    case .dictationPreparing:
      "Preparing dictation"
    case .dictationListening:
      "Dictating"
    case .dictationFinalizing:
      "Finalizing dictation"
    case .dictationInserting:
      "Inserting text"
    }
  }

  var detail: String {
    switch self {
    case .preparing(let detail):
      detail
    case .listening(let transcript), .finalizing(let transcript), .executing(let transcript):
      transcript
    case .success(let message), .failure(let message):
      message
    case .dictationPreparing(let detail):
      detail
    case .dictationListening(let transcript), .dictationFinalizing(let transcript),
      .dictationInserting(let transcript):
      transcript
    }
  }

  var trailingText: String {
    switch self {
    case .preparing:
      "Wait to speak"
    case .listening:
      "Release to run"
    case .finalizing:
      "One moment"
    case .executing:
      "Working"
    case .success, .failure:
      ""
    case .dictationPreparing:
      "Wait to speak"
    case .dictationListening:
      "Release to insert"
    case .dictationFinalizing:
      "One moment"
    case .dictationInserting:
      "Working"
    }
  }

  var symbolName: String? {
    switch self {
    case .preparing, .finalizing, .executing, .listening, .dictationPreparing,
      .dictationListening, .dictationFinalizing, .dictationInserting:
      nil
    case .success:
      "checkmark.circle.fill"
    case .failure:
      "exclamationmark.triangle.fill"
    }
  }

  var symbolColor: Color {
    switch self {
    case .success:
      .green
    case .failure:
      .orange
    case .preparing, .listening, .finalizing, .executing, .dictationPreparing,
      .dictationListening, .dictationFinalizing, .dictationInserting:
      .accentColor
    }
  }
}

private enum VoiceFeedbackHUDMetrics {
  static let width: CGFloat = 384
  static let height: CGFloat = 104
  static let bottomInset: CGFloat = 32
}

private struct VoiceFeedbackHUDRoot: View {
  let state: VoiceFeedbackHUDState

  var body: some View {
    VoiceFeedbackHUD(state: state)
      .frame(width: VoiceFeedbackHUDMetrics.width, height: VoiceFeedbackHUDMetrics.height)
  }
}

private struct VoiceFeedbackHUD: View {
  let state: VoiceFeedbackHUDState

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        switch state {
        case .listening, .dictationListening:
          VoiceWaveform()
        case .preparing, .finalizing, .executing, .dictationPreparing,
          .dictationFinalizing, .dictationInserting:
          ProgressView()
            .controlSize(.small)
            .frame(width: 38, height: 20)
        case .success, .failure:
          if let symbolName = state.symbolName {
            Image(systemName: symbolName)
              .font(.system(size: 18, weight: .semibold))
              .foregroundStyle(state.symbolColor)
              .frame(width: 38, height: 20)
          }
        }

        Text(state.title)
          .font(.system(size: 13, weight: .semibold, design: .rounded))

        Spacer(minLength: 0)

        if !state.trailingText.isEmpty {
          Text(state.trailingText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Text(detailText)
        .font(.system(size: 15, weight: .medium, design: .rounded))
        .foregroundStyle(state.detail.isEmpty ? .secondary : .primary)
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
    .accessibilityValue(detailText)
  }

  private var detailText: String {
    if case .listening = state, state.detail.isEmpty {
      return "Speak now…"
    }
    return state.detail
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
