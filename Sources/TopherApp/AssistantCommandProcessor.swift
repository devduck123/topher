import OSLog
import TopherCore

enum AssistantCommandOutcome: Equatable, Sendable {
  case unsupported(reason: UnsupportedCommandReason)
  case denied(reason: String)
  case completed(ActionOutcome)
}

struct AssistantCommandProcessingResult: Equatable, Sendable {
  let outcome: AssistantCommandOutcome
  let trace: AssistantCommandTrace
  let interpretation: TranscriptInterpretation
}

/// Owns the deterministic transcript-to-capability path.
///
/// The processor does not create unstructured tasks. Once resolution and policy
/// allow a command, it awaits exactly one registered capability and returns its
/// typed outcome to the caller.
@MainActor
final class AssistantCommandProcessor {
  private let resolver: CommandResolver
  private let vocabularyProvider: @MainActor () -> TranscriptVocabulary
  private let policy: CommandPolicy
  private let applicationOpener: ApplicationOpenCapability
  private let browserRouteOpener: BrowserRouteOpenCapability
  private let webOpener: WebOpenCapability
  private let logger = Logger(subsystem: "dev.topher.app", category: "control-path")

  init(
    resolver: CommandResolver = .init(),
    vocabularyProvider: @escaping @MainActor () -> TranscriptVocabulary = {
      .developerDefaults
    },
    policy: CommandPolicy = .init(),
    applicationOpener: ApplicationOpenCapability? = nil,
    browserRouteOpener: BrowserRouteOpenCapability? = nil,
    webOpener: WebOpenCapability? = nil
  ) {
    self.resolver = resolver
    self.vocabularyProvider = vocabularyProvider
    self.policy = policy
    self.applicationOpener = applicationOpener ?? ApplicationOpenCapability()
    self.browserRouteOpener = browserRouteOpener ?? BrowserRouteOpenCapability()
    self.webOpener = webOpener ?? WebOpenCapability()
  }

  func process(
    _ transcript: String,
    alternatives: [TranscriptHypothesis] = [],
    confidence: Double? = nil,
    executionStarted: @MainActor () -> Void = {}
  ) async -> AssistantCommandProcessingResult {
    let interpretation = TranscriptInterpreter(
      resolver: resolver,
      vocabulary: vocabularyProvider()
    ).interpret(
      primary: TranscriptHypothesis(text: transcript, confidence: confidence),
      alternatives: alternatives
    )

    let resolution = resolver.resolve(interpretation.selectedTranscript)
    guard case .resolved(let command) = resolution else {
      let reason =
        if case .unsupported(let unsupportedReason) = resolution {
          unsupportedReason
        } else {
          UnsupportedCommandReason.unsupportedPhrasing
        }
      logger.notice("Rejected an unsupported command")
      return AssistantCommandProcessingResult(
        outcome: .unsupported(reason: reason),
        trace: AssistantCommandTrace(
          outcome: .unsupported,
          commandKind: nil,
          capabilityIdentifier: nil,
          unsupportedReason: reason
        ),
        interpretation: interpretation
      )
    }

    let commandMetadata = traceMetadata(for: command)

    switch policy.evaluate(command) {
    case .allowed:
      break
    case .denied(let reason):
      logger.notice("Command policy denied a registered command")
      return AssistantCommandProcessingResult(
        outcome: .denied(reason: reason),
        trace: AssistantCommandTrace(
          outcome: .policyDenied,
          commandKind: commandMetadata.kind,
          capabilityIdentifier: commandMetadata.capabilityIdentifier
        ),
        interpretation: interpretation
      )
    }

    executionStarted()

    let outcome: ActionOutcome
    switch command {
    case .openApplication(let target):
      logExecution(ApplicationOpenCapability.descriptor)
      outcome = await applicationOpener.execute(target)
    case .openBrowserRoute(let target):
      logExecution(BrowserRouteOpenCapability.descriptor)
      outcome = await browserRouteOpener.execute(target)
    case .openDomain(let domain):
      logExecution(WebOpenCapability.descriptor)
      outcome = await webOpener.execute(domain)
    case .openWebsite(let target):
      logExecution(WebOpenCapability.descriptor)
      outcome = await webOpener.execute(target)
    case .searchWeb(let provider, let query):
      logExecution(WebOpenCapability.descriptor)
      outcome = await webOpener.execute(provider: provider, query: query)
    }

    switch outcome {
    case .succeeded:
      logger.info("Capability completed")
    case .failed:
      logger.error("Capability failed")
    }

    let traceOutcome =
      switch outcome {
      case .succeeded:
        AssistantCommandTraceOutcome.capabilitySucceeded
      case .failed:
        AssistantCommandTraceOutcome.capabilityFailed
      }

    return AssistantCommandProcessingResult(
      outcome: .completed(outcome),
      trace: AssistantCommandTrace(
        outcome: traceOutcome,
        commandKind: commandMetadata.kind,
        capabilityIdentifier: commandMetadata.capabilityIdentifier
      ),
      interpretation: interpretation
    )
  }

  private func logExecution(_ descriptor: CapabilityDescriptor) {
    logger.info(
      "Executing registered capability: \(descriptor.identifier, privacy: .public)"
    )
  }

  private func traceMetadata(
    for command: TopherCommand
  ) -> (kind: AssistantCommandKind, capabilityIdentifier: String) {
    switch command {
    case .openApplication:
      (.openApplication, ApplicationOpenCapability.descriptor.identifier)
    case .openBrowserRoute:
      (.openBrowserRoute, BrowserRouteOpenCapability.descriptor.identifier)
    case .openDomain:
      (.openDomain, WebOpenCapability.descriptor.identifier)
    case .openWebsite:
      (.openWebsite, WebOpenCapability.descriptor.identifier)
    case .searchWeb:
      (.searchWeb, WebOpenCapability.descriptor.identifier)
    }
  }
}
