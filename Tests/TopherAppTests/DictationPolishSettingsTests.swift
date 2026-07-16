import Foundation
import XCTest

@testable import TopherApp

final class DictationPolishSettingsTests: XCTestCase {
  func testDefaultsOnAndPreservesExplicitOptOut() throws {
    let suiteName = "TopherDictationPolishSettingsTests-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    XCTAssertTrue(DictationPolishSettings.currentValue(in: defaults))

    defaults.set(false, forKey: DictationPolishSettings.preferenceKey)
    XCTAssertFalse(DictationPolishSettings.currentValue(in: defaults))

    defaults.set(true, forKey: DictationPolishSettings.preferenceKey)
    XCTAssertTrue(DictationPolishSettings.currentValue(in: defaults))
  }
}
