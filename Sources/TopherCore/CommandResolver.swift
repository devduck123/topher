import Foundation

/// A deliberately narrow deterministic resolver for typed local capabilities.
public struct CommandResolver: Sendable {
  public init() {}

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

    if let resolution = resolveSearchPreservingQuery(transcript) {
      return resolution
    }

    let request = normalizedRequest(transcript)
    if requiresContext(request) {
      return .unsupported(reason: .contextRequired)
    }

    if let requestedName = removingFirstPrefix(
      from: request,
      candidates: [
        "open", "launch", "start", "go to", "visit", "navigate to", "navigate",
        "switch to", "switch over to", "pull up", "bring me to", "take me to",
      ]
    ) {
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

      if let resolution = resolveTargetQuery(transcript) {
        return resolution
      }

      return .unsupported(
        reason: containsKnownTargetPrefix(requestedName) ? .unsupportedAction : .unknownTarget
      )
    }

    return .unsupported(reason: .unsupportedPhrasing)
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
          "search google for", "google search for", "search the web for", "search for",
          "google", "search",
        ]
      ),
    ]

    for (provider, prefixes) in patterns {
      guard let queryText = removingRawPrefix(from: request, candidates: prefixes) else {
        continue
      }

      guard let query = SearchQuery(queryText) else {
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
        let prefixes = verbs.map { "\($0) \(alias) for" }
        guard let queryText = removingRawPrefix(from: request, candidates: prefixes) else {
          continue
        }
        guard let query = SearchQuery(queryText) else {
          return .unsupported(reason: .missingValue)
        }
        return .resolved(.searchWeb(provider: provider, query: query))
      }
    }

    return nil
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
