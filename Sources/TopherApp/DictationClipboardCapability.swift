import AppKit
import TopherCore

@MainActor
struct DictationClipboardEnvironment {
  let writeString: (String) -> Bool

  static var live: Self {
    let pasteboard = NSPasteboard.general
    return Self(writeString: { text in
      pasteboard.clearContents()
      return pasteboard.setString(text, forType: .string)
    })
  }
}

@MainActor
final class DictationClipboardCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "copyDictationToClipboard",
    access: .changesState,
    risk: .lowRiskReversible
  )

  private let environment: DictationClipboardEnvironment

  init(environment: DictationClipboardEnvironment? = nil) {
    self.environment = environment ?? .live
  }

  func copy(_ text: DictationText) -> Bool {
    environment.writeString(text.value)
  }
}
