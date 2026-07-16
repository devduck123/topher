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
  var nsRange: NSRange { NSRange(location: location, length: length) }

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
  case inserted(FocusedTextInsertionResult)
  case mutationNotObserved(FocusedTextInsertionEvidence)
  case mutationUnverified(FocusedTextInsertionEvidence)
  case noPreparedTarget
  case focusChanged
  case selectionChanged
  case secureField
  case unsupportedField
  case failed
}

enum FocusedTextTargetRole: String, Codable, Equatable, Sendable {
  case textArea
  case textField
  case webArea
  case other
}

enum FocusedTextInsertionMethod: String, Codable, Equatable, Sendable {
  case selectedText
  case wholeValue
}

enum FocusedTextInsertionVerification: String, Codable, Equatable, Sendable {
  case contentAndCaret
  case contentOnly
  case notObserved
  case unavailable
}

struct FocusedTextTargetProfile: Codable, Equatable, Sendable {
  let role: FocusedTextTargetRole
  let canSetSelectedText: Bool
  let canSetSelectedRange: Bool
  let canSetValue: Bool
}

struct FocusedTextInsertionEvidence: Codable, Equatable, Sendable {
  let method: FocusedTextInsertionMethod
  let verification: FocusedTextInsertionVerification
  let target: FocusedTextTargetProfile
}

struct FocusedTextInsertionResult: Equatable, Sendable {
  let text: String
  let canUndo: Bool
  let evidence: FocusedTextInsertionEvidence
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
  let processIdentifier: (FocusedTextElementID) -> pid_t?
  let isSecure: (FocusedTextElementID) -> Bool
  let role: (FocusedTextElementID) -> FocusedTextTargetRole
  let hasWebAreaAncestor: (FocusedTextElementID) -> Bool
  let selectedText: (FocusedTextElementID) -> String?
  let selectedRange: (FocusedTextElementID) -> FocusedTextRange?
  let value: (FocusedTextElementID) -> String?
  let text: (FocusedTextElementID, FocusedTextRange) -> String?
  let textContext: (FocusedTextElementID, FocusedTextRange) -> FocusedTextContext
  let canSetSelectedText: (FocusedTextElementID) -> Bool
  let canSetSelectedRange: (FocusedTextElementID) -> Bool
  let canSetValue: (FocusedTextElementID) -> Bool
  let setSelectedText: (FocusedTextElementID, String) -> Bool
  let setSelectedRange: (FocusedTextElementID, FocusedTextRange) -> Bool
  let setValue: (FocusedTextElementID, String) -> Bool
  let waitForMutation: (Duration) async -> Void
  let release: (FocusedTextElementID) -> Void

  static var live: Self {
    let registry = AccessibilityElementRegistry()
    return Self(
      focusedElement: { registry.focusedElement() },
      sameElement: { registry.sameElement($0, $1) },
      processIdentifier: { registry.processIdentifier($0) },
      isSecure: { registry.isSecure($0) },
      role: { registry.role($0) },
      hasWebAreaAncestor: { registry.hasWebAreaAncestor($0) },
      selectedText: { registry.selectedText($0) },
      selectedRange: { registry.selectedRange($0) },
      value: { registry.value($0) },
      text: { registry.text($1, on: $0) },
      textContext: { registry.textContext($1, on: $0) },
      canSetSelectedText: {
        registry.isSettable(kAXSelectedTextAttribute as CFString, on: $0)
      },
      canSetSelectedRange: {
        registry.isSettable(kAXSelectedTextRangeAttribute as CFString, on: $0)
      },
      canSetValue: {
        registry.isSettable(kAXValueAttribute as CFString, on: $0)
      },
      setSelectedText: { registry.setSelectedText($1, on: $0) },
      setSelectedRange: { registry.setSelectedRange($1, on: $0) },
      setValue: { registry.setValue($1, on: $0) },
      waitForMutation: { duration in
        try? await Task.sleep(for: duration)
      },
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
    let processIdentifier: pid_t
    let profile: FocusedTextTargetProfile
    let selectedText: String
    let selectedRange: FocusedTextRange
    let textContext: FocusedTextContext
    let value: String?
    let permitsWholeValueMutation: Bool
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
  private static let maximumWholeValueUTF16Length = 16_384
  private static let maximumWebComposerUTF16Length = 4_096
  private static let verificationRetryDelays: [Duration] = [
    .milliseconds(10), .milliseconds(20), .milliseconds(40), .milliseconds(80),
  ]

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
    let profile = FocusedTextTargetProfile(
      role: environment.role(element),
      canSetSelectedText: environment.canSetSelectedText(element),
      canSetSelectedRange: environment.canSetSelectedRange(element),
      canSetValue: environment.canSetValue(element)
    )
    guard
      profile.canSetSelectedRange,
      profile.canSetSelectedText || profile.canSetValue
    else {
      environment.release(element)
      return .unsupportedField
    }
    guard
      let processIdentifier = environment.processIdentifier(element),
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

    let value = Self.validatedWholeValue(
      environment.value(element),
      selectedRange: selectedRange,
      selectedText: selectedText
    )
    let permitsWholeValueMutation = Self.permitsWholeValueMutation(
      profile: profile,
      value: value,
      selectedRange: selectedRange,
      hasWebAreaAncestor: environment.hasWebAreaAncestor(element)
    )
    guard profile.canSetSelectedText || permitsWholeValueMutation else {
      environment.release(element)
      return .unsupportedField
    }

    preparedTarget = PreparedTarget(
      element: element,
      processIdentifier: processIdentifier,
      profile: profile,
      selectedText: selectedText,
      selectedRange: selectedRange,
      textContext: environment.textContext(element, selectedRange),
      value: value,
      permitsWholeValueMutation: permitsWholeValueMutation
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

  func insert(_ text: DictationText) async -> FocusedTextInsertionOutcome {
    guard let preparedTarget else { return .noPreparedTarget }
    self.preparedTarget = nil

    guard let focusedElement = environment.focusedElement() else {
      environment.release(preparedTarget.element)
      return .focusChanged
    }
    let focusMatches =
      environment.sameElement(preparedTarget.element, focusedElement)
      && environment.processIdentifier(focusedElement) == preparedTarget.processIdentifier
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
    guard environment.canSetSelectedRange(preparedTarget.element) else {
      environment.release(preparedTarget.element)
      return .unsupportedField
    }

    let insertionText = Self.textForInsertion(text.value, context: preparedTarget.textContext)
    let insertionLength = (insertionText as NSString).length
    guard preparedTarget.selectedRange.location <= Int.max - insertionLength else {
      environment.release(preparedTarget.element)
      return .failed
    }
    let insertedRange = FocusedTextRange(
      location: preparedTarget.selectedRange.location,
      length: insertionLength
    )
    let expectedCaret = FocusedTextRange(location: insertedRange.endLocation, length: 0)
    let expectedValue = preparedTarget.value.flatMap {
      Self.replacingSelection(
        in: $0,
        range: preparedTarget.selectedRange,
        with: insertionText
      )
    }

    discardUndoReceipt()

    if let expectedValue, preparedTarget.permitsWholeValueMutation {
      return await insertWholeValue(
        expectedValue,
        preparedTarget: preparedTarget,
        insertionText: insertionText,
        insertedRange: insertedRange,
        expectedCaret: expectedCaret
      )
    }

    if preparedTarget.profile.canSetSelectedText,
      environment.canSetSelectedText(preparedTarget.element),
      environment.setSelectedText(preparedTarget.element, insertionText)
    {
      _ = environment.setSelectedRange(preparedTarget.element, expectedCaret)
      let verification = await verifyMutation(
        preparedTarget,
        insertedText: insertionText,
        insertedRange: insertedRange,
        expectedCaret: expectedCaret,
        expectedValue: expectedValue
      )
      let evidence = FocusedTextInsertionEvidence(
        method: .selectedText,
        verification: verification.publicValue,
        target: preparedTarget.profile
      )

      switch verification {
      case .verified(let level):
        let canUndo = level == .contentAndCaret
        if canUndo {
          undoReceipt = UndoReceipt(
            element: preparedTarget.element,
            replacedText: preparedTarget.selectedText,
            insertedText: insertionText,
            insertedRange: insertedRange,
            expectedCaret: expectedCaret
          )
        } else {
          environment.release(preparedTarget.element)
        }
        return .inserted(
          FocusedTextInsertionResult(
            text: insertionText,
            canUndo: canUndo,
            evidence: evidence
          )
        )
      case .notObserved:
        environment.release(preparedTarget.element)
        return .mutationNotObserved(evidence)
      case .unavailable:
        environment.release(preparedTarget.element)
        return .mutationUnverified(evidence)
      case .secureField:
        environment.release(preparedTarget.element)
        return .secureField
      }
    }

    environment.release(preparedTarget.element)
    return .failed
  }

  private enum MutationVerificationResult: Equatable {
    case verified(FocusedTextInsertionVerification)
    case notObserved
    case unavailable
    case secureField

    var publicValue: FocusedTextInsertionVerification {
      switch self {
      case .verified(let level):
        level
      case .notObserved:
        .notObserved
      case .unavailable, .secureField:
        .unavailable
      }
    }
  }

  private func insertWholeValue(
    _ expectedValue: String,
    preparedTarget: PreparedTarget,
    insertionText: String,
    insertedRange: FocusedTextRange,
    expectedCaret: FocusedTextRange
  ) async -> FocusedTextInsertionOutcome {
    let evidence: (FocusedTextInsertionVerification) -> FocusedTextInsertionEvidence = {
      verification in
      FocusedTextInsertionEvidence(
        method: .wholeValue,
        verification: verification,
        target: preparedTarget.profile
      )
    }

    guard !environment.isSecure(preparedTarget.element) else {
      environment.release(preparedTarget.element)
      return .secureField
    }
    guard let focusedElement = environment.focusedElement() else {
      environment.release(preparedTarget.element)
      return .focusChanged
    }
    let focusMatches =
      environment.sameElement(preparedTarget.element, focusedElement)
      && environment.processIdentifier(focusedElement) == preparedTarget.processIdentifier
    environment.release(focusedElement)
    guard focusMatches else {
      environment.release(preparedTarget.element)
      return .focusChanged
    }
    guard
      environment.canSetValue(preparedTarget.element),
      environment.value(preparedTarget.element) == preparedTarget.value,
      (expectedValue as NSString).length <= Self.maximumWholeValueUTF16Length
    else {
      environment.release(preparedTarget.element)
      return .selectionChanged
    }
    guard environment.setValue(preparedTarget.element, expectedValue) else {
      environment.release(preparedTarget.element)
      return .failed
    }

    _ = environment.setSelectedRange(preparedTarget.element, expectedCaret)
    let verification = await verifyMutation(
      preparedTarget,
      insertedText: insertionText,
      insertedRange: insertedRange,
      expectedCaret: expectedCaret,
      expectedValue: expectedValue
    )
    environment.release(preparedTarget.element)

    switch verification {
    case .verified(let level):
      return .inserted(
        FocusedTextInsertionResult(
          text: insertionText,
          canUndo: false,
          evidence: evidence(level)
        )
      )
    case .notObserved:
      return .mutationNotObserved(evidence(.notObserved))
    case .unavailable:
      return .mutationUnverified(evidence(.unavailable))
    case .secureField:
      return .secureField
    }
  }

  private func verifyMutation(
    _ preparedTarget: PreparedTarget,
    insertedText: String,
    insertedRange: FocusedTextRange,
    expectedCaret: FocusedTextRange,
    expectedValue: String?
  ) async -> MutationVerificationResult {
    var readMutationState = false

    for attempt in 0...Self.verificationRetryDelays.count {
      guard !Task.isCancelled else { return .unavailable }
      if attempt > 0 {
        await environment.waitForMutation(Self.verificationRetryDelays[attempt - 1])
      }
      guard !environment.isSecure(preparedTarget.element) else {
        return .secureField
      }
      guard let focusedElement = environment.focusedElement() else { continue }
      let focusMatches =
        environment.sameElement(preparedTarget.element, focusedElement)
        && environment.processIdentifier(focusedElement) == preparedTarget.processIdentifier
      environment.release(focusedElement)
      guard focusMatches else { return .unavailable }

      let insertedRangeText = environment.text(preparedTarget.element, insertedRange)
      let currentValue = expectedValue.map { _ in environment.value(preparedTarget.element) }
      readMutationState = readMutationState || insertedRangeText != nil || currentValue != nil
      let contentMatches =
        insertedRangeText == insertedText
        || (expectedValue != nil && currentValue == expectedValue)
      guard contentMatches else { continue }

      return .verified(
        environment.selectedRange(preparedTarget.element) == expectedCaret
          ? .contentAndCaret
          : .contentOnly
      )
    }

    return readMutationState ? .notObserved : .unavailable
  }

  private static func validatedWholeValue(
    _ value: String?,
    selectedRange: FocusedTextRange,
    selectedText: String
  ) -> String? {
    guard let value else { return nil }
    let nsValue = value as NSString
    guard
      nsValue.length <= maximumWholeValueUTF16Length,
      selectedRange.endLocation <= nsValue.length,
      nsValue.substring(with: selectedRange.nsRange) == selectedText
    else { return nil }
    return value
  }

  private static func permitsWholeValueMutation(
    profile: FocusedTextTargetProfile,
    value: String?,
    selectedRange: FocusedTextRange,
    hasWebAreaAncestor: Bool
  ) -> Bool {
    guard profile.canSetValue, let value else { return false }
    guard profile.role == .textField || profile.role == .textArea else { return false }
    let length = (value as NSString).length
    let isBoundedPlainWebAppend =
      profile.role == .textArea
      && hasWebAreaAncestor
      && length > 0
      && length <= maximumWebComposerUTF16Length
      && selectedRange.location == length
      && selectedRange.length == 0
      && value.rangeOfCharacter(from: .newlines) == nil
      && !value.contains("\u{FFFC}")
    return profile.role == .textField
      || length == 0
      || (selectedRange.location == 0 && selectedRange.length == length)
      || isBoundedPlainWebAppend
  }

  private static func replacingSelection(
    in value: String,
    range: FocusedTextRange,
    with text: String
  ) -> String? {
    let nsValue = value as NSString
    guard range.endLocation <= nsValue.length else { return nil }
    let result = nsValue.replacingCharacters(in: range.nsRange, with: text)
    return (result as NSString).length <= maximumWholeValueUTF16Length ? result : nil
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
      isWordLike(preceding) || sentenceBoundaryPunctuation.contains(preceding),
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

  private static let sentenceBoundaryPunctuation: Set<Character> = [
    ",", ".", ":", ";", "!", "?",
  ]
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

  func processIdentifier(_ id: FocusedTextElementID) -> pid_t? {
    guard let element = elements[id] else { return nil }
    var processIdentifier = pid_t()
    guard AXUIElementGetPid(element, &processIdentifier) == .success else { return nil }
    return processIdentifier
  }

  func role(_ id: FocusedTextElementID) -> FocusedTextTargetRole {
    guard let element = elements[id] else { return .other }
    let role = copyStringAttribute(kAXRoleAttribute as CFString, from: element)
    if role == kAXTextFieldRole {
      return .textField
    }
    if role == kAXTextAreaRole {
      return .textArea
    }
    if role == "AXWebArea" {
      return .webArea
    }
    return .other
  }

  func hasWebAreaAncestor(_ id: FocusedTextElementID) -> Bool {
    guard var current = elements[id] else { return false }

    for _ in 0..<12 {
      if copyStringAttribute(kAXRoleAttribute as CFString, from: current) == "AXWebArea" {
        return true
      }
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(
          current,
          kAXParentAttribute as CFString,
          &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
      else { return false }
      let parent = unsafeDowncast(value, to: AXUIElement.self)
      guard !CFEqual(current, parent) else { return false }
      current = parent
    }
    return false
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

  func value(_ id: FocusedTextElementID) -> String? {
    guard let element = elements[id] else { return nil }
    return copyStringAttribute(kAXValueAttribute as CFString, from: element)
  }

  func text(_ range: FocusedTextRange, on id: FocusedTextElementID) -> String? {
    guard let element = elements[id] else { return nil }
    return string(for: range, in: element)
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
      ) ?? stringFromValue(range: .init(location: precedingStart, length: precedingLength), id: id)
      ?? ""
    let followingText =
      string(
        for: FocusedTextRange(location: range.endLocation, length: 2),
        in: element
      ) ?? stringFromValue(
        range: .init(location: range.endLocation, length: 2),
        id: id
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

  func setValue(_ value: String, on id: FocusedTextElementID) -> Bool {
    guard let element = elements[id] else { return false }
    return AXUIElementSetAttributeValue(
      element,
      kAXValueAttribute as CFString,
      value as CFString
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

  private func stringFromValue(
    range: FocusedTextRange,
    id: FocusedTextElementID
  ) -> String? {
    guard let value = value(id) else { return nil }
    let nsValue = value as NSString
    guard range.endLocation <= nsValue.length else { return nil }
    return nsValue.substring(with: range.nsRange)
  }
}
