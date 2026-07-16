import Foundation

enum DictationPolishSettings {
  static let preferenceKey = "dictation.conservativePolishEnabled"
  static let defaultEnabled = true

  static func currentValue(in defaults: UserDefaults = .standard) -> Bool {
    guard defaults.object(forKey: preferenceKey) != nil else {
      return defaultEnabled
    }
    return defaults.bool(forKey: preferenceKey)
  }
}
