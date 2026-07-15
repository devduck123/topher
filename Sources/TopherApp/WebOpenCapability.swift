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

  private func homepageURL(for target: WebsiteTarget) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = host(for: target)
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

  private func host(for target: WebsiteTarget) -> String {
    switch target {
    case .google:
      "www.google.com"
    case .youtube:
      "www.youtube.com"
    }
  }
}
