import Foundation
import KeyboardShortcuts
import OSLog
import TopherCore

@MainActor
final class TopherModel: ObservableObject {
  enum Phase: Equatable {
    case idle
    case listening
    case transcribing
    case executing
    case success(String)
    case failure(String)

    var title: String {
      switch self {
      case .idle:
        "Ready"
      case .listening:
        "Listening…"
      case .transcribing:
        "Transcribing…"
      case .executing:
        "Executing…"
      case .success:
        "Done"
      case .failure:
        "Couldn’t complete command"
      }
    }

    var detail: String {
      switch self {
      case .idle:
        "Hold your shortcut, then release to run the mock transcript."
      case .listening:
        "Release the shortcut to process the command."
      case .transcribing:
        "Using the manual transcript for this first slice."
      case .executing:
        "Running an approved native capability."
      case .success(let message), .failure(let message):
        message
      }
    }

    var symbolName: String {
      switch self {
      case .idle:
        "sparkles"
      case .listening:
        "waveform"
      case .transcribing:
        "text.bubble"
      case .executing:
        "gearshape.2"
      case .success:
        "checkmark.circle"
      case .failure:
        "exclamationmark.triangle"
      }
    }

    var isBusy: Bool {
      switch self {
      case .listening, .transcribing, .executing:
        true
      case .idle, .success, .failure:
        false
      }
    }
  }

  @Published var mockTranscript = "Open Safari."
  @Published private(set) var phase: Phase = .idle

  private let resolver: CommandResolver
  private let policy: CommandPolicy
  private let applicationOpener: ApplicationOpenCapability
  private let webOpener: WebOpenCapability
  private let logger = Logger(subsystem: "dev.topher.app", category: "control-path")
  private var shortcutEventsTask: Task<Void, Never>?
  private var listeningTimeoutTask: Task<Void, Never>?

  init(
    resolver: CommandResolver = .init(),
    policy: CommandPolicy = .init(),
    applicationOpener: ApplicationOpenCapability? = nil,
    webOpener: WebOpenCapability? = nil
  ) {
    self.resolver = resolver
    self.policy = policy
    self.applicationOpener = applicationOpener ?? ApplicationOpenCapability()
    self.webOpener = webOpener ?? WebOpenCapability()

    shortcutEventsTask = Task { [weak self] in
      for await event in KeyboardShortcuts.events(for: .pushToTalk) {
        guard let self else { return }

        switch event {
        case .keyDown:
          beginPushToTalk()
        case .keyUp:
          endPushToTalk()
        }
      }
    }
  }

  deinit {
    shortcutEventsTask?.cancel()
    listeningTimeoutTask?.cancel()
  }

  func beginPushToTalk() {
    guard !phase.isBusy else { return }
    phase = .listening
    logger.info("Push-to-talk started")

    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(30))
      } catch {
        return
      }

      guard let self, phase == .listening else { return }
      phase = .failure("Listening timed out. Try the shortcut again.")
      logger.notice("Push-to-talk timed out without a key-up event")
    }
  }

  func endPushToTalk() {
    guard phase == .listening else { return }
    listeningTimeoutTask?.cancel()
    listeningTimeoutTask = nil
    phase = .transcribing
    logger.info("Push-to-talk ended")
    queueMockTranscriptProcessing()
  }

  func runManually() {
    guard !phase.isBusy else { return }
    phase = .transcribing
    queueMockTranscriptProcessing()
  }

  private func queueMockTranscriptProcessing() {
    Task { [weak self] in
      await Task.yield()
      self?.processMockTranscript()
    }
  }

  private func processMockTranscript() {
    let command = resolver.resolve(mockTranscript)

    guard policy.evaluate(command) == .allowed else {
      phase = .failure(
        "Unsupported command. Try “Open Safari.” or “Search YouTube for local AI.”"
      )
      logger.notice("Rejected an unsupported command")
      return
    }

    switch command {
    case .openApplication(let target):
      phase = .executing
      logger.info(
        "Executing registered capability: \(ApplicationOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        let outcome = await applicationOpener.execute(target)
        apply(outcome)
      }
    case .openWebsite(let target):
      phase = .executing
      logger.info(
        "Executing registered capability: \(WebOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        await Task.yield()
        let outcome = await webOpener.execute(target)
        apply(outcome)
      }
    case .searchWeb(let provider, let query):
      phase = .executing
      logger.info(
        "Executing registered capability: \(WebOpenCapability.descriptor.identifier, privacy: .public)"
      )
      Task {
        await Task.yield()
        let outcome = await webOpener.execute(provider: provider, query: query)
        apply(outcome)
      }
    case .unsupported:
      phase = .failure("Unsupported command.")
    }
  }

  private func apply(_ outcome: ActionOutcome) {
    switch outcome {
    case .succeeded(let message):
      phase = .success(message)
      logger.info("Capability completed")
    case .failed(let message):
      phase = .failure(message)
      logger.error("Capability failed")
    }
  }
}
