import OSLog
import TopherCore

enum AssistantCommandOutcome: Equatable, Sendable {
  case unsupported(reason: UnsupportedCommandReason)
  case denied(reason: String)
  case completed(ActionOutcome)
}

enum AssistantCommandInputSource: Equatable, Sendable {
  case manual
  case voice
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
  private let chromeContext: ChromeContextCapabilities
  private let frontmostApplicationReader: FrontmostApplicationCapability
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
    chromeContext: ChromeContextCapabilities? = nil,
    frontmostApplicationReader: FrontmostApplicationCapability? = nil,
    webOpener: WebOpenCapability? = nil
  ) {
    self.resolver = resolver
    self.vocabularyProvider = vocabularyProvider
    self.policy = policy
    self.applicationOpener = applicationOpener ?? ApplicationOpenCapability()
    self.browserRouteOpener = browserRouteOpener ?? BrowserRouteOpenCapability()
    self.chromeContext = chromeContext ?? .unavailable()
    self.frontmostApplicationReader =
      frontmostApplicationReader ?? FrontmostApplicationCapability()
    self.webOpener = webOpener ?? WebOpenCapability()
  }

  func process(
    _ transcript: String,
    alternatives: [TranscriptHypothesis] = [],
    confidence: Double? = nil,
    inputSource: AssistantCommandInputSource = .manual,
    executionStarted: @MainActor () -> Void = {}
  ) async -> AssistantCommandProcessingResult {
    let interpretation = TranscriptInterpreter(
      resolver: resolver,
      vocabulary: vocabularyProvider()
    ).interpret(
      primary: TranscriptHypothesis(text: transcript, confidence: confidence),
      alternatives: alternatives,
      allowKnownDomainNarrowing: inputSource == .voice
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

    if inputSource == .voice,
      hasConflictingDomainEvidence(
        for: command,
        primaryTranscript: transcript,
        alternatives: alternatives
      )
    {
      let reason = UnsupportedCommandReason.uncertainDomain
      logger.notice("Rejected voice domain navigation with conflicting hypotheses")
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
    case .activateChromeTab(let query):
      logExecution(ChromeTabActivationCapability.descriptor)
      outcome = await chromeContext.activateTab.execute(query)
    case .identifyActiveChromeTab:
      logExecution(ChromeActiveTabCapability.descriptor)
      outcome = await chromeContext.activeTab.execute()
    case .listChromeTabs:
      logExecution(ChromeTabListCapability.descriptor)
      outcome = await chromeContext.listTabs.execute()
    case .identifyFrontmostApplication:
      logExecution(FrontmostApplicationCapability.descriptor)
      outcome = frontmostApplicationReader.execute()
    case .openApplication(let target):
      logExecution(ApplicationOpenCapability.descriptor)
      outcome = await applicationOpener.execute(target)
    case .openInstalledApplication(let target):
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
    case .searchUnknownDestination(let query):
      logExecution(WebOpenCapability.descriptor)
      outcome = await webOpener.searchUnknownDestination(query)
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

  private func hasConflictingDomainEvidence(
    for command: TopherCommand,
    primaryTranscript: String,
    alternatives: [TranscriptHypothesis]
  ) -> Bool {
    guard case .openDomain = command else { return false }

    let hypotheses = [TranscriptHypothesis(text: primaryTranscript)] + alternatives
    let hosts = Set(
      hypotheses.compactMap { hypothesis -> String? in
        guard case .resolved(let candidate) = resolver.resolve(hypothesis.text) else {
          return nil
        }
        switch candidate {
        case .openDomain(let domain):
          return domain.host
        case .openWebsite(let target):
          return target.canonicalHost
        case .activateChromeTab, .identifyActiveChromeTab, .identifyFrontmostApplication,
          .listChromeTabs, .openApplication, .openInstalledApplication, .openBrowserRoute,
          .searchWeb, .searchUnknownDestination:
          return nil
        }
      }
    )
    return hosts.count > 1
  }

  private func traceMetadata(
    for command: TopherCommand
  ) -> (kind: AssistantCommandKind, capabilityIdentifier: String) {
    switch command {
    case .activateChromeTab:
      (.activateChromeTab, ChromeTabActivationCapability.descriptor.identifier)
    case .identifyActiveChromeTab:
      (.identifyActiveChromeTab, ChromeActiveTabCapability.descriptor.identifier)
    case .listChromeTabs:
      (.listChromeTabs, ChromeTabListCapability.descriptor.identifier)
    case .identifyFrontmostApplication:
      (
        .identifyFrontmostApplication,
        FrontmostApplicationCapability.descriptor.identifier
      )
    case .openApplication:
      (.openApplication, ApplicationOpenCapability.descriptor.identifier)
    case .openInstalledApplication:
      (.openInstalledApplication, ApplicationOpenCapability.descriptor.identifier)
    case .openBrowserRoute:
      (.openBrowserRoute, BrowserRouteOpenCapability.descriptor.identifier)
    case .openDomain:
      (.openDomain, WebOpenCapability.descriptor.identifier)
    case .openWebsite:
      (.openWebsite, WebOpenCapability.descriptor.identifier)
    case .searchWeb:
      (.searchWeb, WebOpenCapability.descriptor.identifier)
    case .searchUnknownDestination:
      (.searchUnknownDestination, WebOpenCapability.descriptor.identifier)
    }
  }
}
