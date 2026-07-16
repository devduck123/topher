import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class FocusedTextInsertionCapabilityTests: XCTestCase {
  func testDeclaresItsAuthority() {
    XCTAssertEqual(FocusedTextInsertionCapability.descriptor.access, .changesState)
    XCTAssertEqual(FocusedTextInsertionCapability.descriptor.risk, .lowRiskReversible)
  }

  func testInsertsByReplacingCapturedSelectionAndMovesCaret() throws {
    let harness = FocusedTextHarness(
      content: "hello world", selection: .init(location: 6, length: 5))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(
      capability.insert(try DictationText("Topher")),
      .inserted(text: "Topher", canUndo: true)
    )
    XCTAssertEqual(harness.content, "hello Topher")
    XCTAssertEqual(harness.selection, FocusedTextRange(location: 12, length: 0))
    XCTAssertTrue(capability.canUndo)
  }

  func testRejectsSecureFieldBeforeReadingOrWritingText() {
    let harness = FocusedTextHarness(content: "secret", selection: .init(location: 6, length: 0))
    harness.isSecure = true
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .secureField)
    XCTAssertEqual(harness.selectedTextReadCount, 0)
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testRecoveryDiscardRefusesRetentionWhenPreparedFieldBecomesSecure() throws {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    let selectedTextReadCount = harness.selectedTextReadCount

    harness.isSecure = true

    XCTAssertFalse(capability.discardPreparedTargetForRecovery())
    XCTAssertEqual(harness.selectedTextReadCount, selectedTextReadCount)
    XCTAssertEqual(harness.writeCount, 0)
    XCTAssertEqual(capability.insert(try DictationText("secret")), .noPreparedTarget)
  }

  func testUnsupportedFieldFallsBackWithoutMutation() {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    harness.canSetSelectedText = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(harness.selectedTextReadCount, 0)
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testOversizedSelectionIsRejectedBeforeMutation() {
    let content = String(repeating: "a", count: DictationText.maximumCharacterCount + 1)
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 0, length: (content as NSString).length)
    )
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(harness.selectedTextReadCount, 0)
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testFocusChangeBeforeInsertionFailsClosed() throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)

    harness.focusedElement = harness.secondElement

    XCTAssertEqual(capability.insert(try DictationText(" world")), .focusChanged)
    XCTAssertEqual(harness.content, "hello")
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testSelectionChangeBeforeInsertionFailsClosed() throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)

    harness.selection = FocusedTextRange(location: 0, length: 0)

    XCTAssertEqual(capability.insert(try DictationText(" world")), .selectionChanged)
    XCTAssertEqual(harness.content, "hello")
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testInsertionDoesNotAdvertiseUndoWhenCaretUpdateFails() throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    harness.setSelectedRangeSucceeds = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)

    XCTAssertEqual(
      capability.insert(try DictationText(" world")),
      .inserted(text: " world", canUndo: false)
    )
    XCTAssertEqual(harness.content, "hello world")
    XCTAssertFalse(capability.canUndo)
  }

  func testUndoRestoresReplacedTextOnlyWhenFocusCaretAndContentStillMatch() throws {
    let harness = FocusedTextHarness(
      content: "hello world", selection: .init(location: 6, length: 5))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(
      capability.insert(try DictationText("Topher")),
      .inserted(text: "Topher", canUndo: true)
    )

    XCTAssertEqual(capability.undoLastInsertion(), .restored)
    XCTAssertEqual(harness.content, "hello world")
    XCTAssertEqual(harness.selection, FocusedTextRange(location: 11, length: 0))
    XCTAssertFalse(capability.canUndo)
  }

  func testUndoRefusesAfterCaretMoves() throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(
      capability.insert(try DictationText(" world")),
      .inserted(text: " world", canUndo: true)
    )

    harness.selection = FocusedTextRange(location: 0, length: 0)

    XCTAssertEqual(capability.undoLastInsertion(), .selectionChanged)
    XCTAssertEqual(harness.content, "hello world")
    XCTAssertTrue(capability.canUndo)
  }

  func testUndoRefusesWhenInsertedContentChanged() throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(
      capability.insert(try DictationText(" world")),
      .inserted(text: " world", canUndo: true)
    )

    harness.content = "hello earth"

    XCTAssertEqual(capability.undoLastInsertion(), .contentChanged)
    XCTAssertEqual(harness.content, "hello earth")
    XCTAssertEqual(harness.selection, FocusedTextRange(location: 11, length: 0))
  }

  func testUndoInvalidatesWithoutReadingTextWhenFieldBecomesSecure() throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(
      capability.insert(try DictationText(" world")),
      .inserted(text: " world", canUndo: true)
    )
    let selectedTextReadCount = harness.selectedTextReadCount
    let writeCount = harness.writeCount

    harness.isSecure = true

    XCTAssertEqual(capability.undoLastInsertion(), .secureField)
    XCTAssertEqual(harness.selectedTextReadCount, selectedTextReadCount)
    XCTAssertEqual(harness.writeCount, writeCount)
    XCTAssertFalse(capability.canUndo)
  }
}

@MainActor
private final class FocusedTextHarness {
  let firstElement = FocusedTextElementID()
  let secondElement = FocusedTextElementID()

  var focusedElement: FocusedTextElementID?
  var content: String
  var selection: FocusedTextRange
  var isSecure = false
  var canSetSelectedText = true
  var canSetSelectedRange = true
  var setSelectedRangeSucceeds = true
  var selectedTextReadCount = 0
  var writeCount = 0

  init(content: String, selection: FocusedTextRange) {
    self.content = content
    self.selection = selection
    focusedElement = firstElement
  }

  var environment: FocusedTextInsertionEnvironment {
    FocusedTextInsertionEnvironment(
      focusedElement: { [weak self] in self?.focusedElement },
      sameElement: { $0 == $1 },
      isSecure: { [weak self] element in
        guard let self, element == firstElement else { return false }
        return isSecure
      },
      selectedText: { [weak self] element in
        guard let self, element == firstElement else { return nil }
        selectedTextReadCount += 1
        return (content as NSString).substring(with: selection.nsRange)
      },
      selectedRange: { [weak self] element in
        guard let self, element == firstElement else { return nil }
        return selection
      },
      textContext: { [weak self] element, range in
        guard let self, element == firstElement else { return FocusedTextContext() }
        let nsContent = content as NSString
        let precedingLocation = max(0, range.location - 2)
        let preceding = nsContent.substring(
          with: NSRange(
            location: precedingLocation,
            length: range.location - precedingLocation
          )
        )
        let followingLength = min(2, max(0, nsContent.length - range.endLocation))
        let following = nsContent.substring(
          with: NSRange(location: range.endLocation, length: followingLength)
        )
        return FocusedTextContext(precedingText: preceding, followingText: following)
      },
      canSetSelectedText: { [weak self] element in
        guard let self, element == firstElement else { return false }
        return canSetSelectedText
      },
      canSetSelectedRange: { [weak self] element in
        guard let self, element == firstElement else { return false }
        return canSetSelectedRange
      },
      setSelectedText: { [weak self] element, text in
        guard let self, element == firstElement, canSetSelectedText else { return false }
        content = (content as NSString).replacingCharacters(in: selection.nsRange, with: text)
        writeCount += 1
        return true
      },
      setSelectedRange: { [weak self] element, range in
        guard
          let self,
          element == firstElement,
          canSetSelectedRange,
          setSelectedRangeSucceeds
        else { return false }
        selection = range
        return true
      },
      release: { _ in }
    )
  }
}

extension FocusedTextRange {
  fileprivate var nsRange: NSRange {
    NSRange(location: location, length: length)
  }
}
