import Foundation

/// A deliberately narrow deterministic resolver for typed local capabilities.
public struct CommandResolver: Sendable {
  private let installedApplications: [InstalledApplicationTarget]

  public init(installedApplications: [InstalledApplicationTarget] = []) {
    self.installedApplications = installedApplications
  }

  public func resolve(
    _ transcript: String,
    context: CommandResolutionContext = .none
  ) -> CommandResolution {
    let request = normalizedRequest(transcript)
    guard !request.isEmpty else {
      return .unsupported(reason: .emptyInput)
    }

    if containsCompoundRequest(request, context: context) {
      return .unsupported(reason: .compoundRequest)
    }

    return resolveSingle(transcript, context: context)
  }

  private func resolveSingle(
    _ transcript: String,
    context: CommandResolutionContext
  ) -> CommandResolution {
    if let resolution = resolveYouTubeFeedFollowup(
      transcript,
      context: context
    ) {
      return resolution
    }

    if let resolution = resolveChromeTabActivation(transcript) {
      return resolution
    }

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

    if isActiveChromeTabRequest(request) {
      return .resolved(.identifyActiveChromeTab)
    }

    if isChromeTabListRequest(request) {
      return .resolved(.listChromeTabs)
    }

    if isYouTubeFeedRequest(request) {
      return .resolved(.readYouTubeFeed)
    }

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

  private func isActiveChromeTabRequest(_ request: String) -> Bool {
    [
      "what is this chrome tab", "what is the active chrome tab",
      "what chrome tab is this", "which chrome tab is active",
    ].contains(request)
  }

  private func isChromeTabListRequest(_ request: String) -> Bool {
    [
      "what chrome tabs do i have open", "what tabs do i have open",
      "list my chrome tabs", "list my open chrome tabs", "which chrome tabs are open",
    ].contains(request)
  }

  private func isYouTubeFeedRequest(_ request: String) -> Bool {
    Self.youTubeFeedRequests.contains(request)
  }

  private static let youTubeFeedRequests: Set<String> = {
    let targets = [
      "my youtube feed", "the youtube feed", "my youtube home page",
      "my youtube homepage", "the youtube home page", "the youtube homepage",
      "youtube home page", "youtube homepage", "my youtube home", "the youtube home",
      "youtube home", "my youtube home screen", "the youtube home screen",
      "youtube home screen", "youtube recommendations", "my youtube recommendations",
    ]
    let readPrefixes = [
      "what s on", "what is on", "what videos are on", "what are the videos on",
      "what videos are in", "what are the videos in", "show", "show me",
      "show me videos on", "show me the videos on", "show me videos in",
      "show me the videos in", "list", "list the videos on", "check", "check out",
      "let me see", "read", "read out", "read me",
    ]
    var requests = Set(readPrefixes.flatMap { prefix in targets.map { "\(prefix) \($0)" } })
    let conversationalPrefixes = [
      "what s in", "what is in", "what s new on", "what is new on",
      "show me what s on", "show me what is on", "show me what s in", "show me what is in",
      "tell me what s on", "tell me what is on", "tell me what s in", "tell me what is in",
    ]
    requests.formUnion(
      conversationalPrefixes.flatMap { prefix in targets.map { "\(prefix) \($0)" } }
    )
    requests.formUnion([
      "what is youtube recommending", "what s youtube recommending",
      "what does youtube recommend", "what are my youtube recommendations",
      "what recommendations are on youtube", "what do i have on my youtube feed",
      "what videos do i have on my youtube feed", "what is recommended on youtube",
      "what s recommended on youtube", "show me recommended videos on youtube",
      "show me what youtube recommends", "tell me what youtube is recommending",
      "what is youtube showing me", "what s youtube showing me",
      "what videos is youtube recommending", "what videos is youtube recommending to me",
    ])
    return requests
  }()

  private func resolveYouTubeFeedFollowup(
    _ transcript: String,
    context: CommandResolutionContext
  ) -> CommandResolution? {
    let scope = context.youTubeFollowUpScope
    var rawRequest = rawCommandRequest(transcript)
    if scope != .unavailable {
      rawRequest =
        removingRawPrefix(
          from: rawRequest,
          candidates: [
            "let's", "lets", "can we", "could we", "I want to", "I'd like to", "I want",
            "I'll take", "I’d like to", "I’ll take", "I'd like", "I’d like",
          ]
        ) ?? rawRequest
    }
    if let rawTitle = removingRawPrefix(
      from: rawRequest,
      candidates: [
        "open the youtube video titled", "open youtube video titled",
        "play the youtube video titled", "play youtube video titled",
        "watch the youtube video titled", "watch youtube video titled",
        "open the youtube video called", "open youtube video called",
        "play the youtube video called", "play youtube video called",
        "watch the youtube video called", "watch youtube video called",
        "open the youtube video named", "open youtube video named",
        "play the youtube video named", "play youtube video named",
        "watch the youtube video named", "watch youtube video named",
        "open that youtube video titled", "play that youtube video titled",
        "watch that youtube video titled", "open that youtube video called",
        "play that youtube video called", "watch that youtube video called",
        "open that youtube video named", "play that youtube video named",
        "watch that youtube video named",
      ]
    ) {
      let title = removingLikelySentencePunctuation(from: rawTitle)
      guard let query = YouTubeVideoTitleQuery(title) else {
        return .unsupported(reason: .missingValue)
      }
      return .resolved(.openYouTubeFeedItem(.title(query)))
    }

    var request = normalizedRequest(transcript)
    if scope != .unavailable {
      request =
        removingFirstPrefix(
          from: request,
          candidates: [
            "let s", "can we", "could we", "i want to", "i d like to", "i want",
            "i ll take", "i d like",
          ]
        ) ?? request
    }
    let pronounRequests = [
      "open that youtube video", "play that youtube video", "watch that youtube video",
      "open that youtube recommendation", "play that youtube recommendation",
      "watch that youtube recommendation", "open that video", "play that video",
      "watch that video", "open that one", "play that one", "watch that one",
      "open it", "play it", "watch it",
    ]
    if pronounRequests.contains(request) {
      if scope != .unavailable, context.youTubeFeedItemCount == 1 {
        return .resolved(.openYouTubeFeedItem(.ordinal(1)))
      }
      return .unsupported(
        reason: scope == .unavailable ? .youTubeFeedRequired : .youTubeSelectionRequired
      )
    }

    let explicitYouTubePrefixes = [
      "open the youtube recommendation number", "open the youtube video number",
      "open that youtube recommendation number", "open that youtube video number",
      "open youtube recommendation number", "open youtube video number",
      "play the youtube recommendation number", "play the youtube video number",
      "play that youtube recommendation number", "play that youtube video number",
      "play youtube recommendation number", "play youtube video number",
      "watch the youtube recommendation number", "watch the youtube video number",
      "watch that youtube recommendation number", "watch that youtube video number",
      "watch youtube recommendation number", "watch youtube video number",
      "open the youtube recommendation", "open the youtube video",
      "open that youtube recommendation", "open that youtube video",
      "open youtube recommendation", "open youtube video",
      "play the youtube recommendation", "play the youtube video",
      "play that youtube recommendation", "play that youtube video",
      "play youtube recommendation", "play youtube video",
      "watch the youtube recommendation", "watch the youtube video",
      "watch that youtube recommendation", "watch that youtube video",
      "watch youtube recommendation", "watch youtube video",
    ]
    if let reference = removingFirstPrefix(from: request, candidates: explicitYouTubePrefixes) {
      if let ordinal = youTubeOrdinal(
        from: reference,
        itemCount: context.youTubeFeedItemCount
      ) {
        return .resolved(.openYouTubeFeedItem(.ordinal(ordinal)))
      }
      guard scope != .unavailable,
        let rawTitle = removingRawPrefix(
          from: rawRequest,
          candidates: [
            "open the youtube recommendation", "open the youtube video",
            "open that youtube recommendation", "open that youtube video",
            "open youtube recommendation", "open youtube video",
            "play the youtube recommendation", "play the youtube video",
            "play that youtube recommendation", "play that youtube video",
            "play youtube recommendation", "play youtube video",
            "watch the youtube recommendation", "watch the youtube video",
            "watch that youtube recommendation", "watch that youtube video",
            "watch youtube recommendation", "watch youtube video",
          ]
        ),
        let query = YouTubeVideoTitleQuery(removingLikelySentencePunctuation(from: rawTitle))
      else {
        return .unsupported(reason: .youTubeFeedRequired)
      }
      return .resolved(.openYouTubeFeedItem(.title(query)))
    }

    let contextualTitlePrefixes = [
      "open the video titled", "open video titled", "play the video titled",
      "play video titled", "watch the video titled", "watch video titled",
      "open the video called", "open video called", "play the video called",
      "play video called", "watch the video called", "watch video called",
      "open the video named", "open video named", "play the video named",
      "play video named", "watch the video named", "watch video named",
      "open the one titled", "open one titled", "play the one titled", "play one titled",
      "watch the one titled", "watch one titled", "open the one called", "open one called",
      "play the one called", "play one called", "watch the one called", "watch one called",
      "open the one named", "open one named", "play the one named", "play one named",
      "watch the one named", "watch one named",
    ]
    if let rawTitle = removingRawPrefix(from: rawRequest, candidates: contextualTitlePrefixes) {
      guard scope != .unavailable else {
        return .unsupported(reason: .youTubeFeedRequired)
      }
      let title = removingLikelySentencePunctuation(from: rawTitle)
      guard let query = YouTubeVideoTitleQuery(title) else {
        return .unsupported(reason: .missingValue)
      }
      return .resolved(.openYouTubeFeedItem(.title(query)))
    }

    let contextualPrefixes = [
      "open recommendation number", "open video number", "open item number", "open result number",
      "open number", "play recommendation number", "play video number", "play item number",
      "play result number", "play number", "watch recommendation number", "watch video number",
      "watch item number", "watch result number", "watch number", "choose recommendation number",
      "choose video number", "choose item number", "choose result number", "choose number",
      "select recommendation number", "select video number", "select item number",
      "select result number", "select number", "pick recommendation number", "pick video number",
      "pick item number", "pick result number", "pick number", "go with recommendation number",
      "go with video number", "go with item number", "go with result number", "go with number",
      "open recommendation", "open video", "open item", "open result", "open the", "open",
      "play recommendation", "play video", "play item", "play result", "play the", "play",
      "watch recommendation", "watch video", "watch item", "watch result", "watch the", "watch",
      "choose recommendation", "choose video", "choose item", "choose result", "choose the",
      "choose", "select recommendation", "select video", "select item", "select result",
      "select the", "select", "pick recommendation", "pick video", "pick item", "pick result",
      "pick the", "pick", "go with recommendation", "go with video", "go with item",
      "go with result", "go with the", "go with",
    ]
    var references = [request]
    if let stripped = removingFirstPrefix(from: request, candidates: contextualPrefixes) {
      references.insert(stripped, at: 0)
    }
    if let ordinal = references.lazy.compactMap({
      youTubeOrdinal(from: $0, itemCount: context.youTubeFeedItemCount)
    }).first {
      guard scope != .unavailable else {
        return .unsupported(reason: .youTubeFeedRequired)
      }
      return .resolved(.openYouTubeFeedItem(.ordinal(ordinal)))
    }

    let looksLikeSelectionReference =
      request.contains(" number ")
      || request.hasPrefix("open number ")
      || request.hasPrefix("play number ")
      || request.hasPrefix("watch number ")
      || request.hasSuffix(" one")
      || [" video ", " item ", " result ", " recommendation "].contains(where: request.contains)
    if looksLikeSelectionReference,
      ["open ", "play ", "watch ", "choose ", "select ", "pick ", "go with "]
        .contains(where: request.hasPrefix)
    {
      return .unsupported(
        reason: scope == .unavailable ? .youTubeFeedRequired : .contextRequired
      )
    }

    if request.contains("youtube recommendation"),
      ["open ", "play ", "watch ", "choose ", "select ", "pick ", "go with "]
        .contains(where: request.hasPrefix)
    {
      return .unsupported(reason: .unsupportedAction)
    }

    return nil
  }

  private func youTubeOrdinal(from reference: String, itemCount: Int?) -> Int? {
    var value = reference
    if let itemCount, (1...ChromeBridgeRequest.maximumYouTubeFeedItemCount).contains(itemCount),
      [
        "last", "the last", "last one", "the last one", "last video", "the last video",
        "last item", "the last item", "last result", "the last result",
        "last recommendation", "the last recommendation",
      ].contains(value)
    {
      return itemCount
    }
    value =
      removingFirstPrefix(
        from: value,
        candidates: ["the", "number", "no", "video", "item", "result", "recommendation"]
      ) ?? value
    if let ordinal = Self.youTubeOrdinalValues[value] {
      return ordinal
    }
    value = removingFirstSuffix(
      from: value,
      candidates: [
        "youtube recommendation", "youtube video", "one", "video", "recommendation", "item",
        "result",
      ]
    )
    value = removingFirstPrefix(from: value, candidates: ["number", "no"]) ?? value
    if let ordinal = Self.youTubeOrdinalValues[value] {
      return ordinal
    }
    guard let numeric = Int(value), numeric > 0, numeric <= 999 else { return nil }
    return numeric
  }

  private static let youTubeOrdinalValues: [String: Int] = {
    let words = [
      "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
      "ninth", "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth",
      "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth",
    ]
    var values = Dictionary(
      uniqueKeysWithValues: words.enumerated().map { ($0.element, $0.offset + 1) })
    let cardinalWords = [
      "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
      "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
      "eighteen", "nineteen", "twenty",
    ]
    for (index, word) in cardinalWords.enumerated() {
      values[word] = index + 1
    }
    for value in 1...ChromeBridgeRequest.maximumYouTubeFeedItemCount {
      values[String(value)] = value
      let suffix: String
      if (11...13).contains(value % 100) {
        suffix = "th"
      } else {
        suffix =
          switch value % 10 {
          case 1: "st"
          case 2: "nd"
          case 3: "rd"
          default: "th"
          }
      }
      values["\(value)\(suffix)"] = value
    }
    return values
  }()

  private func resolveChromeTabActivation(_ transcript: String) -> CommandResolution? {
    let request = rawCommandRequest(transcript)
    guard
      let rawTitle = removingRawPrefix(
        from: request,
        candidates: [
          "go to the chrome tab titled", "go to chrome tab titled",
          "switch to the chrome tab titled", "switch to chrome tab titled",
          "activate the chrome tab titled", "activate chrome tab titled",
        ]
      )
    else { return nil }

    let title = removingLikelySentencePunctuation(from: rawTitle)
    guard let query = ChromeTabTitleQuery(title) else {
      return .unsupported(reason: .missingValue)
    }
    return .resolved(.activateChromeTab(query))
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

  private func containsCompoundRequest(
    _ request: String,
    context: CommandResolutionContext
  ) -> Bool {
    for connector in [" and then ", " then ", " and "] {
      var searchStart = request.startIndex
      while let range = request.range(of: connector, range: searchStart..<request.endIndex) {
        let first = String(request[..<range.lowerBound])
        let second = String(request[range.upperBound...])
        if containsExecutableClause(first, context: context),
          containsExecutableClause(second, context: context)
        {
          return true
        }
        searchStart = range.upperBound
      }
    }
    return false
  }

  private func containsExecutableClause(
    _ request: String,
    context: CommandResolutionContext
  ) -> Bool {
    var pendingSegments = [request]
    var nextIndex = 0
    let maximumSegments = 64

    while nextIndex < pendingSegments.count, nextIndex < maximumSegments {
      let segment = pendingSegments[nextIndex]
      nextIndex += 1
      if case .resolved = resolveSingle(segment, context: context) {
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
