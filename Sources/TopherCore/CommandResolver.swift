import Foundation

/// A deliberately narrow deterministic resolver for typed local capabilities.
public struct CommandResolver: Sendable {
  private let installedApplications: [InstalledApplicationTarget]

  public init(installedApplications: [InstalledApplicationTarget] = []) {
    self.installedApplications = installedApplications
  }

  public func resolve(_ transcript: String) -> CommandResolution {
    let request = normalizedRequest(transcript)
    guard !request.isEmpty else {
      return .unsupported(reason: .emptyInput)
    }

    if containsCompoundRequest(request) {
      return .unsupported(reason: .compoundRequest)
    }

    return resolveSingle(transcript)
  }

  private func resolveSingle(_ transcript: String) -> CommandResolution {
    if let target = resolveBareWebsiteSearch(transcript) {
      return .resolved(.openWebsite(target))
    }

    if let resolution = resolveDestinationFirstQuery(transcript) {
      return resolution
    }

    if let resolution = resolveSearchPreservingQuery(transcript) {
      return resolution
    }

    let request = normalizedRequest(transcript)

    if isFrontmostApplicationRequest(request) {
      return .resolved(.identifyFrontmostApplication)
    }

    if requiresDictationMode(request) {
      return .unsupported(reason: .dictationModeRequired)
    }

    if requiresContext(request) {
      return .unsupported(reason: .contextRequired)
    }

    // Exact known targets are safe enough to use as terse commands. Website
    // brands win before native applications, matching explicit "open" forms.
    if let target = WebsiteTarget.matching(request) {
      return .resolved(.openWebsite(target))
    }

    if let target = ApplicationTarget.matching(request) {
      return .resolved(.openApplication(target))
    }

    switch matchingInstalledApplication(request) {
    case .unique(let target):
      return .resolved(.openInstalledApplication(target))
    case .ambiguous:
      return .unsupported(reason: .ambiguousTarget)
    case .none:
      break
    }

    if let requestedName = removingFirstPrefix(
      from: request,
      candidates: Self.navigationPrefixes
    ) {
      if let applicationName = removingExplicitSuffix(
        from: requestedName,
        candidates: ["desktop application", "desktop app", "application", "app"]
      ) {
        if let target = ApplicationTarget.matching(applicationName) {
          return .resolved(.openApplication(target))
        }

        switch matchingInstalledApplication(applicationName) {
        case .unique(let target):
          return .resolved(.openInstalledApplication(target))
        case .ambiguous:
          return .unsupported(reason: .ambiguousTarget)
        case .none:
          return .unsupported(reason: .applicationNotFound)
        }
      }

      if let websiteName = removingExplicitSuffix(
        from: requestedName,
        candidates: ["website", "web site", "site"]
      ) {
        if let target = WebsiteTarget.matching(websiteName) {
          return .resolved(.openWebsite(target))
        }
        return fallbackSearchResolution(transcript, strippingExplicitQualifier: true)
      }

      // Exact known website brands win before native applications. This keeps
      // phrases such as "Open Crunchyroll" web-oriented even if a similarly
      // named native application is supported later.
      if let target = BrowserRouteTarget.matching(requestedName) {
        return .resolved(.openBrowserRoute(target))
      }

      if let target = WebsiteTarget.matching(requestedName) {
        return .resolved(.openWebsite(target))
      }

      if let target = ApplicationTarget.matching(requestedName) {
        return .resolved(.openApplication(target))
      }

      switch matchingInstalledApplication(requestedName) {
      case .unique(let target):
        return .resolved(.openInstalledApplication(target))
      case .ambiguous:
        return .unsupported(reason: .ambiguousTarget)
      case .none:
        break
      }

      if let resolution = resolveTargetQuery(transcript) {
        return resolution
      }

      if let domain = resolveExplicitHTTPSDomain(transcript) {
        return .resolved(.openDomain(domain))
      }

      if containsKnownTargetPrefix(requestedName) {
        return .unsupported(reason: .unsupportedAction)
      }

      // Address-shaped input that failed HTTPSDomain validation stays closed.
      // Free-form words can fall back to a transparent Google search, but a
      // malformed URL must never be silently reinterpreted as navigation.
      if let rawTarget = rawNavigationTarget(transcript), looksLikeAddress(rawTarget) {
        return .unsupported(reason: .unknownTarget)
      }

      return fallbackSearchResolution(transcript)
    }

    return .unsupported(reason: .unsupportedPhrasing)
  }

  private static let navigationPrefixes = [
    "navigate to", "switch over to", "switch to", "bring me to", "take me to",
    "pull up", "open", "launch", "start", "go to", "visit", "navigate",
  ]

  private enum InstalledApplicationMatch {
    case none
    case unique(InstalledApplicationTarget)
    case ambiguous
  }

  private func matchingInstalledApplication(
    _ normalizedName: String
  ) -> InstalledApplicationMatch {
    let matches = installedApplications.filter { $0.aliases.contains(normalizedName) }
    guard let first = matches.first else { return .none }
    guard matches.dropFirst().isEmpty else { return .ambiguous }
    return .unique(first)
  }

  private func fallbackSearchResolution(
    _ transcript: String,
    strippingExplicitQualifier: Bool = false
  ) -> CommandResolution {
    guard var rawTarget = rawNavigationTarget(transcript) else {
      return .unsupported(reason: .missingValue)
    }

    if strippingExplicitQualifier {
      rawTarget = removingRawSuffix(
        from: rawTarget,
        candidates: ["website", "web site", "site"]
      )
    }

    guard let query = commandSearchQuery(rawTarget) else {
      return .unsupported(reason: .missingValue)
    }
    return .resolved(.searchUnknownDestination(query))
  }

  private func rawNavigationTarget(_ transcript: String) -> String? {
    let request = rawCommandRequest(transcript)
    guard
      var target = removingRawPrefix(from: request, candidates: Self.navigationPrefixes)
    else { return nil }

    target = removingLikelySentencePunctuation(from: target)
    target = removingRawSuffix(from: target, candidates: ["please", "for me"])
    return removingLikelySentencePunctuation(from: target)
  }

  private func removingExplicitSuffix(
    from text: String,
    candidates: [String]
  ) -> String? {
    for candidate in candidates {
      if text == candidate { return "" }
      if text.hasSuffix(" " + candidate) {
        return String(text.dropLast(candidate.count + 1))
      }
    }
    return nil
  }

  private func looksLikeAddress(_ value: String) -> Bool {
    value.contains(".")
      || value.contains(":")
      || value.contains("/")
      || value.contains("@")
      || value == "localhost"
  }

  private func isFrontmostApplicationRequest(_ request: String) -> Bool {
    [
      "what app am i using", "what application am i using", "what app is open",
      "what application is open", "what app am i in", "what application am i in",
      "what app is this", "what application is this",
    ].contains(request)
  }

  private func requiresDictationMode(_ request: String) -> Bool {
    ["dictate", "input", "insert", "type", "write"].contains { prefix in
      request == prefix || request.hasPrefix(prefix + " ")
    }
  }

  private func resolveBareWebsiteSearch(_ transcript: String) -> WebsiteTarget? {
    let request = normalizedRequest(transcript)
    guard
      let requestedName = removingFirstPrefix(
        from: request,
        candidates: ["search for", "search", "find"]
      ),
      let target = WebsiteTarget.matching(requestedName),
      target.acceptsBareSearchAsNavigation
    else {
      return nil
    }

    return target
  }

  private func resolveSearchPreservingQuery(_ transcript: String) -> CommandResolution? {
    var request = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    request = removingRawAddress(from: request)
    request =
      removingRawPrefix(
        from: request,
        candidates: ["please", "can you", "could you", "would you"]
      ) ?? request

    let patterns: [(SearchProvider, [String])] = [
      (
        .youtube,
        ["search youtube for", "search on youtube for", "youtube search for"]
      ),
      (
        .google,
        [
          "search google for", "google search for", "search the web for",
          "search chrome for", "search in chrome for", "chrome search for", "search for",
          "google", "search",
        ]
      ),
    ]

    for (provider, prefixes) in patterns {
      guard let queryText = removingRawPrefix(from: request, candidates: prefixes) else {
        continue
      }

      guard let query = commandSearchQuery(queryText) else {
        return .unsupported(reason: .missingValue)
      }

      return .resolved(.searchWeb(provider: provider, query: query))
    }

    return nil
  }

  private func resolveTargetQuery(_ transcript: String) -> CommandResolution? {
    var request = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    request = removingRawAddress(from: request)
    request =
      removingRawPrefix(
        from: request,
        candidates: ["please", "can you", "could you", "would you"]
      ) ?? request

    let verbs = [
      "open", "go to", "visit", "navigate to", "pull up", "bring me to", "take me to",
    ]

    for target in WebsiteTarget.allCases {
      guard let provider = target.queryProvider else { continue }
      for alias in target.aliases.sorted(by: { $0.count > $1.count }) {
        let prefixes = verbs.flatMap { verb in
          [
            "\(verb) \(alias) for",
            "\(verb) \(alias) look for",
            "\(verb) \(alias), look for",
            "\(verb) \(alias) and look for",
            "\(verb) \(alias) search for",
            "\(verb) \(alias), search for",
            "\(verb) \(alias) and search for",
          ]
        }
        guard let queryText = removingRawPrefix(from: request, candidates: prefixes) else {
          continue
        }
        guard let query = commandSearchQuery(queryText) else {
          return .unsupported(reason: .missingValue)
        }
        return .resolved(.searchWeb(provider: provider, query: query))
      }
    }

    return nil
  }

  private func resolveDestinationFirstQuery(_ transcript: String) -> CommandResolution? {
    let request = rawCommandRequest(transcript)

    for target in WebsiteTarget.allCases {
      guard let provider = target.queryProvider else { continue }
      for alias in target.aliases.sorted(by: { $0.count > $1.count }) {
        let explicitPrefixes = ["\(alias) for", "\(alias) search for", "\(alias) search"]
        if let queryText = removingRawPrefix(from: request, candidates: explicitPrefixes) {
          guard let query = commandSearchQuery(queryText) else {
            return .unsupported(reason: .missingValue)
          }
          return .resolved(.searchWeb(provider: provider, query: query))
        }

        if let queryText = removingRawDelimitedPrefix(alias, from: request) {
          guard let query = commandSearchQuery(queryText) else {
            return .unsupported(reason: .missingValue)
          }
          return .resolved(.searchWeb(provider: provider, query: query))
        }

        if let queryText = removingRawPrefix(from: request, candidates: [alias]),
          !queryText.isEmpty,
          let query = commandSearchQuery(queryText)
        {
          return .resolved(.searchWeb(provider: provider, query: query))
        }
      }
    }

    return nil
  }

  private func resolveExplicitHTTPSDomain(_ transcript: String) -> HTTPSDomain? {
    let request = rawCommandRequest(transcript)
    guard
      let value = removingRawPrefix(
        from: request,
        candidates: [
          "navigate to", "switch over to", "switch to", "bring me to", "take me to",
          "pull up", "open", "launch", "start", "go to", "visit", "navigate",
        ]
      )
    else {
      return nil
    }

    let withoutPunctuation = removingLikelySentencePunctuation(from: value)
    let domainText = removingRawSuffix(
      from: withoutPunctuation,
      candidates: ["please", "for me"]
    )
    return HTTPSDomain(domainText)
  }

  private func commandSearchQuery(_ text: String) -> SearchQuery? {
    let payload = removingLikelySentencePunctuation(from: text)
    return SearchQuery(SpokenTechnicalNotation.normalizing(in: payload).text)
  }

  private func removingLikelySentencePunctuation(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let last = trimmed.last,
      ".?!".contains(last),
      trimmed.count > 1
    else {
      return trimmed
    }
    return String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func containsCompoundRequest(_ request: String) -> Bool {
    for connector in [" and then ", " then ", " and "] {
      var searchStart = request.startIndex
      while let range = request.range(of: connector, range: searchStart..<request.endIndex) {
        let first = String(request[..<range.lowerBound])
        let second = String(request[range.upperBound...])
        if containsExecutableClause(first), containsExecutableClause(second) {
          return true
        }
        searchStart = range.upperBound
      }
    }
    return false
  }

  private func containsExecutableClause(_ request: String) -> Bool {
    var pendingSegments = [request]
    var nextIndex = 0
    let maximumSegments = 64

    while nextIndex < pendingSegments.count, nextIndex < maximumSegments {
      let segment = pendingSegments[nextIndex]
      nextIndex += 1
      if case .resolved = resolveSingle(segment) {
        return true
      }

      guard let range = firstConnectorRange(in: segment) else { continue }
      pendingSegments.append(String(segment[..<range.lowerBound]))
      pendingSegments.append(String(segment[range.upperBound...]))
    }
    return false
  }

  private func firstConnectorRange(in request: String) -> Range<String.Index>? {
    [" and then ", " then ", " and "]
      .compactMap { request.range(of: $0) }
      .min { first, second in
        if first.lowerBound == second.lowerBound {
          return first.upperBound > second.upperBound
        }
        return first.lowerBound < second.lowerBound
      }
  }

  private func containsKnownTargetPrefix(_ requestedName: String) -> Bool {
    let aliases =
      WebsiteTarget.allCases.flatMap(\.aliases)
      + ApplicationTarget.allCases.flatMap(\.aliases)
      + BrowserRouteTarget.allCases.flatMap(\.aliases)
    return aliases.contains { alias in
      requestedName == alias || requestedName.hasPrefix(alias + " ")
    }
  }

  private func requiresContext(_ request: String) -> Bool {
    [
      "go to that", "go to this", "navigate to that", "navigate to this", "open that",
      "open this", "what app", "what chrome tabs", "what is this", "what does this",
      "what tabs", "which chrome tabs", "which tabs", "what s on my", "what is on my",
      "summarize this", "reply to this",
    ].contains { request == $0 || request.hasPrefix($0 + " ") }
  }

  private func normalizedRequest(_ transcript: String) -> String {
    let normalized = normalize(transcript)
    let withoutAddress = removingFirstPrefix("topher", from: normalized)
    let withoutPolitePrefix =
      removingFirstPrefix(
        from: withoutAddress,
        candidates: ["please", "can you", "could you", "would you"]
      ) ?? withoutAddress
    return removingFirstSuffix(
      from: withoutPolitePrefix,
      candidates: ["please", "for me"]
    )
  }

  private func removingRawAddress(from text: String) -> String {
    let address = "topher"
    guard text.count >= address.count else { return text }

    let addressEnd = text.index(text.startIndex, offsetBy: address.count)
    let prefix = String(text[..<addressEnd])
    guard prefix.compare(address, options: .caseInsensitive) == .orderedSame else {
      return text
    }

    guard addressEnd != text.endIndex else { return "" }

    let separators = CharacterSet.whitespacesAndNewlines.union(
      CharacterSet(charactersIn: ",:;-")
    )
    guard text[addressEnd].unicodeScalars.allSatisfy({ separators.contains($0) }) else {
      return text
    }

    return String(
      text[addressEnd...].drop(while: { character in
        character.unicodeScalars.allSatisfy { separators.contains($0) }
      })
    )
  }

  private func rawCommandRequest(_ transcript: String) -> String {
    var request = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    request = removingRawAddress(from: request)
    request =
      removingRawPrefix(
        from: request,
        candidates: ["please", "can you", "could you", "would you"]
      ) ?? request
    return request
  }

  private func removingRawDelimitedPrefix(_ prefix: String, from text: String) -> String? {
    guard text.count > prefix.count else { return nil }

    let prefixEnd = text.index(text.startIndex, offsetBy: prefix.count)
    let actualPrefix = String(text[..<prefixEnd])
    guard actualPrefix.compare(prefix, options: .caseInsensitive) == .orderedSame else {
      return nil
    }

    guard ",:".contains(text[prefixEnd]) else { return nil }
    return String(text[text.index(after: prefixEnd)...])
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func removingRawSuffix(from text: String, candidates: [String]) -> String {
    for candidate in candidates {
      guard text.count >= candidate.count else { continue }

      let suffixStart = text.index(text.endIndex, offsetBy: -candidate.count)
      let suffix = String(text[suffixStart...])
      guard suffix.compare(candidate, options: .caseInsensitive) == .orderedSame else {
        continue
      }

      if suffixStart == text.startIndex {
        return ""
      }

      let precedingIndex = text.index(before: suffixStart)
      guard text[precedingIndex].isWhitespace else { continue }
      return String(text[..<precedingIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return text
  }

  private func removingRawPrefix(from text: String, candidates: [String]) -> String? {
    for candidate in candidates {
      guard text.count >= candidate.count else { continue }

      let prefixEnd = text.index(text.startIndex, offsetBy: candidate.count)
      let prefix = String(text[..<prefixEnd])
      guard prefix.compare(candidate, options: .caseInsensitive) == .orderedSame else {
        continue
      }

      if prefixEnd == text.endIndex {
        return ""
      }

      guard text[prefixEnd].isWhitespace else { continue }
      return String(text[prefixEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return nil
  }

  private func normalize(_ text: String) -> String {
    let lowered = text.lowercased()
    let words = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
    return words.filter { !$0.isEmpty }.joined(separator: " ")
  }

  private func removingFirstPrefix(_ prefix: String, from text: String) -> String {
    removingFirstPrefix(from: text, candidates: [prefix]) ?? text
  }

  private func removingFirstPrefix(from text: String, candidates: [String]) -> String? {
    for candidate in candidates {
      if text == candidate {
        return ""
      }
      if text.hasPrefix(candidate + " ") {
        return String(text.dropFirst(candidate.count + 1))
      }
    }
    return nil
  }

  private func removingFirstSuffix(from text: String, candidates: [String]) -> String {
    for candidate in candidates {
      if text == candidate {
        return ""
      }
      if text.hasSuffix(" " + candidate) {
        return String(text.dropLast(candidate.count + 1))
      }
    }
    return text
  }
}
