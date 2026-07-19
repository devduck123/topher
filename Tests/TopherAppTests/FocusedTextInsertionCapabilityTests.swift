import ApplicationServices
import Foundation
import TopherCore
import XCTest

@testable import TopherApp

@MainActor
final class FocusedTextInsertionCapabilityTests: XCTestCase {
  func testDeclaresItsAuthority() {
    XCTAssertEqual(FocusedTextInsertionCapability.descriptor.access, .changesState)
    XCTAssertEqual(FocusedTextInsertionCapability.descriptor.risk, .lowRiskReversible)
  }

  func testAttributeClassifierAllowsUniformPresentationAndProofingMetadata() {
    let value = "plain text"
    let font = NSAttributedString.Key("AXFont")
    let foreground = NSAttributedString.Key("AXForegroundColor")
    let misspelled = NSAttributedString.Key("AXMisspelled")
    let attributed = NSMutableAttributedString(
      string: value,
      attributes: [font: "Regular 14", foreground: "black"]
    )
    attributed.addAttribute(misspelled, value: true, range: NSRange(location: 0, length: 5))

    XCTAssertEqual(
      FocusedTextAttributeClassifier.classify(attributed, expectedValue: value),
      .eligibleUniformPresentation
    )
  }

  func testAttributeClassifierRejectsSemanticStyledAndMixedContent() {
    let font = NSAttributedString.Key("AXFont")
    let foreground = NSAttributedString.Key("AXForegroundColor")
    let link = NSAttributedString.Key("AXLink")

    XCTAssertEqual(
      FocusedTextAttributeClassifier.classify(
        NSAttributedString(string: "link", attributes: [font: "Regular", link: "target"]),
        expectedValue: "link"
      ),
      .rejectedSemanticOrUnknownAttribute
    )
    XCTAssertEqual(
      FocusedTextAttributeClassifier.classify(
        NSAttributedString(string: "bold", attributes: [font: "Bold 14"]),
        expectedValue: "bold"
      ),
      .rejectedStyledFont
    )

    let mixed = NSMutableAttributedString(
      string: "mixed",
      attributes: [font: "Regular 14", foreground: "black"]
    )
    mixed.addAttribute(foreground, value: "red", range: NSRange(location: 3, length: 2))
    XCTAssertEqual(
      FocusedTextAttributeClassifier.classify(mixed, expectedValue: "mixed"),
      .rejectedMixedPresentation
    )
  }

  func testSuggestionClassifierRequiresCompleteSuggestionCoverage() {
    let suggestion = NSAttributedString.Key(kAXIsSuggestionStringAttribute as String)
    let allSuggestion = NSAttributedString(
      string: "Ask for follow-up changes",
      attributes: [suggestion: true]
    )
    XCTAssertEqual(
      FocusedTextSuggestionClassifier.classify(
        allSuggestion,
        expectedValue: allSuggestion.string
      ),
      .explicitSuggestionOnly
    )

    let mixed = NSMutableAttributedString(
      string: "draft suggestion",
      attributes: [suggestion: true]
    )
    mixed.removeAttribute(suggestion, range: NSRange(location: 0, length: 5))
    XCTAssertEqual(
      FocusedTextSuggestionClassifier.classify(mixed, expectedValue: mixed.string),
      .mixedSuggestionAndContent
    )
    XCTAssertEqual(
      FocusedTextSuggestionClassifier.classify(
        NSAttributedString(string: "draft"),
        expectedValue: "draft"
      ),
      .logicalContentPresent
    )
  }

  func testKnownComposerSuggestionClassifierIsExactAndApplicationScoped() {
    XCTAssertEqual(
      FocusedTextKnownComposerSuggestionClassifier.classify(
        "Ask for follow-up changes\n",
        application: .codexOrChatGPT
      ),
      .recognized
    )
    XCTAssertEqual(
      FocusedTextKnownComposerSuggestionClassifier.classify(
        "My Ask for follow-up changes draft",
        application: .codexOrChatGPT
      ),
      .unrecognized
    )
    XCTAssertEqual(
      FocusedTextKnownComposerSuggestionClassifier.classify(
        "Ask for follow-up changes",
        application: .notion
      ),
      .notEvaluated
    )
  }

  func testSemanticResolverChecksMarkerEvidenceBeforePositiveCharacterCount() {
    XCTAssertEqual(
      FocusedTextSemanticContentResolver.resolve(
        suggestionAttributeState: .notSuggestion,
        characterCountState: .positive,
        textMarkerState: .empty,
        knownSuggestionState: .unrecognized
      ),
      .corroboratedLogicalEmpty
    )
    XCTAssertEqual(
      FocusedTextSemanticContentResolver.resolve(
        suggestionAttributeState: .notSuggestion,
        characterCountState: .positive,
        textMarkerState: .nonempty,
        knownSuggestionState: .unrecognized
      ),
      .logicalContentPresent
    )
  }

  func testSemanticResolverAllowsKnownSuggestionButRejectsMixedContent() {
    XCTAssertEqual(
      FocusedTextSemanticContentResolver.resolve(
        suggestionAttributeState: .unavailable,
        characterCountState: .positive,
        textMarkerState: .nonempty,
        knownSuggestionState: .recognized
      ),
      .knownApplicationSuggestion
    )
    XCTAssertEqual(
      FocusedTextSemanticContentResolver.resolve(
        suggestionAttributeState: .mixed,
        characterCountState: .positive,
        textMarkerState: .nonempty,
        knownSuggestionState: .recognized
      ),
      .mixedSuggestionAndContent
    )
  }

  func testInsertionEvidenceDecodesPreBuild16RecordsWithoutStructuralFields() throws {
    let data = Data(
      """
      {
        "method": "selectedText",
        "verification": "notObserved",
        "target": {
          "role": "textArea",
          "canSetSelectedText": true,
          "canSetSelectedRange": true,
          "canSetValue": false
        },
        "wholeValueDecision": "rejectedRichWebValue"
      }
      """.utf8
    )

    let evidence = try JSONDecoder().decode(FocusedTextInsertionEvidence.self, from: data)

    XCTAssertNil(evidence.target.application)
    XCTAssertNil(evidence.selectionRelation)
    XCTAssertNil(evidence.placeholderState)
    XCTAssertNil(evidence.attributeDecision)
    XCTAssertNil(evidence.semanticSuggestionAttributeState)
    XCTAssertNil(evidence.semanticCharacterCountState)
    XCTAssertNil(evidence.semanticTextMarkerState)
    XCTAssertNil(evidence.semanticKnownSuggestionState)
  }

  func testPreparationEvidenceDecodesAbsentOptionalFields() throws {
    let evidence = try JSONDecoder().decode(
      FocusedTextPreparationEvidence.self,
      from: Data("{}".utf8)
    )

    XCTAssertNil(evidence.failureReason)
    XCTAssertNil(evidence.focusSource)
    XCTAssertNil(evidence.targetApplication)
  }

  func testSystemWideFocusRemainsPrimaryWhenAvailable() {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.applicationFocusedElement = harness.secondElement
    harness.frontmostProcessIdentifier = harness.firstProcessIdentifier
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(harness.systemFocusReadCount, 1)
    XCTAssertEqual(harness.applicationFocusReadCount, 0)
    XCTAssertEqual(
      capability.latestPreparationEvidence,
      FocusedTextPreparationEvidence(
        focusSource: .systemWide,
        targetApplication: .other
      )
    )
  }

  func testUsesFrontmostApplicationFocusWhenSystemWideFocusIsUnavailable() async throws {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.focusedElement = nil
    harness.applicationFocusedElement = harness.firstElement
    harness.frontmostProcessIdentifier = harness.firstProcessIdentifier
    harness.targetApplication = .visualStudioCode
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    XCTAssertEqual(harness.applicationFocusReadCount, 1)
    XCTAssertEqual(
      capability.latestPreparationEvidence,
      FocusedTextPreparationEvidence(
        focusSource: .frontmostApplication,
        targetApplication: .visualStudioCode
      )
    )

    let outcome = await capability.insert(try DictationText(" text"))
    guard case .inserted = outcome else { return XCTFail("Expected fallback target insertion") }
    XCTAssertEqual(harness.content, "draft text")
    XCTAssertEqual(harness.selectedTextWriteCount, 1)
  }

  func testDoesNotFallBackAcrossSystemAndFrontmostApplicationPIDMismatch() {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.applicationFocusedElement = harness.secondElement
    harness.frontmostProcessIdentifier = harness.secondProcessIdentifier
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(harness.applicationFocusReadCount, 0)
    XCTAssertEqual(harness.selectedTextReadCount, 0)
    XCTAssertEqual(harness.writeCount, 0)
    XCTAssertEqual(
      capability.latestPreparationEvidence?.failureReason,
      .focusedElementProcessMismatch
    )
  }

  func testApplicationFallbackRejectsElementFromAnotherPID() {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.focusedElement = nil
    harness.applicationFocusedElement = harness.secondElement
    harness.frontmostProcessIdentifier = harness.firstProcessIdentifier
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(harness.selectedTextReadCount, 0)
    XCTAssertEqual(harness.writeCount, 0)
    XCTAssertEqual(
      capability.latestPreparationEvidence?.failureReason,
      .focusedElementProcessMismatch
    )
  }

  func testCapturedPIDChangeBeforeInsertionFailsClosedWithoutMutation() async throws {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.frontmostProcessIdentifier = harness.firstProcessIdentifier
    let capability = FocusedTextInsertionCapability(environment: harness.environment)
    XCTAssertEqual(capability.prepareTarget(), .ready)

    harness.frontmostProcessIdentifier = harness.secondProcessIdentifier
    harness.focusedElement = nil
    harness.applicationFocusedElement = harness.secondElement

    let outcome = await capability.insert(try DictationText(" text"))

    XCTAssertEqual(outcome, .focusChanged)
    XCTAssertEqual(harness.content, "draft")
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testInsertsByReplacingCapturedSelectionAndMovesCaret() async throws {
    let harness = FocusedTextHarness(
      content: "hello world", selection: .init(location: 6, length: 5))
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("Topher"))
    XCTAssertEqual(
      outcome,
      expectedSelectedInsertion(text: "Topher", selectionRelation: .partialSelection)
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
    XCTAssertEqual(capability.latestPreparationEvidence?.failureReason, .secureField)
  }

  func testApplicationFallbackRejectsSecureFieldBeforeReadingText() {
    let harness = FocusedTextHarness(content: "secret", selection: .init(location: 6, length: 0))
    harness.focusedElement = nil
    harness.applicationFocusedElement = harness.firstElement
    harness.frontmostProcessIdentifier = harness.firstProcessIdentifier
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
    XCTAssertEqual(
      capability.latestPreparationEvidence?.failureReason,
      .textMutationSetterUnavailable
    )
  }

  func testReportsUnavailableRangeSetterWithoutReadingContent() {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.canSetSelectedRange = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(harness.selectedTextReadCount, 0)
    XCTAssertEqual(
      capability.latestPreparationEvidence?.failureReason,
      .selectedRangeSetterUnavailable
    )
  }

  func testReportsUnavailableSelectedRangePrecisely() {
    let harness = FocusedTextHarness(content: "draft", selection: .init(location: 5, length: 0))
    harness.exposesSelectedRange = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(harness.selectedTextReadCount, 0)
    XCTAssertEqual(capability.latestPreparationEvidence?.failureReason, .selectedRangeUnavailable)
  }

  func testReportsUnavailableAndInconsistentSelectedTextPrecisely() {
    let unavailableHarness = FocusedTextHarness(
      content: "draft", selection: .init(location: 5, length: 0))
    unavailableHarness.exposesSelectedText = false
    let unavailableCapability = FocusedTextInsertionCapability(
      environment: unavailableHarness.environment)

    XCTAssertEqual(unavailableCapability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(
      unavailableCapability.latestPreparationEvidence?.failureReason,
      .selectedTextUnavailable
    )

    let inconsistentHarness = FocusedTextHarness(
      content: "draft", selection: .init(location: 5, length: 0))
    inconsistentHarness.selectedTextOverride = "unexpected"
    let inconsistentCapability = FocusedTextInsertionCapability(
      environment: inconsistentHarness.environment)

    XCTAssertEqual(inconsistentCapability.prepareTarget(), .unsupportedField)
    XCTAssertEqual(
      inconsistentCapability.latestPreparationEvidence?.failureReason,
      .selectedTextLengthMismatch
    )
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
    XCTAssertEqual(capability.latestPreparationEvidence?.failureReason, .selectedRangeTooLarge)
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
          wholeValueDecision: .rejectedValueNotSettable,
          selectionRelation: .emptyValue,
          placeholderState: .absent,
          attributeDecision: .notEvaluated
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
            wholeValueDecision: .eligibleEmptyTextArea,
            selectionRelation: .emptyValue,
            placeholderState: .absent,
            attributeDecision: .notEvaluated
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
            wholeValueDecision: .eligibleTextField,
            selectionRelation: .partialSelection,
            placeholderState: .absent,
            attributeDecision: .notEvaluated
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
          wholeValueDecision: .eligibleTextField,
          selectionRelation: .emptyValue,
          placeholderState: .absent,
          attributeDecision: .notEvaluated
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
            wholeValueDecision: .eligibleTextField,
            selectionRelation: .emptyValue,
            placeholderState: .absent,
            attributeDecision: .notEvaluated
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

  func testStabilizesWholeValueCaretWithoutRepeatingTextMutation() async throws {
    let suggestion = "Ask for follow-up changes\n"
    let transcript = "Hello, how are you doing today?"
    let harness = FocusedTextHarness(
      content: suggestion,
      selection: .init(location: 0, length: 0)
    )
    harness.targetApplication = .codexOrChatGPT
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.semanticContentEvidence = .testEvidence(decision: .explicitSuggestionOnly)
    harness.semanticContentEvidenceAfterValueMutation = .testEvidence(
      decision: .logicalContentPresent
    )
    harness.selectedRangeWritesToIgnore = 1
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText(transcript))

    guard case .inserted(let result) = outcome else {
      return XCTFail("Expected a verified insertion with a stabilized caret")
    }
    XCTAssertEqual(result.evidence.verification, .contentAndCaret)
    XCTAssertEqual(harness.content, transcript)
    XCTAssertEqual(
      harness.selection,
      FocusedTextRange(location: (transcript as NSString).length, length: 0)
    )
    XCTAssertEqual(harness.valueWriteCount, 1)
    XCTAssertEqual(harness.selectedRangeWriteCount, 2)
    XCTAssertEqual(harness.waitCount, 1)
  }

  func testRefusesUnprovenCodexCaretStartValue() async throws {
    let content = "Authored draft\n"
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 0, length: 0)
    )
    harness.targetApplication = .codexOrChatGPT
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.selectedTextMutationSucceeds = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("Hello, how are you doing today?"))

    guard case .mutationNotObserved(let evidence) = outcome else {
      return XCTFail("Expected authored Codex text to fall back without a value rewrite")
    }
    XCTAssertEqual(evidence.method, .selectedText)
    XCTAssertEqual(evidence.target.application, .codexOrChatGPT)
    XCTAssertEqual(evidence.selectionRelation, .caretAtStart)
    XCTAssertEqual(evidence.wholeValueDecision, .rejectedAmbiguousWebSelection)
    XCTAssertEqual(harness.content, content)
    XCTAssertEqual(harness.selectedTextWriteCount, 1)
    XCTAssertEqual(harness.valueWriteCount, 0)
  }

  func testReplacesProvenCodexSuggestionWithoutAppendingOrSelectedTextMutation() async throws {
    let suggestion = "Ask for follow-up changes\n"
    let transcript = "Hello, how are you doing today?"
    let harness = FocusedTextHarness(
      content: suggestion,
      selection: .init(location: 0, length: 0)
    )
    harness.targetApplication = .codexOrChatGPT
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.selectedTextMutationSucceeds = false
    harness.semanticContentEvidence = .testEvidence(decision: .explicitSuggestionOnly)
    harness.semanticContentEvidenceAfterValueMutation = .testEvidence(
      decision: .logicalContentPresent
    )
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText(transcript))

    guard case .inserted(let result) = outcome else {
      return XCTFail("Expected verified semantic-empty composer insertion")
    }
    XCTAssertEqual(result.text, transcript)
    XCTAssertEqual(result.evidence.method, .wholeValue)
    XCTAssertEqual(
      result.evidence.wholeValueDecision,
      .eligibleSemanticallyEmptyWebComposer
    )
    XCTAssertEqual(result.evidence.semanticContentDecision, .explicitSuggestionOnly)
    XCTAssertEqual(harness.content, transcript)
    XCTAssertEqual(harness.selectedTextWriteCount, 0)
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testReplacesKnownCodexSuggestionWithFixedSignalDiagnostics() async throws {
    let suggestion = "Ask for follow-up changes\n"
    let transcript = "Hello, how are you doing today?"
    let harness = FocusedTextHarness(
      content: suggestion,
      selection: .init(location: 0, length: 0)
    )
    harness.targetApplication = .codexOrChatGPT
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.selectedTextMutationSucceeds = false
    harness.semanticContentEvidence = .testEvidence(
      decision: .knownApplicationSuggestion,
      suggestionAttributeState: .notSuggestion,
      characterCountState: .positive,
      textMarkerState: .nonempty,
      knownSuggestionState: .recognized
    )
    harness.semanticContentEvidenceAfterValueMutation = .testEvidence(
      decision: .logicalContentPresent,
      suggestionAttributeState: .notSuggestion,
      characterCountState: .positive,
      textMarkerState: .nonempty,
      knownSuggestionState: .unrecognized
    )
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText(transcript))

    guard case .inserted(let result) = outcome else {
      return XCTFail("Expected known Codex suggestion replacement")
    }
    XCTAssertEqual(result.evidence.method, .wholeValue)
    XCTAssertEqual(result.evidence.semanticContentDecision, .knownApplicationSuggestion)
    XCTAssertEqual(result.evidence.semanticSuggestionAttributeState, .notSuggestion)
    XCTAssertEqual(result.evidence.semanticCharacterCountState, .positive)
    XCTAssertEqual(result.evidence.semanticTextMarkerState, .nonempty)
    XCTAssertEqual(result.evidence.semanticKnownSuggestionState, .recognized)
    XCTAssertEqual(harness.content, transcript)
    XCTAssertEqual(harness.selectedTextWriteCount, 0)
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testSemanticComposerEvidenceChangeBeforeMutationFailsClosed() async throws {
    let content = "Ask for follow-up changes\n"
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 0, length: 0)
    )
    harness.targetApplication = .codexOrChatGPT
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.semanticContentEvidence = .testEvidence(decision: .corroboratedLogicalEmpty)
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    harness.semanticContentEvidence = .testEvidence(decision: .logicalContentPresent)

    let outcome = await capability.insert(try DictationText("hello"))
    XCTAssertEqual(outcome, .unsupportedField)
    XCTAssertEqual(harness.writeCount, 0)
  }

  func testSemanticComposerRequiresPostWriteAuthoredContentEvidence() async throws {
    let content = "Ask for follow-up changes\n"
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 0, length: 0)
    )
    harness.targetApplication = .codexOrChatGPT
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.semanticContentEvidence = .testEvidence(decision: .explicitSuggestionOnly)
    harness.semanticContentEvidenceAfterValueMutation = .testEvidence(
      decision: .evidenceUnavailable
    )
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("hello"))

    guard case .mutationUnverified(let evidence) = outcome else {
      return XCTFail("Expected an uncertain result when post-write semantics disappear")
    }
    XCTAssertEqual(evidence.verification, .unavailable)
    XCTAssertEqual(harness.valueWriteCount, 1)
    XCTAssertEqual(harness.selectedTextWriteCount, 0)
  }

  func testRefusesPlaceholderBackedValueBeforeWholeValueMutation() async throws {
    let content = "Ask anything"
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 0, length: 0)
    )
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.placeholderValue = content
    harness.selectedTextMutationSucceeds = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("Hello"))

    guard case .mutationNotObserved(let evidence) = outcome else {
      return XCTFail("Expected placeholder-backed content to fall back")
    }
    XCTAssertEqual(evidence.placeholderState, .matchesValue)
    XCTAssertEqual(evidence.wholeValueDecision, .rejectedPlaceholderBackedValue)
    XCTAssertEqual(harness.content, content)
    XCTAssertEqual(harness.valueWriteCount, 0)
  }

  func testUsesWholeValueForNotionLikeUniformPresentationAtEnd() async throws {
    let content = "Existing Notion text"
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: (content as NSString).length, length: 0)
    )
    harness.targetApplication = .notion
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 12
    harness.textAttributeDecision = .eligibleUniformPresentation
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("appended"))

    guard case .inserted(let result) = outcome else {
      return XCTFail("Expected a verified plain Notion-style append")
    }
    XCTAssertEqual(result.evidence.method, .wholeValue)
    XCTAssertEqual(result.evidence.target.application, .notion)
    XCTAssertEqual(result.evidence.selectionRelation, .caretAtEnd)
    XCTAssertEqual(result.evidence.attributeDecision, .eligibleUniformPresentation)
    XCTAssertEqual(harness.content, "Existing Notion text appended")
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testUsesWholeValueForBoundedPlainNotionCaretAtStartAndMiddle() async throws {
    for (location, expected) in [
      (0, "prepended Existing Notion text"),
      (8, "Existing inserted Notion text"),
    ] {
      let content = "Existing Notion text"
      let harness = FocusedTextHarness(
        content: content,
        selection: .init(location: location, length: 0)
      )
      harness.targetApplication = .notion
      harness.exposesValue = true
      harness.canSetValue = true
      harness.webAreaAncestorDepth = 12
      harness.textAttributeDecision = .eligibleUniformPresentation
      harness.selectedTextMutationSucceeds = false
      let capability = FocusedTextInsertionCapability(environment: harness.environment)

      XCTAssertEqual(capability.prepareTarget(), .ready)
      let transcript = location == 0 ? "prepended" : "inserted"
      let outcome = await capability.insert(try DictationText(transcript))

      guard case .inserted(let result) = outcome else {
        return XCTFail("Expected verified plain Notion caret insertion at \(location)")
      }
      XCTAssertEqual(result.evidence.method, .wholeValue)
      XCTAssertEqual(result.evidence.wholeValueDecision, .eligiblePlainWebSelection)
      XCTAssertEqual(harness.content, expected)
      XCTAssertEqual(harness.selectedTextWriteCount, 0)
      XCTAssertEqual(harness.valueWriteCount, 1)
    }
  }

  func testPrependingPunctuatedDictationSeparatesFollowingNotionText() async throws {
    let content = "Existing Notion text"
    let transcript = "Went back to the start of the line."
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 0, length: 0)
    )
    harness.targetApplication = .notion
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 12
    harness.textAttributeDecision = .eligibleUniformPresentation
    harness.selectedTextMutationSucceeds = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText(transcript))

    guard case .inserted(let result) = outcome else {
      return XCTFail("Expected a verified punctuated Notion prepend")
    }
    XCTAssertEqual(result.text, transcript + " ")
    XCTAssertEqual(harness.content, transcript + " " + content)
    XCTAssertEqual(harness.valueWriteCount, 1)
  }

  func testRefusesNotionCaretWholeValueForMultilineOrRichContent() async throws {
    for (content, decision) in [
      ("First line\nSecond line", FocusedTextAttributeDecision.eligibleUniformPresentation),
      ("Existing rich text", .rejectedStyledFont),
    ] {
      let harness = FocusedTextHarness(
        content: content,
        selection: .init(location: 5, length: 0)
      )
      harness.targetApplication = .notion
      harness.exposesValue = true
      harness.canSetValue = true
      harness.webAreaAncestorDepth = 12
      harness.textAttributeDecision = decision
      harness.selectedTextMutationSucceeds = false
      let capability = FocusedTextInsertionCapability(environment: harness.environment)

      XCTAssertEqual(capability.prepareTarget(), .ready)
      let outcome = await capability.insert(try DictationText("new"))

      guard case .mutationNotObserved(let evidence) = outcome else {
        return XCTFail("Expected unsafe Notion caret insertion to fall back")
      }
      XCTAssertFalse(evidence.wholeValueDecision?.permitsMutation ?? true)
      XCTAssertEqual(harness.content, content)
      XCTAssertEqual(harness.valueWriteCount, 0)
    }
  }

  func testRefusesWholeValueForMidValueWebComposerCaret() async throws {
    let content = "First line\nSecond line"
    let harness = FocusedTextHarness(
      content: content,
      selection: .init(location: 5, length: 0)
    )
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    harness.selectedTextMutationSucceeds = false
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    let outcome = await capability.insert(try DictationText("new"))

    guard case .mutationNotObserved(let evidence) = outcome else {
      return XCTFail("Expected the ambiguous web selection to fall back")
    }
    XCTAssertEqual(evidence.method, .selectedText)
    XCTAssertEqual(evidence.wholeValueDecision, .rejectedAmbiguousWebSelection)
    XCTAssertEqual(evidence.selectionRelation, .caretInMiddle)
    XCTAssertEqual(harness.content, content)
    XCTAssertEqual(harness.selectedTextWriteCount, 1)
    XCTAssertEqual(harness.valueWriteCount, 0)
  }

  func testRefusesWholeValueMutationForNativeObjectBearingOrStyledTextArea() {
    for (content, webDepth, attributeDecision) in [
      ("Native rich text", nil, FocusedTextAttributeDecision.eligibleFontOnly),
      ("Attached \u{FFFC}", 22, .eligibleFontOnly),
      ("Styled web text", 22, .rejectedStyledFont),
    ] as [(String, Int?, FocusedTextAttributeDecision)] {
      let harness = FocusedTextHarness(
        content: content,
        selection: .init(location: (content as NSString).length, length: 0)
      )
      harness.canSetSelectedText = false
      harness.exposesValue = true
      harness.canSetValue = true
      harness.webAreaAncestorDepth = webDepth
      harness.textAttributeDecision = attributeDecision
      let capability = FocusedTextInsertionCapability(environment: harness.environment)

      XCTAssertEqual(capability.prepareTarget(), .unsupportedField)
      XCTAssertEqual(harness.writeCount, 0)
    }
  }

  func testReadsAttributedTextOnlyForOtherwiseEligibleWebComposer() {
    let harness = FocusedTextHarness(
      content: "Existing draft",
      selection: .init(location: 14, length: 0)
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
      selection: .init(location: 14, length: 0)
    )
    harness.exposesValue = true
    harness.canSetValue = true
    harness.webAreaAncestorDepth = 22
    let capability = FocusedTextInsertionCapability(environment: harness.environment)

    XCTAssertEqual(capability.prepareTarget(), .ready)
    harness.textAttributeDecision = .rejectedMixedPresentation

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
      expectedSelectedInsertion(text: "Topher", selectionRelation: .partialSelection)
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
    verification: FocusedTextInsertionVerification = .contentAndCaret,
    selectionRelation: FocusedTextSelectionRelation = .emptyValue
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
            canSetValue: false,
            application: .other
          ),
          wholeValueDecision: .rejectedValueNotSettable,
          selectionRelation: selectionRelation,
          placeholderState: .absent,
          attributeDecision: .notEvaluated
        )
      )
    )
  }
}

extension FocusedTextSemanticContentEvidence {
  fileprivate static func testEvidence(
    decision: FocusedTextSemanticContentDecision,
    suggestionAttributeState: FocusedTextSemanticSuggestionAttributeState = .unavailable,
    characterCountState: FocusedTextSemanticCharacterCountState = .unavailable,
    textMarkerState: FocusedTextSemanticTextMarkerState = .unavailable,
    knownSuggestionState: FocusedTextSemanticKnownSuggestionState = .notEvaluated
  ) -> Self {
    Self(
      decision: decision,
      suggestionAttributeState: suggestionAttributeState,
      characterCountState: characterCountState,
      textMarkerState: textMarkerState,
      knownSuggestionState: knownSuggestionState
    )
  }
}

@MainActor
private final class FocusedTextHarness {
  let firstElement = FocusedTextElementID()
  let secondElement = FocusedTextElementID()
  let firstProcessIdentifier = pid_t(1001)
  let secondProcessIdentifier = pid_t(1002)

  var focusedElement: FocusedTextElementID?
  var applicationFocusedElement: FocusedTextElementID?
  var frontmostProcessIdentifier: pid_t?
  var content: String
  var selection: FocusedTextRange
  var isSecure = false
  var role: FocusedTextTargetRole = .textArea
  var targetApplication: FocusedTextTargetApplication = .other
  var webAreaAncestorDepth: Int?
  var textAttributeDecision: FocusedTextAttributeDecision = .eligibleFontOnly
  var semanticContentEvidence = FocusedTextSemanticContentEvidence.testEvidence(
    decision: .evidenceUnavailable
  )
  var semanticContentEvidenceAfterValueMutation: FocusedTextSemanticContentEvidence?
  var placeholderValue: String?
  var canSetSelectedText = true
  var canSetSelectedRange = true
  var canSetValue = false
  var exposesValue = false
  var exposesSelectedRange = true
  var exposesSelectedText = true
  var selectedTextOverride: String?
  var selectedTextMutationSucceeds = true
  var valueMutationSucceeds = true
  var deferValueMutationUntilWait = false
  var setSelectedRangeSucceeds = true
  var selectedRangeWritesToIgnore = 0
  var selectedRangeWriteCount = 0
  var selectedTextReadCount = 0
  var uniformTextAttributeReadCount = 0
  var writeCount = 0
  var selectedTextWriteCount = 0
  var valueWriteCount = 0
  var waitCount = 0
  var pendingValue: String?
  var systemFocusReadCount = 0
  var applicationFocusReadCount = 0

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
      canSetValue: canSetValue,
      application: targetApplication
    )
  }

  var environment: FocusedTextInsertionEnvironment {
    FocusedTextInsertionEnvironment(
      focusedElement: { [weak self] in
        self?.systemFocusReadCount += 1
        return self?.focusedElement
      },
      applicationFocusedElement: { [weak self] processIdentifier in
        guard let self else { return nil }
        applicationFocusReadCount += 1
        guard processIdentifier == frontmostProcessIdentifier else { return nil }
        return applicationFocusedElement
      },
      frontmostApplicationProcessIdentifier: { [weak self] in
        self?.frontmostProcessIdentifier
      },
      sameElement: { $0 == $1 },
      processIdentifier: { [weak self] element in
        guard let self else { return nil }
        return element == firstElement ? firstProcessIdentifier : secondProcessIdentifier
      },
      targetApplication: { [weak self] _ in self?.targetApplication ?? .unknown },
      isSecure: { [weak self] element in
        guard let self, element == firstElement else { return false }
        return isSecure
      },
      role: { [weak self] _ in self?.role ?? .other },
      webAreaAncestorDepth: { [weak self] _ in self?.webAreaAncestorDepth },
      textAttributeDecision: { [weak self] _, _ in
        guard let self else { return .rejectedUnavailableOrInconsistent }
        uniformTextAttributeReadCount += 1
        return textAttributeDecision
      },
      semanticContentEvidence: { [weak self] _, _, _ in
        self?.semanticContentEvidence
          ?? .testEvidence(decision: .evidenceUnavailable)
      },
      placeholderValue: { [weak self] _ in self?.placeholderValue },
      selectedText: { [weak self] element in
        guard let self, element == firstElement, exposesSelectedText else { return nil }
        selectedTextReadCount += 1
        if let selectedTextOverride { return selectedTextOverride }
        return (content as NSString).substring(with: selection.nsRange)
      },
      selectedRange: { [weak self] element in
        guard let self, element == firstElement, exposesSelectedRange else { return nil }
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
        guard let self, element == firstElement, canSetSelectedRange else { return false }
        selectedRangeWriteCount += 1
        guard setSelectedRangeSucceeds else { return false }
        if selectedRangeWriteCount <= selectedRangeWritesToIgnore { return true }
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
            if let semanticContentEvidenceAfterValueMutation {
              semanticContentEvidence = semanticContentEvidenceAfterValueMutation
            }
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
