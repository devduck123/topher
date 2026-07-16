import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class FocusedTextInsertionCapabilityTests: XCTestCase {
  func testDeclaresItsAuthority() {
    XCTAssertEqual(FocusedTextInsertionCapability.descriptor.access, .changesState)
    XCTAssertEqual(FocusedTextInsertionCapability.descriptor.risk, .lowRiskReversible)
  }

  func testInsertsByReplacingCapturedSelectionAndMovesCaret() async throws {
    let harness = FocusedTextHarness(
      content: "hello world", selection: .init(location: 6, length: 5))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("Topher"))
    XCTAssertEqual(
      outcome,
      expectedSelectedInsertion(text: "Topher")
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

  func testRecoveryDiscardRefusesRetentionWhenPreparedFieldBecomesSecure() async throws {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    let selectedTextReadCount = harness.selectedTextReadCount

    harness.isSecure = true

    XCTAssertFalse(capability.discardPreparedTargetForRecovery())
    XCTAssertEqual(harness.selectedTextReadCount, selectedTextReadCount)
    XCTAssertEqual(harness.writeCount, 0)
    let outcome = await capability.insert(try DictationText("secret"))
    XCTAssertEqual(outcome, .noPreparedTarget)
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

  func testFocusChangeBeforeInsertionFailsClosed() async throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)

    harness.focusedElement = harness.secondElement

    let outcome = await capability.insert(try DictationText(" world"))
    XCTAssertEqual(outcome, .focusChanged)
    XCTAssertEqual(harness.content, "hello")
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testSelectionChangeBeforeInsertionFailsClosed() async throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)

    harness.selection = FocusedTextRange(location: 0, length: 0)

    let outcome = await capability.insert(try DictationText(" world"))
    XCTAssertEqual(outcome, .selectionChanged)
    XCTAssertEqual(harness.content, "hello")
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testInsertionDoesNotAdvertiseUndoWhenCaretUpdateFails() async throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    harness.setSelectedRangeSucceeds = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)

    let outcome = await capability.insert(try DictationText(" world"))
    XCTAssertEqual(
      outcome,
      expectedSelectedInsertion(
        text: " world",
        canUndo: false,
        verification: .contentOnly
      )
    )
    XCTAssertEqual(harness.content, "hello world")
    XCTAssertFalse(capability.canUndo)
  }

  func testSetterSuccessWithoutObservedMutationDoesNotReportInsertion() async throws {
    let harness = FocusedTextHarness(content: "", selection: .init(location: 0, length: 0))
    harness.selectedTextMutationSucceeds = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("hello"))
    XCTAssertEqual(
      outcome,
      .mutationUnverified(
        FocusedTextInsertionEvidence(
          method: .selectedText,
          verification: .unavailable,
          target: harness.profile,
          wholeValueDecision: .rejectedValueNotSettable
        )
      )
    )
    XCTAssertEqual(harness.content, "")
    XCTAssertFalse(capability.canUndo)
  }

  func testPrefersVerifiedWholeValueForAnEmptyPlainTextSurface() async throws {
    let harness = FocusedTextHarness(content: "", selection: .init(location: 0, length: 0))
    harness.selectedTextMutationSucceeds = false
    harness.exposesValue = true
    harness.canSetValue = true
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("hello"))
    XCTAssertEqual(
      outcome,
      .inserted(
        FocusedTextInsertionResult(
          text: "hello",
          canUndo: false,
          evidence: FocusedTextInsertionEvidence(
            method: .wholeValue,
            verification: .contentAndCaret,
            target: harness.profile,
            wholeValueDecision: .eligibleEmptyTextArea
          )
        )
      )
    )
    XCTAssertEqual(harness.content, "hello")
    XCTAssertEqual(harness.selection, .init(location: 5, length: 0))
    XCTAssertEqual(harness.selectedTextWriteCount, 0)
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testUsesWholeValueForAPartialPlainTextFieldSelection() async throws {
    let harness = FocusedTextHarness(
      content: "hello world", selection: .init(location: 6, length: 5))
    harness.role = .textField
    harness.exposesValue = true
    harness.canSetValue = true
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("Topher"))
    XCTAssertEqual(
      outcome,
      .inserted(
        FocusedTextInsertionResult(
          text: "Topher",
          canUndo: false,
          evidence: FocusedTextInsertionEvidence(
            method: .wholeValue,
            verification: .contentAndCaret,
            target: harness.profile,
            wholeValueDecision: .eligibleTextField
          )
        )
      )
    )
    XCTAssertEqual(harness.content, "hello Topher")
    XCTAssertEqual(harness.selection, .init(location: 12, length: 0))
    XCTAssertEqual(harness.selectedTextWriteCount, 0)
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testWholeValueSuccessWithoutObservedMutationFailsClosed() async throws {
    let harness = FocusedTextHarness(content: "", selection: .init(location: 0, length: 0))
    harness.canSetSelectedText = false
    harness.exposesValue = true
    harness.canSetValue = true
    harness.valueMutationSucceeds = false
    harness.role = .textField
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("hello"))
    XCTAssertEqual(
      outcome,
      .mutationNotObserved(
        FocusedTextInsertionEvidence(
          method: .wholeValue,
          verification: .notObserved,
          target: harness.profile,
          wholeValueDecision: .eligibleTextField
        )
      )
    )
    XCTAssertEqual(harness.content, "")
  }

  func testVerificationAcceptsABoundedDelayedHostMutation() async throws {
    let harness = FocusedTextHarness(content: "", selection: .init(location: 0, length: 0))
    harness.role = .textField
    harness.exposesValue = true
    harness.canSetValue = true
    harness.deferValueMutationUntilWait = true
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("hello"))

    XCTAssertEqual(
      outcome,
      .inserted(
        FocusedTextInsertionResult(
          text: "hello",
          canUndo: false,
          evidence: FocusedTextInsertionEvidence(
            method: .wholeValue,
            verification: .contentAndCaret,
            target: harness.profile,
            wholeValueDecision: .eligibleTextField
          )
        )
      )
    )
    XCTAssertEqual(harness.waitCount, 1)
    XCTAssertEqual(harness.content, "hello")
  }

  func testRefusesWholeValueMutationForPartiallySelectedNonemptyTextArea() {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.canSetSelectedText = false
    harness.exposesValue = true
    harness.canSetValue = true
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testUsesWholeValueForBoundedAppendAtEndOfPlainWebComposer() async throws {
    let content = "First thought."
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: (content as NSString).length, length: 0)
    )
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("Second thought."))

    guard case .inserted(let result) = outcome else {
      return XCTFail("Expected a verified web-composer insertion")
    }
    XCTAssertEqual(result.evidence.method, .wholeValue)
    XCTAssertEqual(result.evidence.verification, .contentAndCaret)
    XCTAssertEqual(harness.content, "First thought. Second thought.")
    XCTAssertEqual(harness.selectedTextWriteCount, 0)
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testUsesWholeValueForUniformMultilineWebComposerAtCaret() async throws {
    let content = "First line\nSecond line"
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 5, length: 0)
    )
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("new"))

    guard case .inserted(let result) = outcome else {
      return XCTFail("Expected a verified multiline web-composer insertion")
    }
    XCTAssertEqual(result.evidence.method, .wholeValue)
    XCTAssertEqual(result.evidence.wholeValueDecision, .eligiblePlainWebComposer)
    XCTAssertEqual(harness.content, "First new line\nSecond line")
    XCTAssertEqual(harness.selectedTextWriteCount, 0)
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testRefusesWholeValueMutationForNativeObjectBearingOrStyledTextArea() {
    for (content, webDepth, hasUniformTextAttributes) in [
      ("Native rich text", nil, true),
      ("Attached \u{FFFC}", 22, true),
      ("Styled web text", 22, false),
    ] as [(String, Int?, Bool)] {
      let harness = FocusedTextHarness(
        content: content,
        selection: .init(location: (content as NSString).length, length: 0)
      )
      harness.canSetSelectedText = false
      harness.exposesValue = true
      harness.canSetValue = true
      harness.webAreaAncestorDepth = webDepth
      harness.hasUniformTextAttributes = hasUniformTextAttributes
      let capability = FocusedTextInsertionCapability(environment: harness.environment)

      XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
      XCTAssertEqual(harness.writeCount, 0)
    }
  }

  func testReadsAttributedTextOnlyForOtherwiseEligibleWebComposer() {
    let harness = FocusedTextHarness(
      content: "Existing draft",
      selection: .init(location: 8, length: 0)
    )
    harness.exposesValue = true
    harness.canSetValue = true
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(harness.uniformTextAttributeReadCount, 0)

    capability.discardPreparedTarget()
    harness.webAreaAncestorDepth = 22

    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(harness.uniformTextAttributeReadCount, 1)
  }

  func testWebComposerFormattingChangeBeforeMutationFailsClosed() async throws {
    let harness = FocusedTextHarness(
      content: "Existing draft",
      selection: .init(location: 8, length: 0)
    )
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    harness.hasUniformTextAttributes = false

    let outcome = await capability.insert(try DictationText("safe"))

    XCTAssertEqual(outcome, .unsupportedField)
    XCTAssertEqual(harness.content, "Existing draft")
    XCTAssertEqual(harness.writeCount, 0)
    XCTAssertEqual(harness.uniformTextAttributeReadCount, 2)
  }

  func testUndoRestoresReplacedTextOnlyWhenFocusCaretAndContentStillMatch() async throws {
    let harness = FocusedTextHarness(
      content: "hello world", selection: .init(location: 6, length: 5))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("Topher"))
    XCTAssertEqual(
      outcome,
      expectedSelectedInsertion(text: "Topher")
    )

    XCTAssertEqual(capability.undoLastInsertion(), .restored)
    XCTAssertEqual(harness.content, "hello world")
    XCTAssertEqual(harness.selection, FocusedTextRange(location: 11, length: 0))
    XCTAssertFalse(capability.canUndo)
  }

  func testUndoRefusesAfterCaretMoves() async throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText(" world"))
    XCTAssertEqual(
      outcome,
      expectedSelectedInsertion(text: " world")
    )

    harness.selection = FocusedTextRange(location: 0, length: 0)

    XCTAssertEqual(capability.undoLastInsertion(), .selectionChanged)
    XCTAssertEqual(harness.content, "hello world")
    XCTAssertTrue(capability.canUndo)
  }

  func testUndoRefusesWhenInsertedContentChanged() async throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText(" world"))
    XCTAssertEqual(
      outcome,
      expectedSelectedInsertion(text: " world")
    )

    harness.content = "hello earth"

    XCTAssertEqual(capability.undoLastInsertion(), .contentChanged)
    XCTAssertEqual(harness.content, "hello earth")
    XCTAssertEqual(harness.selection, FocusedTextRange(location: 11, length: 0))
  }

  func testUndoInvalidatesWithoutReadingTextWhenFieldBecomesSecure() async throws {
    let harness = FocusedTextHarness(content: "hello", selection: .init(location: 5, length: 0))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText(" world"))
    XCTAssertEqual(
      outcome,
      expectedSelectedInsertion(text: " world")
    )
    let selectedTextReadCount = harness.selectedTextReadCount
    let writeCount = harness.writeCount

    harness.isSecure = true

    XCTAssertEqual(capability.undoLastInsertion(), .secureField)
    XCTAssertEqual(harness.selectedTextReadCount, selectedTextReadCount)
    XCTAssertEqual(harness.writeCount, writeCount)
    XCTAssertFalse(capability.canUndo)
  }

  private func expectedSelectedInsertion(
    text: String,
    canUndo: Bool = true,
    verification: FocusedTextInsertionVerification = .contentAndCaret
  ) -> FocusedTextInsertionOutcome {
    .inserted(
      FocusedTextInsertionResult(
        text: text,
        canUndo: canUndo,
        evidence: FocusedTextInsertionEvidence(
          method: .selectedText,
          verification: verification,
          target: FocusedTextTargetProfile(
            role: .textArea,
            canSetSelectedText: true,
            canSetSelectedRange: true,
            canSetValue: false
          ),
          wholeValueDecision: .rejectedValueNotSettable
        )
      )
    )
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
  var role: FocusedTextTargetRole = .textArea
  var webAreaAncestorDepth: Int?
  var hasUniformTextAttributes = true
  var canSetSelectedText = true
  var canSetSelectedRange = true
  var canSetValue = false
  var exposesValue = false
  var selectedTextMutationSucceeds = true
  var valueMutationSucceeds = true
  var deferValueMutationUntilWait = false
  var setSelectedRangeSucceeds = true
  var selectedTextReadCount = 0
  var uniformTextAttributeReadCount = 0
  var writeCount = 0
  var selectedTextWriteCount = 0
  var valueWriteCount = 0
  var waitCount = 0
  var pendingValue: String?

  init(content: String, selection: FocusedTextRange) {
    self.content = content
    self.selection = selection
    focusedElement = firstElement
  }

  var profile: FocusedTextTargetProfile {
    FocusedTextTargetProfile(
      role: role,
      canSetSelectedText: canSetSelectedText,
      canSetSelectedRange: canSetSelectedRange,
      canSetValue: canSetValue
    )
  }

  var environment: FocusedTextInsertionEnvironment {
    FocusedTextInsertionEnvironment(
      focusedElement: { [weak self] in self?.focusedElement },
      sameElement: { $0 == $1 },
      processIdentifier: { [weak self] element in
        guard let self else { return nil }
        return element == firstElement ? 1001 : 1002
      },
      isSecure: { [weak self] element in
        guard let self, element == firstElement else { return false }
        return isSecure
      },
      role: { [weak self] _ in self?.role ?? .other },
      webAreaAncestorDepth: { [weak self] _ in self?.webAreaAncestorDepth },
      hasUniformTextAttributes: { [weak self] _, _ in
        guard let self else { return false }
        uniformTextAttributeReadCount += 1
        return hasUniformTextAttributes
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
      value: { [weak self] element in
        guard let self, element == firstElement, exposesValue else { return nil }
        return content
      },
      text: { [weak self] element, range in
        guard let self, element == firstElement else { return nil }
        let nsContent = content as NSString
        guard range.endLocation <= nsContent.length else { return nil }
        return nsContent.substring(with: range.nsRange)
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
      canSetValue: { [weak self] element in
        guard let self, element == firstElement else { return false }
        return canSetValue
      },
      setSelectedText: { [weak self] element, text in
        guard let self, element == firstElement, canSetSelectedText else { return false }
        if selectedTextMutationSucceeds {
          content = (content as NSString).replacingCharacters(in: selection.nsRange, with: text)
        }
        writeCount += 1
        selectedTextWriteCount += 1
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
      setValue: { [weak self] element, value in
        guard let self, element == firstElement, canSetValue else { return false }
        if valueMutationSucceeds {
          if deferValueMutationUntilWait {
            pendingValue = value
          } else {
            content = value
          }
        }
        writeCount += 1
        valueWriteCount += 1
        return true
      },
      waitForMutation: { [weak self] _ in
        guard let self else { return }
        waitCount += 1
        if let pendingValue {
          content = pendingValue
          self.pendingValue = nil
        }
      },
      release: { _ in }
    )
  }
}
