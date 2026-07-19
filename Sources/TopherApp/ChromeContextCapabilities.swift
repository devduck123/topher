import Foundation
import OSLog
import TopherCore

enum ChromeContextError: Error, Equatable, Sendable {
  case activationOutcomeUnknown
  case bridgeUnavailable
  case busy
  case canceled
  case malformedResponse
  case provider(ChromeBridgeFailureCode)
  case responseTimedOut
  case versionMismatch
}

struct ChromeTabList: Equatable, Sendable {
  let tabs: [ChromeTabSnapshot]
  let excludedTabCount: Int
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
  static let standardActivationTimeout: Duration = .seconds(3)
  static let maximumConcurrentRequests = 4

  private let exchange: ChromeBridgeExchange
  private let readTimeout: Duration
  private let activationTimeout: Duration
  private let maximumConcurrentRequests: Int
  private var inFlightRequestIDs = Set<UUID>()

  init(
    exchange: ChromeBridgeExchange,
    readTimeout: Duration = standardReadTimeout,
    activationTimeout: Duration = standardActivationTimeout,
    maximumConcurrentRequests: Int = maximumConcurrentRequests
  ) {
    self.exchange = exchange
    self.readTimeout = readTimeout
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
      response.excludedTabCount == nil,
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
      let wireTabs = response.tabs,
      wireTabs.count <= maximumCount,
      let excludedTabCount = response.excludedTabCount,
      excludedTabCount >= 0
    else {
      throw responseError(response)
    }

    let tabs = wireTabs.compactMap(\.validatedSnapshot)
    guard tabs.count == wireTabs.count else {
      throw ChromeContextError.malformedResponse
    }
    return ChromeTabList(tabs: tabs, excludedTabCount: excludedTabCount)
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
        response.excludedTabCount == nil
      else {
        throw responseError(response)
      }
    } catch ChromeContextError.responseTimedOut {
      // Activation is never retried after dispatch: a lost reply is an unknown
      // outcome, not permission to possibly run the mutation again.
      throw ChromeContextError.activationOutcomeUnknown
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

  init(
    client: ChromeBridgeClient,
    nowMilliseconds: @escaping @Sendable () -> Int64 = {
      Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    }
  ) {
    activeTab = ChromeActiveTabCapability(client: client)
    listTabs = ChromeTabListCapability(client: client)
    activateTab = ChromeTabActivationCapability(
      client: client,
      nowMilliseconds: nowMilliseconds
    )
  }

  static func unavailable() -> Self {
    Self(client: ChromeBridgeClient(exchange: .unavailable))
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
      "Chrome context is unavailable. Start Chrome, load Topher's extension, and check native-host registration."
  case .busy:
    return "Chrome context is busy. Wait a moment and try again."
  case .canceled:
    return "The Chrome context request was canceled."
  case .malformedResponse, .versionMismatch:
    return
      "Topher and the Chrome extension are incompatible or returned invalid data. Reinstall matching versions."
  case .responseTimedOut:
    return "Chrome context timed out. No broader context fallback was used."
  case .provider(let failure):
    switch failure {
    case .activationOutcomeUnknown:
      return
        "Chrome may have switched tabs, but Topher did not receive confirmation and will not retry automatically."
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
      return "Chrome could not complete the bounded tab request. Try again."
    case .invalidTarget, .malformedRequest, .messageTooLarge, .unsupportedOperation,
      .unsupportedVersion:
      return "Topher and the Chrome extension rejected an invalid or incompatible request."
    case .noActiveTab:
      return "Chrome has no supported active non-incognito tab."
    }
  }
}
