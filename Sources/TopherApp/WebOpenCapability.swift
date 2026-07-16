import AppKit
import TopherCore

/// The smallest test seam around opening a validated web URL.
@MainActor
struct WebWorkspace {
  let open: (URL) async throws -> Void

  static var live: Self {
    let workspace = NSWorkspace.shared
    return Self(
      open: { url in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        _ = try await workspace.open(url, configuration: configuration)
      }
    )
  }
}

@MainActor
struct BrowserRouteWorkspace {
  let applicationURL: (String) -> URL?
  let openURLs: ([URL], URL) async throws -> Void

  static var live: Self {
    let workspace = NSWorkspace.shared
    return Self(
      applicationURL: { workspace.urlForApplication(withBundleIdentifier: $0) },
      openURLs: { urls, applicationURL in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.promptsUserIfNeeded = true
        try await withCheckedThrowingContinuation {
          (continuation: CheckedContinuation<Void, any Error>) in
          workspace.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
          ) { _, error in
            if let error {
              continuation.resume(throwing: error)
            } else {
              continuation.resume(returning: ())
            }
          }
        }
      }
    )
  }
}

@MainActor
final class BrowserRouteOpenCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "browserRouteNavigation",
    access: .changesState,
    risk: .lowRiskReversible
  )

  private let workspace: BrowserRouteWorkspace

  init(workspace: BrowserRouteWorkspace? = nil) {
    self.workspace = workspace ?? .live
  }

  func execute(_ target: BrowserRouteTarget) async -> ActionOutcome {
    guard
      let applicationURL = workspace.applicationURL(target.browser.bundleIdentifier),
      let routeURL = routeURL(for: target)
    else {
      return .failed(message: "Could not open \(target.displayName).")
    }

    do {
      try await workspace.openURLs([routeURL], applicationURL)
      return .succeeded(message: "Opened \(target.displayName).")
    } catch {
      return .failed(message: "Could not open \(target.displayName).")
    }
  }

  private func routeURL(for target: BrowserRouteTarget) -> URL? {
    switch target {
    case .chromeExtensions:
      URL(string: "chrome://extensions/")
    }
  }
}

@MainActor
final class WebOpenCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "webNavigation",
    access: .changesState,
    risk: .sensitive
  )

  private let workspace: WebWorkspace

  init(workspace: WebWorkspace? = nil) {
    self.workspace = workspace ?? .live
  }

  func execute(_ target: WebsiteTarget) async -> ActionOutcome {
    guard let url = homepageURL(for: target) else {
      return .failed(message: "Could not open \(target.displayName).")
    }

    do {
      try await workspace.open(url)
      return .succeeded(message: "Opened \(target.displayName).")
    } catch {
      return .failed(message: "Could not open \(target.displayName).")
    }
  }

  func execute(_ domain: HTTPSDomain) async -> ActionOutcome {
    do {
      try await workspace.open(domain.url)
      return .succeeded(message: "Opened \(domain.host).")
    } catch {
      return .failed(message: "Could not open \(domain.host).")
    }
  }

  func execute(provider: SearchProvider, query: SearchQuery) async -> ActionOutcome {
    guard let url = searchURL(provider: provider, query: query) else {
      return .failed(message: "Could not search \(provider.displayName).")
    }

    do {
      try await workspace.open(url)
      return .succeeded(message: "Searched \(provider.displayName).")
    } catch {
      return .failed(message: "Could not search \(provider.displayName).")
    }
  }

  func searchUnknownDestination(_ query: SearchQuery) async -> ActionOutcome {
    guard let url = searchURL(provider: .google, query: query) else {
      return .failed(message: "I couldn't search for that destination.")
    }

    do {
      try await workspace.open(url)
      return .succeeded(
        message: "No matching app or website was found, so I searched Google instead."
      )
    } catch {
      return .failed(message: "I couldn't search for that destination.")
    }
  }

  private func homepageURL(for target: WebsiteTarget) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = target.canonicalHost
    components.path = "/"
    return components.url
  }

  private func searchURL(provider: SearchProvider, query: SearchQuery) -> URL? {
    var components = URLComponents()
    components.scheme = "https"

    switch provider {
    case .google:
      components.host = "www.google.com"
      components.path = "/search"
      components.queryItems = [URLQueryItem(name: "q", value: query.value)]
    case .youtube:
      components.host = "www.youtube.com"
      components.path = "/results"
      components.queryItems = [URLQueryItem(name: "search_query", value: query.value)]
    }

    components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(
      of: "+",
      with: "%2B"
    )

    return components.url
  }
}
