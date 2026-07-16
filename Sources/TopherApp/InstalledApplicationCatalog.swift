import Foundation
import TopherCore

/// Discovers launchable applications from bounded, conventional macOS
/// application directories. The catalog is captured once per Topher launch so
/// resolution stays deterministic for the whole session.
struct InstalledApplicationCatalog: Sendable {
  let applications: [InstalledApplicationTarget]

  static func discover(
    roots: [URL] = defaultRoots,
    fileManager: FileManager = .default
  ) -> Self {
    var applicationsByBundleIdentifier: [String: InstalledApplicationTarget] = [:]

    for applicationURL in applicationURLs(in: roots, fileManager: fileManager) {
      guard
        let bundle = Bundle(url: applicationURL),
        let bundleIdentifier = bundle.bundleIdentifier?.trimmingCharacters(
          in: .whitespacesAndNewlines
        ),
        isValidBundleIdentifier(bundleIdentifier)
      else { continue }

      let filename = applicationURL.deletingPathExtension().lastPathComponent
      let displayName =
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? filename
      let cleanedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cleanedDisplayName.isEmpty else { continue }

      var aliases: Set<String> = [cleanedDisplayName, filename]
      for suffix in [" Desktop", " App"] {
        if cleanedDisplayName.hasSuffix(suffix) {
          aliases.insert(String(cleanedDisplayName.dropLast(suffix.count)))
        }
      }

      if applicationsByBundleIdentifier[bundleIdentifier] == nil {
        applicationsByBundleIdentifier[bundleIdentifier] = InstalledApplicationTarget(
          displayName: cleanedDisplayName,
          bundleIdentifier: bundleIdentifier,
          aliases: aliases
        )
      }
    }

    return Self(
      applications: applicationsByBundleIdentifier.values.sorted {
        let order = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
        if order == .orderedSame {
          return $0.bundleIdentifier < $1.bundleIdentifier
        }
        return order == .orderedAscending
      }
    )
  }

  private static var defaultRoots: [URL] {
    let fileManager = FileManager.default
    return [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications", isDirectory: true),
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent(
        "Applications",
        isDirectory: true
      ),
    ]
  }

  private static func applicationURLs(
    in roots: [URL],
    fileManager: FileManager
  ) -> [URL] {
    var result: [URL] = []

    for root in roots {
      guard
        (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
      else { continue }
      guard
        let firstLevel = try? fileManager.contentsOfDirectory(
          at: root,
          includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
          options: [.skipsHiddenFiles]
        )
      else { continue }

      for candidate in firstLevel {
        if candidate.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
          guard
            (try? candidate.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink)
              != true
          else { continue }
          result.append(candidate)
          continue
        }

        guard
          let values = try? candidate.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
          ),
          values.isDirectory == true,
          values.isSymbolicLink != true,
          let secondLevel = try? fileManager.contentsOfDirectory(
            at: candidate,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
          )
        else { continue }

        result.append(contentsOf: contentsOfApplicationDirectory(secondLevel))
      }
    }

    return result
  }

  private static func contentsOfApplicationDirectory(_ urls: [URL]) -> [URL] {
    urls.filter {
      $0.pathExtension.caseInsensitiveCompare("app") == .orderedSame
        && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
    }
  }

  private static func isValidBundleIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty, value.utf8.count <= 255 else { return false }
    let components = value.split(separator: ".", omittingEmptySubsequences: false)
    guard components.count >= 2 else { return false }
    return components.allSatisfy { component in
      !component.isEmpty
        && component.allSatisfy { character in
          character.isASCII && (character.isLetter || character.isNumber || character == "-")
        }
    }
  }
}
