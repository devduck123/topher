import Foundation

public struct TranscriptHypothesis: Equatable, Sendable {
  public let text: String
  public let confidence: Double?

  public init(text: String, confidence: Double? = nil) {
    self.text = text
    self.confidence = confidence
  }
}

public struct TranscriptVocabularyEntry: Codable, Equatable, Sendable {
  public let canonicalTerm: String
  public let spokenForms: [String]

  public init(canonicalTerm: String, spokenForms: [String] = []) {
    self.canonicalTerm = canonicalTerm
    self.spokenForms = spokenForms
  }
}

public struct TranscriptVocabulary: Equatable, Sendable {
  public static let maximumContextualStringCount = 100

  public static let developerDefaults = TranscriptVocabulary(
    entries: [
      .init(canonicalTerm: "Crunchyroll", spokenForms: ["crunchy role"]),
      .init(canonicalTerm: "Amazon"),
      .init(canonicalTerm: "Ballislife", spokenForms: ["ball is life", "ballaslive"]),
      .init(canonicalTerm: "GitHub", spokenForms: ["git hub", "gidhub"]),
      .init(canonicalTerm: "Grok", spokenForms: ["grock"]),
      .init(canonicalTerm: "Hulu"),
      .init(canonicalTerm: "Netflix"),
      .init(canonicalTerm: "YouTube", spokenForms: ["you tube"]),
      .init(canonicalTerm: "Notion"),
      .init(canonicalTerm: "Google Chrome"),
      .init(canonicalTerm: "Visual Studio Code", spokenForms: ["VS Code", "vscode"]),
      .init(canonicalTerm: "TypeScript"),
      .init(canonicalTerm: "JavaScript"),
      .init(canonicalTerm: "Node.js", spokenForms: ["node js"]),
      .init(canonicalTerm: "npm"),
      .init(canonicalTerm: "pnpm"),
      .init(canonicalTerm: "React"),
      .init(canonicalTerm: "Next.js", spokenForms: ["next js"]),
      .init(canonicalTerm: "Vercel"),
      .init(canonicalTerm: "Docker"),
      .init(canonicalTerm: "Kubernetes"),
      .init(canonicalTerm: "GraphQL"),
      .init(canonicalTerm: "Postgres"),
      .init(canonicalTerm: "Terraform"),
      .init(canonicalTerm: "CI/CD", spokenForms: ["CI CD"]),
      .init(canonicalTerm: "OpenAI", spokenForms: ["open AI"]),
      .init(canonicalTerm: "Codex"),
      .init(canonicalTerm: "Xcode", spokenForms: ["X code"]),
      .init(canonicalTerm: "SwiftUI", spokenForms: ["Swift UI"]),
    ]
  )

  public let entries: [TranscriptVocabularyEntry]

  public init(entries: [TranscriptVocabularyEntry]) {
    self.entries = Array(entries.prefix(Self.maximumContextualStringCount))
  }

  public func merging(_ additionalEntries: [TranscriptVocabularyEntry]) -> Self {
    var merged: [TranscriptVocabularyEntry] = []
    var indexByCanonicalTerm: [String: Int] = [:]

    for entry in entries + additionalEntries {
      let key = Self.normalized(entry.canonicalTerm)
      guard !key.isEmpty else { continue }

      if let index = indexByCanonicalTerm[key] {
        var seenForms = Set(merged[index].spokenForms.map(Self.normalized))
        let newForms = entry.spokenForms.filter {
          seenForms.insert(Self.normalized($0)).inserted
        }
        merged[index] = TranscriptVocabularyEntry(
          canonicalTerm: merged[index].canonicalTerm,
          spokenForms: merged[index].spokenForms + newForms
        )
        continue
      }

      indexByCanonicalTerm[key] = merged.count
      merged.append(entry)
      guard merged.count < Self.maximumContextualStringCount else { break }
    }
    return Self(entries: merged)
  }

  public var contextualStrings: [String] {
    var seen = Set<String>()
    return
      entries
      // AnalysisContext expects the desired words or phrases. Known ASR
      // mistakes belong only to the deterministic correction layer; feeding
      // them back to Speech would teach the recognizer the wrong spelling.
      .map(\.canonicalTerm)
      .filter { seen.insert(Self.normalized($0)).inserted }
      .prefix(Self.maximumContextualStringCount)
      .map { $0 }
  }

  fileprivate static func normalized(_ text: String) -> String {
    text
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }
}

public enum TranscriptInterpretationReason: String, Codable, Equatable, Sendable {
  case dictationDisfluencyCleanup
  case dictationPauseJoin
  case dictationSpokenPunctuation
  case speechAlternative
  case vocabularyCorrection
}

/// Selects an alternative for dictation only when it is uniquely equivalent to
/// replacing a known spoken form with its canonical personal-vocabulary term.
/// It never performs general hypothesis ranking or rewrites unrelated prose.
public struct DictationTranscriptSelector: Sendable {
  private let vocabulary: TranscriptVocabulary

  public init(vocabulary: TranscriptVocabulary = .developerDefaults) {
    self.vocabulary = vocabulary
  }

  public func select(
    primary: TranscriptHypothesis,
    alternatives: [TranscriptHypothesis] = []
  ) -> TranscriptInterpretation {
    let raw = primary.text.trimmingCharacters(in: .whitespacesAndNewlines)
    var candidates: [String] = []

    for entry in vocabulary.entries {
      for spokenForm in entry.spokenForms {
        let corrected = Self.replacingPhrase(
          spokenForm,
          with: entry.canonicalTerm,
          in: raw
        )
        guard corrected != raw else { continue }
        let correctedKey = TranscriptVocabulary.normalized(corrected)
        guard
          alternatives.contains(where: {
            TranscriptVocabulary.normalized($0.text) == correctedKey
          })
        else { continue }
        candidates.append(corrected)
      }
    }

    let unique = Dictionary(
      grouping: candidates,
      by: TranscriptVocabulary.normalized
    ).compactMap { $0.value.first }
    guard unique.count == 1, let selected = unique.first else {
      return TranscriptInterpretation(
        rawTranscript: raw,
        selectedTranscript: raw,
        confidence: primary.confidence,
        reason: nil
      )
    }

    return TranscriptInterpretation(
      rawTranscript: raw,
      selectedTranscript: selected,
      confidence: primary.confidence,
      reason: .speechAlternative
    )
  }

  private static func replacingPhrase(
    _ phrase: String,
    with replacement: String,
    in text: String
  ) -> String {
    guard
      let range = text.range(
        of: phrase,
        options: [.caseInsensitive, .diacriticInsensitive]
      ),
      isPhraseBoundary(range.lowerBound, in: text, preceding: true),
      isPhraseBoundary(range.upperBound, in: text, preceding: false)
    else { return text }
    return text.replacingCharacters(in: range, with: replacement)
  }

  private static func isPhraseBoundary(
    _ index: String.Index,
    in text: String,
    preceding: Bool
  ) -> Bool {
    let adjacentIndex: String.Index
    if preceding {
      guard index != text.startIndex else { return true }
      adjacentIndex = text.index(before: index)
    } else {
      guard index != text.endIndex else { return true }
      adjacentIndex = index
    }
    let character = text[adjacentIndex]
    return !character.isLetter && !character.isNumber
  }
}

public struct TranscriptInterpretation: Equatable, Sendable {
  public let rawTranscript: String
  public let selectedTranscript: String
  public let confidence: Double?
  public let reason: TranscriptInterpretationReason?

  public var wasCorrected: Bool { reason != nil }
}

/// Selects only interpretations that resolve to existing typed capabilities.
/// It never creates URLs, application identifiers, or execution authority.
public struct TranscriptInterpreter: Sendable {
  private let resolver: CommandResolver
  private let vocabulary: TranscriptVocabulary

  public init(
    resolver: CommandResolver = .init(),
    vocabulary: TranscriptVocabulary = .developerDefaults
  ) {
    self.resolver = resolver
    self.vocabulary = vocabulary
  }

  public func interpret(
    primary: TranscriptHypothesis,
    alternatives: [TranscriptHypothesis] = [],
    allowKnownDomainNarrowing: Bool = false
  ) -> TranscriptInterpretation {
    let raw = primary.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let rawCommand = command(for: raw)

    // Resolver aliases already understand valid target wording such as
    // "crunchy roll" and "chat g p t". Preserve that raw transcript instead
    // of reporting a correction that cannot change the selected target.
    if let rawCommand, !rawCommand.isWebSearch, !rawCommand.isExplicitDomain {
      return unchanged(raw, confidence: primary.confidence)
    }

    if let correction = vocabularyCorrection(
      raw,
      rawCommand: rawCommand,
      confidence: primary.confidence,
      allowKnownDomainNarrowing: allowKnownDomainNarrowing
    ) {
      return correction
    }

    if let rawCommand, !rawCommand.isFallbackSearch {
      return unchanged(raw, confidence: primary.confidence)
    }

    let supportedAlternatives = uniqueSupportedAlternatives(alternatives, excluding: raw)
    let distinctCommands = Set(supportedAlternatives.compactMap(commandKey))
    if distinctCommands.count == 1, let selected = supportedAlternatives.first {
      return TranscriptInterpretation(
        rawTranscript: raw,
        selectedTranscript: selected.text,
        confidence: selected.confidence,
        reason: .speechAlternative
      )
    }

    return unchanged(raw, confidence: primary.confidence)
  }

  private func vocabularyCorrection(
    _ raw: String,
    rawCommand: TopherCommand?,
    confidence: Double?,
    allowKnownDomainNarrowing: Bool
  ) -> TranscriptInterpretation? {
    for entry in vocabulary.entries {
      for spokenForm in entry.spokenForms {
        let corrected = Self.replacingPhrase(
          spokenForm,
          with: entry.canonicalTerm,
          in: raw
        )
        guard
          corrected != raw,
          let correctedCommand = command(for: corrected),
          rawCommand.map({
            hasSameAuthority(
              $0,
              correctedCommand,
              allowKnownDomainNarrowing: allowKnownDomainNarrowing
            )
          }) ?? true
        else { continue }

        return TranscriptInterpretation(
          rawTranscript: raw,
          selectedTranscript: corrected,
          confidence: confidence,
          reason: .vocabularyCorrection
        )
      }
    }
    return nil
  }

  private func unchanged(_ text: String, confidence: Double?) -> TranscriptInterpretation {
    TranscriptInterpretation(
      rawTranscript: text,
      selectedTranscript: text,
      confidence: confidence,
      reason: nil
    )
  }

  private func resolves(_ text: String) -> Bool {
    guard let command = command(for: text) else { return false }
    return !command.isFallbackSearch
  }

  private func command(for text: String) -> TopherCommand? {
    guard case .resolved(let command) = resolver.resolve(text) else { return nil }
    return command
  }

  private func hasSameAuthority(
    _ first: TopherCommand,
    _ second: TopherCommand,
    allowKnownDomainNarrowing: Bool
  ) -> Bool {
    switch (first, second) {
    case (.openApplication(let firstTarget), .openApplication(let secondTarget)):
      firstTarget == secondTarget
    case (
      .openInstalledApplication(let firstTarget),
      .openInstalledApplication(let secondTarget)
    ):
      firstTarget == secondTarget
    case (.openWebsite(let firstTarget), .openWebsite(let secondTarget)):
      firstTarget == secondTarget
    case (.openDomain(let firstDomain), .openDomain(let secondDomain)):
      firstDomain == secondDomain
    case (.openDomain, .openWebsite):
      // Correcting an arbitrary recognized domain to a fixed application-owned
      // destination narrows authority; it never constructs another free URL.
      allowKnownDomainNarrowing
    case (.searchWeb(let firstProvider, _), .searchWeb(let secondProvider, _)):
      firstProvider == secondProvider
    case (.searchUnknownDestination, .openApplication),
      (.searchUnknownDestination, .openInstalledApplication),
      (.searchUnknownDestination, .openWebsite):
      // A vocabulary correction may narrow a transparent search to a
      // registered destination, but it cannot construct a new destination.
      true
    case (.searchUnknownDestination, .searchUnknownDestination),
      (.identifyFrontmostApplication, .identifyFrontmostApplication):
      true
    default:
      false
    }
  }

  private func uniqueSupportedAlternatives(
    _ alternatives: [TranscriptHypothesis],
    excluding raw: String
  ) -> [TranscriptHypothesis] {
    var seen = Set<String>()
    return
      alternatives
      .filter { candidate in
        let normalized = TranscriptVocabulary.normalized(candidate.text)
        return
          !normalized.isEmpty
          && normalized != TranscriptVocabulary.normalized(raw)
          && seen.insert(normalized).inserted
          && resolves(candidate.text)
      }
      .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
  }

  private func commandKey(_ hypothesis: TranscriptHypothesis) -> String? {
    guard case .resolved(let command) = resolver.resolve(hypothesis.text) else { return nil }
    return String(reflecting: command)
  }

  private static func replacingPhrase(
    _ phrase: String,
    with replacement: String,
    in text: String
  ) -> String {
    guard
      let range = text.range(
        of: phrase,
        options: [.caseInsensitive, .diacriticInsensitive]
      ),
      isPhraseBoundary(range.lowerBound, in: text, preceding: true),
      isPhraseBoundary(range.upperBound, in: text, preceding: false)
    else { return text }
    return text.replacingCharacters(in: range, with: replacement)
  }

  private static func isPhraseBoundary(
    _ index: String.Index,
    in text: String,
    preceding: Bool
  ) -> Bool {
    let adjacentIndex: String.Index
    if preceding {
      guard index != text.startIndex else { return true }
      adjacentIndex = text.index(before: index)
    } else {
      guard index != text.endIndex else { return true }
      adjacentIndex = index
    }
    let character = text[adjacentIndex]
    return !character.isLetter && !character.isNumber
  }
}

extension TopherCommand {
  fileprivate var isWebSearch: Bool {
    switch self {
    case .searchWeb, .searchUnknownDestination:
      true
    default:
      false
    }
  }

  fileprivate var isExplicitDomain: Bool {
    if case .openDomain = self { return true }
    return false
  }

  fileprivate var isFallbackSearch: Bool {
    if case .searchUnknownDestination = self { return true }
    return false
  }
}
