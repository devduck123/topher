import AppKit
import ApplicationServices
import TopherCore

struct FocusedTextElementID: Hashable, Sendable {
  let rawValue: UUID

  init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

struct FocusedTextRange: Equatable, Sendable {
  let location: Int
  let length: Int

  var endLocation: Int { location + length }

  init(location: Int, length: Int) {
    self.location = location
    self.length = length
  }
}

struct FocusedTextContext: Equatable, Sendable {
  let precedingText: String
  let followingText: String

  init(precedingText: String = "", followingText: String = "") {
    self.precedingText = precedingText
    self.followingText = followingText
  }
}

enum FocusedTextPreparationOutcome: Equatable, Sendable {
  case ready
  case noFocusedElement
  case secureField
  case unsupportedField
}

enum FocusedTextInsertionOutcome: Equatable, Sendable {
  case inserted(text: String, canUndo: Bool)
  case noPreparedTarget
  case focusChanged
  case selectionChanged
  case secureField
  case unsupportedField
  case failed
}

enum FocusedTextUndoOutcome: Equatable, Sendable {
  case restored
  case unavailable
  case focusChanged
  case secureField
  case selectionChanged
  case contentChanged
  case failed
}

@MainActor
struct FocusedTextInsertionEnvironment {
  let focusedElement: () -> FocusedTextElementID?
  let sameElement: (FocusedTextElementID, FocusedTextElementID) -> Bool
  let isSecure: (FocusedTextElementID) -> Bool
  let selectedText: (FocusedTextElementID) -> String?
  let selectedRange: (FocusedTextElementID) -> FocusedTextRange?
  let textContext: (FocusedTextElementID, FocusedTextRange) -> FocusedTextContext
  let canSetSelectedText: (FocusedTextElementID) -> Bool
  let canSetSelectedRange: (FocusedTextElementID) -> Bool
  let setSelectedText: (FocusedTextElementID, String) -> Bool
  let setSelectedRange: (FocusedTextElementID, FocusedTextRange) -> Bool
  let release: (FocusedTextElementID) -> Void

  static var live: Self {
    let registry = AccessibilityElementRegistry()
    return Self(
      focusedElement: { registry.focusedElement() },
      sameElement: { registry.sameElement($0, $1) },
      isSecure: { registry.isSecure($0) },
      selectedText: { registry.selectedText($0) },
      selectedRange: { registry.selectedRange($0) },
      textContext: { registry.textContext($1, on: $0) },
      canSetSelectedText: {
        registry.isSettable(kAXSelectedTextAttribute as CFString, on: $0)
      },
      canSetSelectedRange: {
        registry.isSettable(kAXSelectedTextRangeAttribute as CFString, on: $0)
      },
      setSelectedText: { registry.setSelectedText($1, on: $0) },
      setSelectedRange: { registry.setSelectedRange($1, on: $0) },
      release: { registry.release($0) }
    )
  }
}

/// Replaces only the current selection in the field captured at key-down.
///
/// The capability revalidates focus, selection, and secure-field state before
/// mutating anything. It never synthesizes Return or another submit action.
@MainActor
final class FocusedTextInsertionCapability {
  static let descriptor = CapabilityDescriptor(
    identifier: "focusedTextInsertion",
    access: .changesState,
    risk: .lowRiskReversible
  )

  private struct PreparedTarget {
    let element: FocusedTextElementID
    let selectedText: String
    let selectedRange: FocusedTextRange
    let textContext: FocusedTextContext
  }

  private struct UndoReceipt {
    let element: FocusedTextElementID
    let replacedText: String
    let insertedText: String
    let insertedRange: FocusedTextRange
    let expectedCaret: FocusedTextRange
  }

  private let environment: FocusedTextInsertionEnvironment
  private var preparedTarget: PreparedTarget?
  private var undoReceipt: UndoReceipt?

  private static let maximumSelectionUTF16Length = 16_384

  init(environment: FocusedTextInsertionEnvironment? = nil) {
    self.environment = environment ?? .live
  }

  var canUndo: Bool { undoReceipt != nil }

  func prepareTarget() -> FocusedTextPreparationOutcome {
    discardPreparedTarget()

    guard let element = environment.focusedElement() else {
      return .noFocusedElement
    }
    guard !environment.isSecure(element) else {
      environment.release(element)
      return .secureField
    }
    guard
      environment.canSetSelectedText(element),
      environment.canSetSelectedRange(element),
      let selectedRange = environment.selectedRange(element),
      selectedRange.location >= 0,
      selectedRange.length >= 0,
      selectedRange.location <= Int.max - selectedRange.length,
      selectedRange.endLocation <= Int.max - 2,
      selectedRange.length <= Self.maximumSelectionUTF16Length,
      let selectedText = environment.selectedText(element),
      (selectedText as NSString).length == selectedRange.length
    else {
      environment.release(element)
      return .unsupportedField
    }

    preparedTarget = PreparedTarget(
      element: element,
      selectedText: selectedText,
      selectedRange: selectedRange,
      textContext: environment.textContext(element, selectedRange)
    )
    return .ready
  }

  func discardPreparedTarget() {
    guard let preparedTarget else { return }
    environment.release(preparedTarget.element)
    self.preparedTarget = nil
  }

  /// Discards the prepared target and reports whether a failed transcription
  /// may be retained for explicit review. A target that became secure must not
  /// produce a preview or content-bearing diagnostic.
  func discardPreparedTargetForRecovery() -> Bool {
    guard let preparedTarget else { return true }
    let mayRetain = !environment.isSecure(preparedTarget.element)
    discardPreparedTarget()
    return mayRetain
  }

  func insert(_ text: DictationText) -> FocusedTextInsertionOutcome {
    guard let preparedTarget else { return .noPreparedTarget }
    self.preparedTarget = nil

    guard let focusedElement = environment.focusedElement() else {
      environment.release(preparedTarget.element)
      return .focusChanged
    }
    let focusMatches = environment.sameElement(preparedTarget.element, focusedElement)
    environment.release(focusedElement)
    guard focusMatches else {
      environment.release(preparedTarget.element)
      return .focusChanged
    }
    guard !environment.isSecure(preparedTarget.element) else {
      environment.release(preparedTarget.element)
      return .secureField
    }
    guard
      environment.selectedRange(preparedTarget.element) == preparedTarget.selectedRange,
      environment.selectedText(preparedTarget.element) == preparedTarget.selectedText,
      environment.textContext(preparedTarget.element, preparedTarget.selectedRange)
        == preparedTarget.textContext
    else {
      environment.release(preparedTarget.element)
      return .selectionChanged
    }
    guard
      environment.canSetSelectedText(preparedTarget.element),
      environment.canSetSelectedRange(preparedTarget.element)
    else {
      environment.release(preparedTarget.element)
      return .unsupportedField
    }

    let insertionText = Self.textForInsertion(text.value, context: preparedTarget.textContext)
    let insertionLength = (insertionText as NSString).length
    guard preparedTarget.selectedRange.location <= Int.max - insertionLength else {
      environment.release(preparedTarget.element)
      return .failed
    }
    guard environment.setSelectedText(preparedTarget.element, insertionText) else {
      environment.release(preparedTarget.element)
      return .failed
    }

    let insertedRange = FocusedTextRange(
      location: preparedTarget.selectedRange.location,
      length: insertionLength
    )
    let expectedCaret = FocusedTextRange(location: insertedRange.endLocation, length: 0)
    let movedCaret = environment.setSelectedRange(preparedTarget.element, expectedCaret)

    discardUndoReceipt()
    guard movedCaret else {
      environment.release(preparedTarget.element)
      return .inserted(text: insertionText, canUndo: false)
    }
    undoReceipt = UndoReceipt(
      element: preparedTarget.element,
      replacedText: preparedTarget.selectedText,
      insertedText: insertionText,
      insertedRange: insertedRange,
      expectedCaret: expectedCaret
    )
    return .inserted(text: insertionText, canUndo: true)
  }

  func undoLastInsertion() -> FocusedTextUndoOutcome {
    guard let undoReceipt else { return .unavailable }

    guard let focusedElement = environment.focusedElement() else {
      return .focusChanged
    }
    let focusMatches = environment.sameElement(undoReceipt.element, focusedElement)
    environment.release(focusedElement)
    guard focusMatches else { return .focusChanged }
    guard !environment.isSecure(undoReceipt.element) else {
      discardUndoReceipt()
      return .secureField
    }
    guard environment.selectedRange(undoReceipt.element) == undoReceipt.expectedCaret else {
      return .selectionChanged
    }
    guard environment.setSelectedRange(undoReceipt.element, undoReceipt.insertedRange) else {
      return .failed
    }
    guard environment.selectedText(undoReceipt.element) == undoReceipt.insertedText else {
      _ = environment.setSelectedRange(undoReceipt.element, undoReceipt.expectedCaret)
      return .contentChanged
    }
    guard environment.setSelectedText(undoReceipt.element, undoReceipt.replacedText) else {
      _ = environment.setSelectedRange(undoReceipt.element, undoReceipt.expectedCaret)
      return .failed
    }

    let restoredCaret = FocusedTextRange(
      location: undoReceipt.insertedRange.location + (undoReceipt.replacedText as NSString).length,
      length: 0
    )
    _ = environment.setSelectedRange(undoReceipt.element, restoredCaret)
    discardUndoReceipt()
    return .restored
  }

  private func discardUndoReceipt() {
    guard let undoReceipt else { return }
    environment.release(undoReceipt.element)
    self.undoReceipt = nil
  }

  private static func textForInsertion(
    _ text: String,
    context: FocusedTextContext
  ) -> String {
    var insertion = text
    if let preceding = context.precedingText.last,
      let first = insertion.first,
      isWordLike(preceding),
      isWordLike(first)
    {
      insertion.insert(" ", at: insertion.startIndex)
    }
    if let following = context.followingText.first,
      let last = insertion.last,
      isWordLike(following),
      isWordLike(last)
    {
      insertion.append(" ")
    }
    return insertion
  }

  private static func isWordLike(_ character: Character) -> Bool {
    character == "_"
      || character.unicodeScalars.allSatisfy {
        CharacterSet.alphanumerics.contains($0)
      }
  }
}

@MainActor
private final class AccessibilityElementRegistry {
  private let systemWideElement = AXUIElementCreateSystemWide()
  private var elements: [FocusedTextElementID: AXUIElement] = [:]

  func focusedElement() -> FocusedTextElementID? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        systemWideElement,
        kAXFocusedUIElementAttribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }

    let id = FocusedTextElementID()
    elements[id] = unsafeDowncast(value, to: AXUIElement.self)
    return id
  }

  func sameElement(_ lhs: FocusedTextElementID, _ rhs: FocusedTextElementID) -> Bool {
    guard let lhs = elements[lhs], let rhs = elements[rhs] else { return false }
    return CFEqual(lhs, rhs)
  }

  func isSecure(_ id: FocusedTextElementID) -> Bool {
    guard let element = elements[id] else { return true }

    if copyStringAttribute(kAXSubroleAttribute as CFString, from: element)
      == kAXSecureTextFieldSubrole as String
    {
      return true
    }

    var value: CFTypeRef?
    let protectedContentAttribute =
      NSAccessibility.Attribute.containsProtectedContent.rawValue as CFString
    guard
      AXUIElementCopyAttributeValue(element, protectedContentAttribute, &value) == .success,
      let number = value as? NSNumber
    else { return false }
    return number.boolValue
  }

  func selectedText(_ id: FocusedTextElementID) -> String? {
    guard let element = elements[id] else { return nil }
    return copyStringAttribute(kAXSelectedTextAttribute as CFString, from: element)
  }

  func selectedRange(_ id: FocusedTextElementID) -> FocusedTextRange? {
    guard let element = elements[id] else { return nil }
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        element,
        kAXSelectedTextRangeAttribute as CFString,
        &value
      ) == .success,
      let value,
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }

    let axValue = unsafeDowncast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cfRange else { return nil }
    var range = CFRange()
    guard AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return FocusedTextRange(location: range.location, length: range.length)
  }

  func textContext(
    _ range: FocusedTextRange,
    on id: FocusedTextElementID
  ) -> FocusedTextContext {
    guard let element = elements[id] else { return FocusedTextContext() }

    let precedingStart = max(0, range.location - 2)
    let precedingLength = range.location - precedingStart
    let precedingText =
      string(
        for: FocusedTextRange(location: precedingStart, length: precedingLength),
        in: element
      ) ?? ""
    let followingText =
      string(
        for: FocusedTextRange(location: range.endLocation, length: 2),
        in: element
      ) ?? ""
    return FocusedTextContext(
      precedingText: precedingText,
      followingText: followingText
    )
  }

  func isSettable(_ attribute: CFString, on id: FocusedTextElementID) -> Bool {
    guard let element = elements[id] else { return false }
    var settable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
      return false
    }
    return settable.boolValue
  }

  func setSelectedText(_ text: String, on id: FocusedTextElementID) -> Bool {
    guard let element = elements[id] else { return false }
    return AXUIElementSetAttributeValue(
      element,
      kAXSelectedTextAttribute as CFString,
      text as CFString
    )
      == .success
  }

  func setSelectedRange(_ range: FocusedTextRange, on id: FocusedTextElementID) -> Bool {
    guard let element = elements[id] else { return false }
    var cfRange = CFRange(location: range.location, length: range.length)
    guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
    return AXUIElementSetAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      value
    ) == .success
  }

  func release(_ id: FocusedTextElementID) {
    elements[id] = nil
  }

  private func copyStringAttribute(
    _ attribute: CFString,
    from element: AXUIElement
  ) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
      return nil
    }
    return value as? String
  }

  private func string(
    for range: FocusedTextRange,
    in element: AXUIElement
  ) -> String? {
    guard range.length > 0 else { return "" }
    var cfRange = CFRange(location: range.location, length: range.length)
    guard let parameter = AXValueCreate(.cfRange, &cfRange) else { return nil }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXStringForRangeParameterizedAttribute as CFString,
        parameter,
        &value
      ) == .success
    else { return nil }
    return value as? String
  }
}
