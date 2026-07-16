import Foundation

/// A deliberately narrow deterministic resolver for typed local capabilities.
public struct CommandResolver: Sendable {
  public init() {}

  public func resolve(_ transcript: String) -> CommandResolution {
    if let target = resolveBareWebsiteSearch(transcript) {
      return .resolved(.openWebsite(target))
    }

    if let command = resolveSearchPreservingQuery(transcript) {
      return .resolved(command)
    }

    let normalized = normalize(transcript)
    guard !normalized.isEmpty else {
      return .unsupported
    }

    let withoutAddress = removingFirstPrefix("topher", from: normalized)
    let withoutPolitePrefix =
      removingFirstPrefix(
        from: withoutAddress,
        candidates: ["please", "can you", "could you", "would you"]
      ) ?? withoutAddress

    let request = removingFirstSuffix(
      from: withoutPolitePrefix,
      candidates: ["please", "for me"]
    )

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
      if let target = WebsiteTarget.matching(requestedName) {
        return .resolved(.openWebsite(target))
      }

      if let target = ApplicationTarget.matching(requestedName) {
        return .resolved(.openApplication(target))
      }

      return .unsupported
    }

    return .unsupported
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

  private func resolveSearchPreservingQuery(_ transcript: String) -> TopherCommand? {
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
        return nil
      }

      return .searchWeb(provider: provider, query: query)
    }

    return nil
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
