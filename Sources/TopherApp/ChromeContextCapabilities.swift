import Foundation
import OSLog
import TopherCore

enum ChromeContextError: Error, Equatable, Sendable {
  case activationOutcomeUnknown
  case bridgeUnavailable
  case busy
  case canceled
  case malformedResponse
  case navigationOutcomeUnknown
  case provider(ChromeBridgeFailureCode)
  case responseTimedOut
  case versionMismatch
}

struct ChromeTabList: Equatable, Sendable {
  let tabs: [ChromeTabSnapshot]
  let excludedTabCount: Int
  let observationWasTruncated: Bool
}

struct ChromeBridgeExchange: Sendable {
  let send: @Sendable (ChromeBridgeRequest) async throws -> ChromeBridgeResponse
  let cancel: @Sendable (UUID) async -> Void

  init(
    send: @escaping @Sendable (ChromeBridgeRequest) async throws -> ChromeBridgeResponse,
    cancel: @escaping @Sendable (UUID) async -> Void = { _ in }
  ) {
    self.send = send
    self.cancel = cancel
  }

  static let unavailable = Self(send: { _ in
    throw ChromeContextError.bridgeUnavailable
  })
}

/// Validates every extension response and owns request timeout, cancellation,
/// concurrency, duplicate-ID, and no-retry behavior.
actor ChromeBridgeClient {
  static let standardReadTimeout: Duration = .seconds(2)
  static let standardFeedReadTimeout: Duration = .seconds(3)
  static let standardActivationTimeout: Duration = .seconds(3)
  static let maximumConcurrentRequests = 4

  private let exchange: ChromeBridgeExchange
  private let readTimeout: Duration
  private let feedReadTimeout: Duration
  private let activationTimeout: Duration
  private let maximumConcurrentRequests: Int
  private var inFlightRequestIDs = Set<UUID>()

  init(
    exchange: ChromeBridgeExchange,
    readTimeout: Duration = standardReadTimeout,
    feedReadTimeout: Duration = standardFeedReadTimeout,
    activationTimeout: Duration = standardActivationTimeout,
    maximumConcurrentRequests: Int = maximumConcurrentRequests
  ) {
    self.exchange = exchange
    self.readTimeout = readTimeout
    self.feedReadTimeout = feedReadTimeout
    self.activationTimeout = activationTimeout
    self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
  }

  func activeTab() async throws -> ChromeTabSnapshot {
    let request = ChromeBridgeRequest.activeTab()
    let response = try await perform(request, timeout: readTimeout)
    guard
      response.status == .success,
      response.failureCode == nil,
      response.tabs == nil,
      response.youTubeFeed == nil,
      response.excludedTabCount == nil,
      response.observationWasTruncated == nil,
      let tab = response.tab?.validatedSnapshot,
      tab.active
    else {
      throw responseError(response)
    }
    return tab
  }

  func listTabs(maximumCount: Int) async throws -> ChromeTabList {
    guard let request = ChromeBridgeRequest.listTabs(maximumTabCount: maximumCount) else {
      throw ChromeContextError.malformedResponse
    }
    let response = try await perform(request, timeout: readTimeout)
    guard
      response.status == .success,
      response.failureCode == nil,
      response.tab == nil,
      response.youTubeFeed == nil,
      let wireTabs = response.tabs,
      wireTabs.count <= maximumCount,
      let excludedTabCount = response.excludedTabCount,
      excludedTabCount >= 0,
      let observationWasTruncated = response.observationWasTruncated
    else {
      throw responseError(response)
    }

    let tabs = wireTabs.compactMap(\.validatedSnapshot)
    guard tabs.count == wireTabs.count else {
      throw ChromeContextError.malformedResponse
    }
    return ChromeTabList(
      tabs: tabs,
      excludedTabCount: excludedTabCount,
      observationWasTruncated: observationWasTruncated
    )
  }

  func youTubeFeed() async throws -> YouTubeFeedSnapshot {
    let request = ChromeBridgeRequest.youTubeFeed()
    let response = try await perform(request, timeout: feedReadTimeout)
    guard
      response.status == .success,
      response.failureCode == nil,
      response.tab == nil,
      response.tabs == nil,
      response.excludedTabCount == nil,
      response.observationWasTruncated == nil,
      let feed = response.youTubeFeed?.validatedSnapshot
    else {
      throw responseError(response)
    }
    return feed
  }

  func activate(_ target: ChromeTabActivationTarget) async throws {
    let request = ChromeBridgeRequest.activate(target)
    do {
      let response = try await perform(request, timeout: activationTimeout)
      guard
        response.status == .success,
        response.failureCode == nil,
        response.tab == nil,
        response.tabs == nil,
        response.youTubeFeed == nil,
        response.excludedTabCount == nil,
        response.observationWasTruncated == nil
      else {
        throw responseError(response)
      }
    } catch ChromeContextError.responseTimedOut {
      // Activation is never retried after dispatch: a lost reply is an unknown
      // outcome, not permission to possibly run the mutation again.
      throw ChromeContextError.activationOutcomeUnknown
    }
  }

  func openYouTubeVideo(_ target: YouTubeVideoOpenTarget) async throws {
    let request = ChromeBridgeRequest.openYouTubeVideo(target)
    do {
      let response = try await perform(request, timeout: activationTimeout)
      guard
        response.status == .success,
        response.failureCode == nil,
        response.tab == nil,
        response.tabs == nil,
        response.youTubeFeed == nil,
        response.excludedTabCount == nil,
        response.observationWasTruncated == nil
      else {
        throw responseError(response)
      }
    } catch ChromeContextError.responseTimedOut {
      throw ChromeContextError.navigationOutcomeUnknown
    }
  }

  private func perform(
    _ request: ChromeBridgeRequest,
    timeout: Duration
  ) async throws -> ChromeBridgeResponse {
    guard inFlightRequestIDs.count < maximumConcurrentRequests else {
      throw ChromeContextError.busy
    }
    guard inFlightRequestIDs.insert(request.requestID).inserted else {
      throw ChromeContextError.busy
    }
    defer { inFlightRequestIDs.remove(request.requestID) }

    let exchange = exchange
    let response = try await withTaskCancellationHandler {
      try await withThrowingTaskGroup(of: ChromeBridgeResponse.self) { group in
        group.addTask {
          try await exchange.send(request)
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw ChromeContextError.responseTimedOut
        }

        guard let response = try await group.next() else {
          throw ChromeContextError.bridgeUnavailable
        }
        group.cancelAll()
        return response
      }
    } onCancel: {
      Task {
        await exchange.cancel(request.requestID)
      }
    }

    guard response.version == ChromeBridgeRequest.protocolVersion else {
      throw ChromeContextError.versionMismatch
    }
    guard response.requestID == request.requestID else {
      throw ChromeContextError.malformedResponse
    }
    return response
  }

  private func responseError(_ response: ChromeBridgeResponse) -> ChromeContextError {
    if let failureCode = response.failureCode {
      return failureCode == .canceled ? .canceled : .provider(failureCode)
    }
    return .malformedResponse
  }
}

@MainActor
final class YouTubeFeedSessionStore {
  private(set) var snapshot: YouTubeFeedSnapshot?

  func replace(with snapshot: YouTubeFeedSnapshot) {
    self.snapshot = snapshot
  }

  func current(nowMilliseconds: Int64) -> YouTubeFeedSnapshot? {
    guard let snapshot else { return nil }
    guard nowMilliseconds <= snapshot.expiresAtMilliseconds else {
      self.snapshot = nil
      return nil
    }
    return snapshot
  }

  func clear() {
    snapshot = nil
  }
}

struct YouTubeFeedReadExecution: Equatable, Sendable {
  let outcome: ActionOutcome
  let snapshot: YouTubeFeedSnapshot?
}

@MainActor
final class ChromeYouTubeFeedCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "chromeYouTubeFeedContext",
    access: .readsState,
    risk: .readOnly
  )

  private let client: ChromeBridgeClient
  private let sessionStore: YouTubeFeedSessionStore
  private let nowMilliseconds: @Sendable () -> Int64

  init(
    client: ChromeBridgeClient,
    sessionStore: YouTubeFeedSessionStore,
    nowMilliseconds: @escaping @Sendable () -> Int64
  ) {
    self.client = client
    self.sessionStore = sessionStore
    self.nowMilliseconds = nowMilliseconds
  }

  func execute() async -> YouTubeFeedReadExecution {
    do {
      let snapshot = try await client.youTubeFeed()
      let now = nowMilliseconds()
      guard
        now >= snapshot.capturedAtMilliseconds
          - ChromeYouTubeVideoOpenCapability.maximumFutureClockSkewMilliseconds,
        now <= snapshot.expiresAtMilliseconds
      else {
        sessionStore.clear()
        return YouTubeFeedReadExecution(
          outcome: .failed(message: "The YouTube feed snapshot was already stale. Ask again."),
          snapshot: nil
        )
      }
      sessionStore.replace(with: snapshot)
      let noun = snapshot.items.count == 1 ? "recommendation" : "recommendations"
      var message =
        "I found \(snapshot.items.count) YouTube \(noun). Open Topher to review the numbered list."
      if snapshot.observationWasTruncated {
        message += " The view is bounded; use a number for the safest follow-up."
      }
      return YouTubeFeedReadExecution(
        outcome: .succeeded(message: message),
        snapshot: snapshot
      )
    } catch {
      sessionStore.clear()
      return YouTubeFeedReadExecution(
        outcome: .failed(message: chromeFailureMessage(error)),
        snapshot: nil
      )
    }
  }
}

@MainActor
final class ChromeYouTubeVideoOpenCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "openChromeYouTubeFeedVideo",
    access: .changesState,
    risk: .lowRiskReversible
  )
  static let maximumFutureClockSkewMilliseconds: Int64 = 1_000

  private let client: ChromeBridgeClient
  private let sessionStore: YouTubeFeedSessionStore
  private let nowMilliseconds: @Sendable () -> Int64

  init(
    client: ChromeBridgeClient,
    sessionStore: YouTubeFeedSessionStore,
    nowMilliseconds: @escaping @Sendable () -> Int64
  ) {
    self.client = client
    self.sessionStore = sessionStore
    self.nowMilliseconds = nowMilliseconds
  }

  func execute(_ selection: YouTubeFeedSelection) async -> ActionOutcome {
    let now = nowMilliseconds()
    guard let snapshot = sessionStore.current(nowMilliseconds: now) else {
      return .failed(
        message: "Ask “What’s on my YouTube feed?” first, then use the numbered list promptly."
      )
    }
    guard now >= snapshot.capturedAtMilliseconds - Self.maximumFutureClockSkewMilliseconds else {
      sessionStore.clear()
      return .failed(message: "The YouTube feed snapshot has invalid timing. Ask again.")
    }

    let item: YouTubeFeedItem
    switch selection {
    case .ordinal(let position):
      guard let match = snapshot.items.first(where: { $0.position == position }) else {
        return .failed(
          message: "That number is not in the current YouTube list. Choose a listed number."
        )
      }
      item = match
    case .title(let query):
      guard !snapshot.observationWasTruncated else {
        return .failed(
          message:
            "The YouTube list was bounded, so a title match could be incomplete. Use its number or ask again."
        )
      }
      let matches = snapshot.items.filter { query.matches($0.title) }
      guard let match = matches.first else {
        return .failed(message: "That title is not in the current YouTube list. Ask again.")
      }
      guard matches.dropFirst().isEmpty else {
        return .failed(
          message: "More than one listed YouTube video has that title. Use its number."
        )
      }
      item = match
    }

    // Consume the reference before dispatch. A timeout or disconnect after the
    // request leaves the navigation outcome unknown, so the same snapshot must
    // never authorize a replay.
    sessionStore.clear()
    do {
      try await client.openYouTubeVideo(snapshot.openTarget(for: item))
      return .succeeded(message: "Opened “\(boundedTitle(item.title))” in the YouTube tab.")
    } catch {
      return .failed(message: chromeFailureMessage(error))
    }
  }
}

@MainActor
final class ChromeActiveTabCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "chromeActiveTabContext",
    access: .readsState,
    risk: .readOnly
  )

  private let client: ChromeBridgeClient

  init(client: ChromeBridgeClient) {
    self.client = client
  }

  func execute() async -> ActionOutcome {
    do {
      let tab = try await client.activeTab()
      return .succeeded(
        message: "This Chrome tab is “\(boundedTitle(tab.title))” on \(tab.url.displayOrigin)."
      )
    } catch {
      return .failed(message: chromeFailureMessage(error))
    }
  }
}

@MainActor
final class ChromeTabListCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "chromeTabListContext",
    access: .readsState,
    risk: .readOnly
  )
  static let maximumReturnedTabCount = 25

  private let client: ChromeBridgeClient

  init(client: ChromeBridgeClient) {
    self.client = client
  }

  func execute() async -> ActionOutcome {
    do {
      let result = try await client.listTabs(maximumCount: Self.maximumReturnedTabCount)
      guard !result.tabs.isEmpty else {
        return .succeeded(message: "I found no supported non-incognito Chrome tabs.")
      }

      let titles = result.tabs.enumerated().map { index, tab in
        "\(index + 1). \(boundedTitle(tab.title, maximumCharacters: 100))"
      }
      var message = "Open Chrome tabs:\n" + titles.joined(separator: "\n")
      if result.excludedTabCount > 0 {
        message += "\n\(result.excludedTabCount) tab(s) were excluded by scheme or the list bound."
      }
      message += " Incognito tabs are intentionally unavailable."
      return .succeeded(message: message)
    } catch {
      return .failed(message: chromeFailureMessage(error))
    }
  }
}

@MainActor
final class ChromeTabActivationCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "activateChromeTab",
    access: .changesState,
    risk: .lowRiskReversible
  )
  static let maximumSnapshotAgeMilliseconds: Int64 = 5_000
  static let maximumFutureClockSkewMilliseconds: Int64 = 1_000

  private let client: ChromeBridgeClient
  private let nowMilliseconds: @Sendable () -> Int64

  init(
    client: ChromeBridgeClient,
    nowMilliseconds: @escaping @Sendable () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    self.client = client
    self.nowMilliseconds = nowMilliseconds
  }

  func execute(_ query: ChromeTabTitleQuery) async -> ActionOutcome {
    do {
      let result = try await client.listTabs(maximumCount: ChromeBridgeRequest.maximumTabCount)
      guard !result.observationWasTruncated else {
        return .failed(
          message:
            "Topher couldn't safely check every supported Chrome tab within the activation bound, so it did not switch tabs."
        )
      }
      let matches = result.tabs.filter { query.matches($0.title) }

      guard let match = matches.first else {
        return .failed(message: "I couldn't find a non-incognito Chrome tab with that exact title.")
      }
      guard matches.dropFirst().isEmpty else {
        return .failed(
          message:
            "More than one Chrome tab has that exact title. Make the titles unique and try again."
        )
      }

      let age = nowMilliseconds() - match.capturedAtMilliseconds
      guard
        age >= -Self.maximumFutureClockSkewMilliseconds,
        age <= Self.maximumSnapshotAgeMilliseconds
      else {
        return .failed(message: "Chrome's tab snapshot was stale. Ask again to refresh it.")
      }

      try await client.activate(match.activationTarget)
      return .succeeded(message: "Switched to the Chrome tab “\(boundedTitle(match.title))”.")
    } catch {
      return .failed(message: chromeFailureMessage(error))
    }
  }
}

@MainActor
struct ChromeContextCapabilities {
  let activeTab: ChromeActiveTabCapability
  let listTabs: ChromeTabListCapability
  let activateTab: ChromeTabActivationCapability
  let youTubeFeed: ChromeYouTubeFeedCapability
  let openYouTubeVideo: ChromeYouTubeVideoOpenCapability
  private let youTubeSessionStore: YouTubeFeedSessionStore

  init(
    client: ChromeBridgeClient,
    nowMilliseconds: @escaping @Sendable () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    let youTubeSessionStore = YouTubeFeedSessionStore()
    self.youTubeSessionStore = youTubeSessionStore
    activeTab = ChromeActiveTabCapability(client: client)
    listTabs = ChromeTabListCapability(client: client)
    activateTab = ChromeTabActivationCapability(
      client: client,
      nowMilliseconds: nowMilliseconds
    )
    youTubeFeed = ChromeYouTubeFeedCapability(
      client: client,
      sessionStore: youTubeSessionStore,
      nowMilliseconds: nowMilliseconds
    )
    openYouTubeVideo = ChromeYouTubeVideoOpenCapability(
      client: client,
      sessionStore: youTubeSessionStore,
      nowMilliseconds: nowMilliseconds
    )
  }

  func clearYouTubeFeedSession() {
    youTubeSessionStore.clear()
  }

  var hasYouTubeFeedSession: Bool {
    youTubeSessionStore.snapshot != nil
  }

  static func unavailable() -> Self {
    Self(client: ChromeBridgeClient(exchange: .unavailable))
  }

  static func runtime(
    isPrimary: Bool,
    liveFactory: () -> Self = { .live() }
  ) -> Self {
    guard isPrimary else { return .unavailable() }
    return liveFactory()
  }
}

private func boundedTitle(_ title: String, maximumCharacters: Int = 160) -> String {
  guard title.count > maximumCharacters else { return title }
  return String(title.prefix(maximumCharacters - 1)) + "…"
}

private func chromeFailureMessage(_ error: Error) -> String {
  if error is CancellationError {
    return "The Chrome context request was canceled."
  }
  guard let error = error as? ChromeContextError else {
    return "Chrome context failed without exposing page data. Try again."
  }

  switch error {
  case .activationOutcomeUnknown:
    return
      "Chrome may have switched tabs, but Topher did not receive confirmation and will not retry automatically."
  case .bridgeUnavailable:
    return
      "Chrome isn’t connected. Open Topher Settings → General → Chrome and YouTube, finish Set Up, then reload the extension in Chrome."
  case .busy:
    return "Chrome context is busy. Wait a moment and try again."
  case .canceled:
    return "The Chrome context request was canceled."
  case .malformedResponse, .versionMismatch:
    return
      "Topher and the Chrome extension are incompatible or returned invalid data. Reinstall matching versions."
  case .responseTimedOut:
    return "Chrome context timed out. No broader context fallback was used."
  case .navigationOutcomeUnknown:
    return
      "Chrome may have opened the video, but Topher did not receive confirmation and will not retry automatically. Ask for the feed again before another open."
  case .provider(let failure):
    switch failure {
    case .activationOutcomeUnknown:
      return
        "Chrome may have switched tabs, but Topher did not receive confirmation and will not retry automatically."
    case .navigationOutcomeUnknown:
      return
        "Chrome may have opened the video, but Topher did not receive confirmation and will not retry automatically. Ask for the feed again before another open."
    case .staleTab, .targetNotFound:
      return "That Chrome tab changed or closed before activation. Ask again to refresh it."
    case .incognitoExcluded:
      return "Incognito tabs are intentionally excluded from Topher."
    case .excludedScheme:
      return "That Chrome tab uses a scheme Topher intentionally excludes."
    case .canceled:
      return "The Chrome context request was canceled."
    case .duplicateRequest:
      return "Chrome rejected a duplicate request without repeating the action."
    case .browserFailure:
      return "Chrome could not complete the bounded request. Try again."
    case .invalidTarget, .malformedRequest, .messageTooLarge, .unsupportedOperation,
      .unsupportedVersion:
      return "Topher and the Chrome extension rejected an invalid or incompatible request."
    case .noActiveTab:
      return "Chrome has no supported active non-incognito tab."
    case .staleYouTubeFeed, .youTubeFeedChanged:
      return "The YouTube feed changed. Ask “What’s on my YouTube feed?” again."
    case .unsupportedYouTubePage:
      return "Open YouTube Home in the active Chrome tab, then ask again."
    case .youTubeFeedUnavailable:
      return
        "Topher couldn’t read a bounded recommendation list. Let YouTube Home finish loading and try again."
    case .youTubePermissionRequired:
      return
        "Grant YouTube access from the Topher extension button in Chrome, then ask again. You can remove access there at any time."
    }
  }
}
