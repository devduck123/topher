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

enum FocusedTextFocusSource: String, Codable, Equatable, Sendable {
  case systemWide
  case frontmostApplication
}

/// A fixed, content-free explanation of why Accessibility preparation failed.
///
/// These values are safe to aggregate in local diagnostics: they identify the
/// failed contract, never the focused field's text, label, title, or path.
enum FocusedTextPreparationFailureReason: String, Codable, Equatable, Sendable {
  case frontmostApplicationUnavailable
  case focusedElementUnavailable
  case focusedElementProcessUnavailable
  case focusedElementProcessMismatch
  case secureField
  case selectedRangeSetterUnavailable
  case textMutationSetterUnavailable
  case selectedRangeUnavailable
  case selectedRangeInvalid
  case selectedRangeTooLarge
  case selectedTextUnavailable
  case selectedTextLengthMismatch
  case supportedMutationPathUnavailable
}

struct FocusedTextPreparationEvidence: Codable, Equatable, Sendable {
  let failureReason: FocusedTextPreparationFailureReason?
  let focusSource: FocusedTextFocusSource?
  let targetApplication: FocusedTextTargetApplication?

  init(
    failureReason: FocusedTextPreparationFailureReason? = nil,
    focusSource: FocusedTextFocusSource? = nil,
    targetApplication: FocusedTextTargetApplication? = nil
  ) {
    self.failureReason = failureReason
    self.focusSource = focusSource
    self.targetApplication = targetApplication
  }
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

enum FocusedTextWholeValueDecision: String, Codable, Equatable, Sendable {
  case eligibleTextField
  case eligibleEmptyTextArea
  case eligibleFullValueReplacement
  case eligiblePlainWebComposer
  case eligiblePlainWebSelection
  case eligibleSemanticallyEmptyWebComposer
  case rejectedValueUnavailableOrInconsistent
  case rejectedValueNotSettable
  case rejectedUnsupportedRole
  case rejectedNonWebTextArea
  case rejectedOversizedWebValue
  case rejectedObjectBearingWebValue
  case rejectedRichWebValue
  case rejectedAmbiguousWebSelection
  case rejectedPlaceholderBackedValue

  var permitsMutation: Bool {
    switch self {
    case .eligibleTextField, .eligibleEmptyTextArea, .eligibleFullValueReplacement,
      .eligiblePlainWebComposer, .eligiblePlainWebSelection,
      .eligibleSemanticallyEmptyWebComposer:
      true
    case .rejectedValueUnavailableOrInconsistent, .rejectedValueNotSettable,
      .rejectedUnsupportedRole, .rejectedNonWebTextArea, .rejectedOversizedWebValue,
      .rejectedObjectBearingWebValue, .rejectedRichWebValue,
      .rejectedAmbiguousWebSelection, .rejectedPlaceholderBackedValue:
      false
    }
  }
}

/// A bounded, content-free description of what Accessibility proves about a
/// web editor whose exposed AXValue does not match its visible editing state.
enum FocusedTextSemanticContentDecision: String, Codable, Equatable, Sendable {
  case notEvaluated
  case explicitSuggestionOnly
  case corroboratedLogicalEmpty
  case knownApplicationSuggestion
  case mixedSuggestionAndContent
  case logicalContentPresent
  case markedTextActive
  case evidenceUnavailable
  case evidenceInconsistent

  var provesEmptyComposer: Bool {
    self == .explicitSuggestionOnly || self == .corroboratedLogicalEmpty
      || self == .knownApplicationSuggestion
  }
}

enum FocusedTextSemanticSuggestionAttributeState: String, Codable, Equatable, Sendable {
  case notEvaluated
  case unavailable
  case suggestionOnly
  case mixed
  case notSuggestion
  case inconsistent
}

enum FocusedTextSemanticCharacterCountState: String, Codable, Equatable, Sendable {
  case notEvaluated
  case unavailable
  case zero
  case positive
  case invalid
}

enum FocusedTextSemanticTextMarkerState: String, Codable, Equatable, Sendable {
  case notEvaluated
  case unavailable
  case empty
  case nonempty
  case inconsistent
}

enum FocusedTextSemanticKnownSuggestionState: String, Codable, Equatable, Sendable {
  case notEvaluated
  case unrecognized
  case recognized
}

struct FocusedTextSemanticContentEvidence: Equatable, Sendable {
  static let notEvaluated = FocusedTextSemanticContentEvidence(
    decision: .notEvaluated,
    suggestionAttributeState: .notEvaluated,
    characterCountState: .notEvaluated,
    textMarkerState: .notEvaluated,
    knownSuggestionState: .notEvaluated
  )

  let decision: FocusedTextSemanticContentDecision
  let suggestionAttributeState: FocusedTextSemanticSuggestionAttributeState
  let characterCountState: FocusedTextSemanticCharacterCountState
  let textMarkerState: FocusedTextSemanticTextMarkerState
  let knownSuggestionState: FocusedTextSemanticKnownSuggestionState
}

enum FocusedTextKnownComposerSuggestionClassifier {
  private static let maximumSuggestionUTF16Length = 128
  private static let codexOrChatGPTSuggestions: Set<String> = [
    "Ask for follow-up changes"
  ]

  static func classify(
    _ value: String,
    application: FocusedTextTargetApplication
  ) -> FocusedTextSemanticKnownSuggestionState {
    guard application == .codexOrChatGPT else { return .notEvaluated }
    guard (value as NSString).length <= maximumSuggestionUTF16Length else {
      return .unrecognized
    }
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return codexOrChatGPTSuggestions.contains(normalized) ? .recognized : .unrecognized
  }
}

enum FocusedTextSemanticContentResolver {
  static func resolve(
    suggestionAttributeState: FocusedTextSemanticSuggestionAttributeState,
    characterCountState: FocusedTextSemanticCharacterCountState,
    textMarkerState: FocusedTextSemanticTextMarkerState,
    knownSuggestionState: FocusedTextSemanticKnownSuggestionState
  ) -> FocusedTextSemanticContentDecision {
    switch suggestionAttributeState {
    case .suggestionOnly:
      return .explicitSuggestionOnly
    case .mixed:
      return .mixedSuggestionAndContent
    case .inconsistent:
      return .evidenceInconsistent
    case .notEvaluated, .unavailable, .notSuggestion:
      if textMarkerState == .empty {
        return .corroboratedLogicalEmpty
      }
      if knownSuggestionState == .recognized,
        textMarkerState != .inconsistent,
        characterCountState != .invalid
      {
        return .knownApplicationSuggestion
      }
      if textMarkerState == .nonempty || characterCountState == .positive {
        return .logicalContentPresent
      }
      if textMarkerState == .inconsistent || characterCountState == .invalid {
        return .evidenceInconsistent
      }
      return .evidenceUnavailable
    }
  }
}

enum FocusedTextSuggestionClassifier {
  static func classify(
    _ attributedString: NSAttributedString,
    expectedValue: String
  ) -> FocusedTextSemanticContentDecision {
    let length = (expectedValue as NSString).length
    guard
      length > 0,
      attributedString.length == length,
      attributedString.string == expectedValue
    else { return .evidenceInconsistent }

    let suggestionKey = NSAttributedString.Key(kAXIsSuggestionStringAttribute as String)
    var coveredLength = 0
    var sawSuggestion = false
    var sawAuthoredContent = false
    attributedString.enumerateAttribute(
      suggestionKey,
      in: NSRange(location: 0, length: length),
      options: []
    ) { value, range, _ in
      coveredLength += range.length
      if (value as? NSNumber)?.boolValue == true {
        sawSuggestion = true
      } else {
        sawAuthoredContent = true
      }
    }

    guard coveredLength == length else { return .evidenceInconsistent }
    if sawSuggestion && !sawAuthoredContent { return .explicitSuggestionOnly }
    if sawSuggestion { return .mixedSuggestionAndContent }
    return .logicalContentPresent
  }
}

enum FocusedTextTargetApplication: String, Codable, Equatable, Sendable {
  case chrome
  case codexOrChatGPT
  case notion
  case notes
  case safari
  case terminal
  case visualStudioCode
  case other
  case unknown
}

enum FocusedTextSelectionRelation: String, Codable, Equatable, Sendable {
  case emptyValue
  case caretAtStart
  case caretAtEnd
  case caretInMiddle
  case fullValue
  case partialSelection
}

enum FocusedTextPlaceholderState: String, Codable, Equatable, Sendable {
  case absent
  case matchesValue
  case present
}

enum FocusedTextAttributeDecision: String, Codable, Equatable, Sendable {
  case notEvaluated
  case eligibleFontOnly
  case eligibleUniformPresentation
  case rejectedUnavailableOrInconsistent
  case rejectedMixedPresentation
  case rejectedSemanticOrUnknownAttribute
  case rejectedStyledFont

  var permitsMutation: Bool {
    switch self {
    case .eligibleFontOnly, .eligibleUniformPresentation:
      true
    case .notEvaluated, .rejectedUnavailableOrInconsistent, .rejectedMixedPresentation,
      .rejectedSemanticOrUnknownAttribute, .rejectedStyledFont:
      false
    }
  }
}

enum FocusedTextAttributeClassifier {
  static func classify(
    _ attributedString: NSAttributedString,
    expectedValue: String
  ) -> FocusedTextAttributeDecision {
    let length = (expectedValue as NSString).length
    guard
      length > 0,
      attributedString.length == length,
      attributedString.string == expectedValue
    else { return .rejectedUnavailableOrInconsistent }

    let stablePresentationKeys: Set<String> = [
      "AXFont",
      "AXForegroundColor",
      "AXBackgroundColor",
      "AXNaturalLanguage",
    ]
    let transientProofingKeys: Set<String> = [
      "AXMisspelled",
      "AXMarkedMisspelled",
      "AXAutocorrected",
    ]
    var stablePresentation: NSDictionary?
    var sawPresentationMetadata = false
    var decision = FocusedTextAttributeDecision.eligibleFontOnly

    attributedString.enumerateAttributes(
      in: NSRange(location: 0, length: length),
      options: []
    ) { attributes, _, stop in
      let keys = Set(attributes.keys.map(\.rawValue))
      guard keys.isSubset(of: stablePresentationKeys.union(transientProofingKeys)) else {
        decision = .rejectedSemanticOrUnknownAttribute
        stop.pointee = true
        return
      }

      let stable = [String: Any](
        uniqueKeysWithValues: attributes.compactMap { key, value in
          guard stablePresentationKeys.contains(key.rawValue) else { return nil }
          return (key.rawValue, value)
        }
      )
      guard stable.keys.contains("AXFont") else {
        decision = .rejectedSemanticOrUnknownAttribute
        stop.pointee = true
        return
      }
      let fontDescription = stable["AXFont"].map(String.init(describing:))?.lowercased() ?? ""
      guard !["bold", "italic", "oblique"].contains(where: fontDescription.contains) else {
        decision = .rejectedStyledFont
        stop.pointee = true
        return
      }

      let stableDictionary = NSDictionary(dictionary: stable)
      if let stablePresentation, !stablePresentation.isEqual(to: stable) {
        decision = .rejectedMixedPresentation
        stop.pointee = true
        return
      }
      stablePresentation = stableDictionary
      sawPresentationMetadata = sawPresentationMetadata || stable.count > 1 || attributes.count > 1
    }

    guard decision.permitsMutation else { return decision }
    return sawPresentationMetadata ? .eligibleUniformPresentation : .eligibleFontOnly
  }
}

struct FocusedTextTargetProfile: Codable, Equatable, Sendable {
  let role: FocusedTextTargetRole
  let canSetSelectedText: Bool
  let canSetSelectedRange: Bool
  let canSetValue: Bool
  let application: FocusedTextTargetApplication?

  init(
    role: FocusedTextTargetRole,
    canSetSelectedText: Bool,
    canSetSelectedRange: Bool,
    canSetValue: Bool,
    application: FocusedTextTargetApplication? = nil
  ) {
    self.role = role
    self.canSetSelectedText = canSetSelectedText
    self.canSetSelectedRange = canSetSelectedRange
    self.canSetValue = canSetValue
    self.application = application
  }
}

struct FocusedTextInsertionEvidence: Codable, Equatable, Sendable {
  let method: FocusedTextInsertionMethod
  let verification: FocusedTextInsertionVerification
  let target: FocusedTextTargetProfile
  let wholeValueDecision: FocusedTextWholeValueDecision?
  let selectionRelation: FocusedTextSelectionRelation?
  let placeholderState: FocusedTextPlaceholderState?
  let attributeDecision: FocusedTextAttributeDecision?
  let semanticContentDecision: FocusedTextSemanticContentDecision?
  let semanticSuggestionAttributeState: FocusedTextSemanticSuggestionAttributeState?
  let semanticCharacterCountState: FocusedTextSemanticCharacterCountState?
  let semanticTextMarkerState: FocusedTextSemanticTextMarkerState?
  let semanticKnownSuggestionState: FocusedTextSemanticKnownSuggestionState?

  init(
    method: FocusedTextInsertionMethod,
    verification: FocusedTextInsertionVerification,
    target: FocusedTextTargetProfile,
    wholeValueDecision: FocusedTextWholeValueDecision? = nil,
    selectionRelation: FocusedTextSelectionRelation? = nil,
    placeholderState: FocusedTextPlaceholderState? = nil,
    attributeDecision: FocusedTextAttributeDecision? = nil,
    semanticContentDecision: FocusedTextSemanticContentDecision? = nil,
    semanticSuggestionAttributeState: FocusedTextSemanticSuggestionAttributeState? = nil,
    semanticCharacterCountState: FocusedTextSemanticCharacterCountState? = nil,
    semanticTextMarkerState: FocusedTextSemanticTextMarkerState? = nil,
    semanticKnownSuggestionState: FocusedTextSemanticKnownSuggestionState? = nil
  ) {
    self.method = method
    self.verification = verification
    self.target = target
    self.wholeValueDecision = wholeValueDecision
    self.selectionRelation = selectionRelation
    self.placeholderState = placeholderState
    self.attributeDecision = attributeDecision
    self.semanticContentDecision = semanticContentDecision
    self.semanticSuggestionAttributeState = semanticSuggestionAttributeState
    self.semanticCharacterCountState = semanticCharacterCountState
    self.semanticTextMarkerState = semanticTextMarkerState
    self.semanticKnownSuggestionState = semanticKnownSuggestionState
  }
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
  /// The system-wide focused element. This remains the authoritative source
  /// whenever it returns an element.
  let focusedElement: () -> FocusedTextElementID?
  /// Bounded fallback queried only when the system-wide source is unavailable.
  let applicationFocusedElement: (pid_t) -> FocusedTextElementID?
  let frontmostApplicationProcessIdentifier: () -> pid_t?
  let sameElement: (FocusedTextElementID, FocusedTextElementID) -> Bool
  let processIdentifier: (FocusedTextElementID) -> pid_t?
  let targetApplication: (pid_t) -> FocusedTextTargetApplication
  let isSecure: (FocusedTextElementID) -> Bool
  let role: (FocusedTextElementID) -> FocusedTextTargetRole
  let webAreaAncestorDepth: (FocusedTextElementID) -> Int?
  let textAttributeDecision: (FocusedTextElementID, String) -> FocusedTextAttributeDecision
  let semanticContentEvidence:
    (FocusedTextElementID, String, FocusedTextTargetApplication)
      -> FocusedTextSemanticContentEvidence
  let placeholderValue: (FocusedTextElementID) -> String?
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

  init(
    focusedElement: @escaping () -> FocusedTextElementID?,
    applicationFocusedElement: @escaping (pid_t) -> FocusedTextElementID? = { _ in nil },
    frontmostApplicationProcessIdentifier: @escaping () -> pid_t? = { nil },
    sameElement: @escaping (FocusedTextElementID, FocusedTextElementID) -> Bool,
    processIdentifier: @escaping (FocusedTextElementID) -> pid_t?,
    targetApplication: @escaping (pid_t) -> FocusedTextTargetApplication,
    isSecure: @escaping (FocusedTextElementID) -> Bool,
    role: @escaping (FocusedTextElementID) -> FocusedTextTargetRole,
    webAreaAncestorDepth: @escaping (FocusedTextElementID) -> Int?,
    textAttributeDecision: @escaping (FocusedTextElementID, String) -> FocusedTextAttributeDecision,
    semanticContentEvidence:
      @escaping (FocusedTextElementID, String, FocusedTextTargetApplication)
      -> FocusedTextSemanticContentEvidence = { _, _, _ in
        FocusedTextSemanticContentEvidence(
          decision: .evidenceUnavailable,
          suggestionAttributeState: .unavailable,
          characterCountState: .unavailable,
          textMarkerState: .unavailable,
          knownSuggestionState: .notEvaluated
        )
      },
    placeholderValue: @escaping (FocusedTextElementID) -> String?,
    selectedText: @escaping (FocusedTextElementID) -> String?,
    selectedRange: @escaping (FocusedTextElementID) -> FocusedTextRange?,
    value: @escaping (FocusedTextElementID) -> String?,
    text: @escaping (FocusedTextElementID, FocusedTextRange) -> String?,
    textContext: @escaping (FocusedTextElementID, FocusedTextRange) -> FocusedTextContext,
    canSetSelectedText: @escaping (FocusedTextElementID) -> Bool,
    canSetSelectedRange: @escaping (FocusedTextElementID) -> Bool,
    canSetValue: @escaping (FocusedTextElementID) -> Bool,
    setSelectedText: @escaping (FocusedTextElementID, String) -> Bool,
    setSelectedRange: @escaping (FocusedTextElementID, FocusedTextRange) -> Bool,
    setValue: @escaping (FocusedTextElementID, String) -> Bool,
    waitForMutation: @escaping (Duration) async -> Void,
    release: @escaping (FocusedTextElementID) -> Void
  ) {
    self.focusedElement = focusedElement
    self.applicationFocusedElement = applicationFocusedElement
    self.frontmostApplicationProcessIdentifier = frontmostApplicationProcessIdentifier
    self.sameElement = sameElement
    self.processIdentifier = processIdentifier
    self.targetApplication = targetApplication
    self.isSecure = isSecure
    self.role = role
    self.webAreaAncestorDepth = webAreaAncestorDepth
    self.textAttributeDecision = textAttributeDecision
    self.semanticContentEvidence = semanticContentEvidence
    self.placeholderValue = placeholderValue
    self.selectedText = selectedText
    self.selectedRange = selectedRange
    self.value = value
    self.text = text
    self.textContext = textContext
    self.canSetSelectedText = canSetSelectedText
    self.canSetSelectedRange = canSetSelectedRange
    self.canSetValue = canSetValue
    self.setSelectedText = setSelectedText
    self.setSelectedRange = setSelectedRange
    self.setValue = setValue
    self.waitForMutation = waitForMutation
    self.release = release
  }

  static var live: Self {
    let registry = AccessibilityElementRegistry()
    return Self(
      focusedElement: { registry.focusedElement() },
      applicationFocusedElement: { registry.focusedElement(processIdentifier: $0) },
      frontmostApplicationProcessIdentifier: {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
      },
      sameElement: { registry.sameElement($0, $1) },
      processIdentifier: { registry.processIdentifier($0) },
      targetApplication: { registry.targetApplication(processIdentifier: $0) },
      isSecure: { registry.isSecure($0) },
      role: { registry.role($0) },
      webAreaAncestorDepth: { registry.webAreaAncestorDepth($0) },
      textAttributeDecision: { registry.textAttributeDecision($1, on: $0) },
      semanticContentEvidence: { registry.semanticContentEvidence($1, application: $2, on: $0) },
      placeholderValue: { registry.placeholderValue($0) },
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
    let wholeValueDecision: FocusedTextWholeValueDecision
    let selectionRelation: FocusedTextSelectionRelation
    let placeholderState: FocusedTextPlaceholderState
    let attributeDecision: FocusedTextAttributeDecision
    let semanticContentEvidence: FocusedTextSemanticContentEvidence
  }

  private enum FocusResolution {
    case resolved(FocusedTextElementID, pid_t, FocusedTextFocusSource)
    case failed(FocusedTextPreparationFailureReason)
  }

  private struct UndoReceipt {
    let element: FocusedTextElementID
    let processIdentifier: pid_t
    let replacedText: String
    let insertedText: String
    let insertedRange: FocusedTextRange
    let expectedCaret: FocusedTextRange
  }

  private let environment: FocusedTextInsertionEnvironment
  private var preparedTarget: PreparedTarget?
  private var undoReceipt: UndoReceipt?
  private(set) var latestPreparationEvidence: FocusedTextPreparationEvidence?

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
    latestPreparationEvidence = nil

    let focusResolution = resolveFocusedElement()
    let element: FocusedTextElementID
    let processIdentifier: pid_t
    let focusSource: FocusedTextFocusSource
    switch focusResolution {
    case .resolved(let resolvedElement, let resolvedProcessIdentifier, let resolvedSource):
      element = resolvedElement
      processIdentifier = resolvedProcessIdentifier
      focusSource = resolvedSource
    case .failed(let reason):
      latestPreparationEvidence = FocusedTextPreparationEvidence(failureReason: reason)
      return reason == .focusedElementUnavailable ? .noFocusedElement : .unsupportedField
    }
    guard !environment.isSecure(element) else {
      latestPreparationEvidence = FocusedTextPreparationEvidence(
        failureReason: .secureField,
        focusSource: focusSource,
        targetApplication: environment.targetApplication(processIdentifier)
      )
      environment.release(element)
      return .secureField
    }
    let profile = FocusedTextTargetProfile(
      role: environment.role(element),
      canSetSelectedText: environment.canSetSelectedText(element),
      canSetSelectedRange: environment.canSetSelectedRange(element),
      canSetValue: environment.canSetValue(element),
      application: environment.targetApplication(processIdentifier)
    )
    guard profile.canSetSelectedRange else {
      failPreparation(
        .selectedRangeSetterUnavailable,
        source: focusSource,
        profile: profile,
        releasing: element
      )
      return .unsupportedField
    }
    guard profile.canSetSelectedText || profile.canSetValue else {
      failPreparation(
        .textMutationSetterUnavailable,
        source: focusSource,
        profile: profile,
        releasing: element
      )
      return .unsupportedField
    }
    guard let selectedRange = environment.selectedRange(element) else {
      failPreparation(
        .selectedRangeUnavailable,
        source: focusSource,
        profile: profile,
        releasing: element
      )
      return .unsupportedField
    }
    guard
      selectedRange.location >= 0,
      selectedRange.length >= 0,
      selectedRange.location <= Int.max - selectedRange.length,
      selectedRange.endLocation <= Int.max - 2
    else {
      failPreparation(
        .selectedRangeInvalid,
        source: focusSource,
        profile: profile,
        releasing: element
      )
      return .unsupportedField
    }
    guard selectedRange.length <= Self.maximumSelectionUTF16Length else {
      failPreparation(
        .selectedRangeTooLarge,
        source: focusSource,
        profile: profile,
        releasing: element
      )
      return .unsupportedField
    }
    guard let selectedText = environment.selectedText(element) else {
      failPreparation(
        .selectedTextUnavailable,
        source: focusSource,
        profile: profile,
        releasing: element
      )
      return .unsupportedField
    }
    guard (selectedText as NSString).length == selectedRange.length else {
      failPreparation(
        .selectedTextLengthMismatch,
        source: focusSource,
        profile: profile,
        releasing: element
      )
      return .unsupportedField
    }

    let value = Self.validatedWholeValue(
      environment.value(element),
      selectedRange: selectedRange,
      selectedText: selectedText
    )
    let selectionRelation = Self.selectionRelation(value: value, selectedRange: selectedRange)
    let placeholderState = Self.placeholderState(
      value: value,
      placeholderValue: environment.placeholderValue(element)
    )
    var attributeDecision = FocusedTextAttributeDecision.notEvaluated
    var semanticContentEvidence = FocusedTextSemanticContentEvidence.notEvaluated
    let wholeValueDecision = Self.wholeValueDecision(
      profile: profile,
      value: value,
      selectedRange: selectedRange,
      selectionRelation: selectionRelation,
      placeholderState: placeholderState,
      webAreaAncestorDepth: environment.webAreaAncestorDepth(element),
      textAttributeDecision: {
        attributeDecision =
          value.map { environment.textAttributeDecision(element, $0) }
          ?? .rejectedUnavailableOrInconsistent
        return attributeDecision
      },
      semanticContentDecision: {
        semanticContentEvidence =
          value.map {
            environment.semanticContentEvidence(
              element,
              $0,
              profile.application ?? .unknown
            )
          }
          ?? FocusedTextSemanticContentEvidence(
            decision: .evidenceUnavailable,
            suggestionAttributeState: .unavailable,
            characterCountState: .unavailable,
            textMarkerState: .unavailable,
            knownSuggestionState: .notEvaluated
          )
        return semanticContentEvidence.decision
      }
    )
    guard profile.canSetSelectedText || wholeValueDecision.permitsMutation else {
      failPreparation(
        .supportedMutationPathUnavailable,
        source: focusSource,
        profile: profile,
        releasing: element
      )
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
      wholeValueDecision: wholeValueDecision,
      selectionRelation: selectionRelation,
      placeholderState: placeholderState,
      attributeDecision: attributeDecision,
      semanticContentEvidence: semanticContentEvidence
    )
    latestPreparationEvidence = FocusedTextPreparationEvidence(
      focusSource: focusSource,
      targetApplication: profile.application
    )
    return .ready
  }

  private func failPreparation(
    _ reason: FocusedTextPreparationFailureReason,
    source: FocusedTextFocusSource,
    profile: FocusedTextTargetProfile,
    releasing element: FocusedTextElementID
  ) {
    latestPreparationEvidence = FocusedTextPreparationEvidence(
      failureReason: reason,
      focusSource: source,
      targetApplication: profile.application
    )
    environment.release(element)
  }

  func discardPreparedTarget() {
    guard let preparedTarget else { return }
    environment.release(preparedTarget.element)
    self.preparedTarget = nil
  }

  /// Resolves one focused target without crossing application boundaries.
  ///
  /// The system-wide value is authoritative whenever present. The
  /// application-scoped lookup is attempted only when that primary lookup is
  /// unavailable, and only for the current frontmost process. During mutation
  /// revalidation, `expectedProcessIdentifier` also prevents an app switch from
  /// redirecting the insertion.
  private func resolveFocusedElement(
    expectedProcessIdentifier: pid_t? = nil
  ) -> FocusResolution {
    let frontmostProcessIdentifier = environment.frontmostApplicationProcessIdentifier()

    if let element = environment.focusedElement() {
      guard let elementProcessIdentifier = environment.processIdentifier(element) else {
        environment.release(element)
        return .failed(.focusedElementProcessUnavailable)
      }
      guard
        frontmostProcessIdentifier.map({ $0 == elementProcessIdentifier }) ?? true,
        expectedProcessIdentifier.map({ $0 == elementProcessIdentifier }) ?? true
      else {
        environment.release(element)
        return .failed(.focusedElementProcessMismatch)
      }
      return .resolved(element, elementProcessIdentifier, .systemWide)
    }

    guard let frontmostProcessIdentifier else {
      return .failed(.frontmostApplicationUnavailable)
    }
    guard
      expectedProcessIdentifier.map({ $0 == frontmostProcessIdentifier }) ?? true
    else {
      return .failed(.focusedElementProcessMismatch)
    }
    guard
      let element = environment.applicationFocusedElement(frontmostProcessIdentifier)
    else {
      return .failed(.focusedElementUnavailable)
    }
    guard
      environment.processIdentifier(element) == frontmostProcessIdentifier
    else {
      environment.release(element)
      return .failed(.focusedElementProcessMismatch)
    }
    return .resolved(element, frontmostProcessIdentifier, .frontmostApplication)
  }

  private func focusStillMatches(_ preparedTarget: PreparedTarget) -> Bool {
    let resolution = resolveFocusedElement(
      expectedProcessIdentifier: preparedTarget.processIdentifier
    )
    guard case .resolved(let focusedElement, _, _) = resolution else { return false }
    let matches = environment.sameElement(preparedTarget.element, focusedElement)
    environment.release(focusedElement)
    return matches
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

    guard focusStillMatches(preparedTarget) else {
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

    let insertionContext =
      preparedTarget.wholeValueDecision == .eligibleSemanticallyEmptyWebComposer
      ? FocusedTextContext() : preparedTarget.textContext
    let insertionText = Self.textForInsertion(text.value, context: insertionContext)
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
    let expectedValue =
      preparedTarget.wholeValueDecision == .eligibleSemanticallyEmptyWebComposer
      ? insertionText
      : preparedTarget.value.flatMap {
        Self.replacingSelection(
          in: $0,
          range: preparedTarget.selectedRange,
          with: insertionText
        )
      }

    discardUndoReceipt()

    if let expectedValue, preparedTarget.wholeValueDecision.permitsMutation {
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
        target: preparedTarget.profile,
        wholeValueDecision: preparedTarget.wholeValueDecision,
        selectionRelation: preparedTarget.selectionRelation,
        placeholderState: preparedTarget.placeholderState,
        attributeDecision: preparedTarget.attributeDecision,
        semanticContentDecision:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.decision,
        semanticSuggestionAttributeState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.suggestionAttributeState,
        semanticCharacterCountState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.characterCountState,
        semanticTextMarkerState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.textMarkerState,
        semanticKnownSuggestionState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.knownSuggestionState
      )

      switch verification {
      case .verified(let level):
        let canUndo = level == .contentAndCaret
        if canUndo {
          undoReceipt = UndoReceipt(
            element: preparedTarget.element,
            processIdentifier: preparedTarget.processIdentifier,
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
        target: preparedTarget.profile,
        wholeValueDecision: preparedTarget.wholeValueDecision,
        selectionRelation: preparedTarget.selectionRelation,
        placeholderState: preparedTarget.placeholderState,
        attributeDecision: preparedTarget.attributeDecision,
        semanticContentDecision:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.decision,
        semanticSuggestionAttributeState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.suggestionAttributeState,
        semanticCharacterCountState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.characterCountState,
        semanticTextMarkerState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.textMarkerState,
        semanticKnownSuggestionState:
          preparedTarget.semanticContentEvidence.decision == .notEvaluated
          ? nil : preparedTarget.semanticContentEvidence.knownSuggestionState
      )
    }

    guard !environment.isSecure(preparedTarget.element) else {
      environment.release(preparedTarget.element)
      return .secureField
    }
    guard focusStillMatches(preparedTarget) else {
      environment.release(preparedTarget.element)
      return .focusChanged
    }
    guard
      environment.role(preparedTarget.element) == preparedTarget.profile.role,
      environment.canSetValue(preparedTarget.element)
    else {
      environment.release(preparedTarget.element)
      return .unsupportedField
    }
    guard
      environment.value(preparedTarget.element) == preparedTarget.value,
      (expectedValue as NSString).length <= Self.maximumWholeValueUTF16Length
    else {
      environment.release(preparedTarget.element)
      return .selectionChanged
    }
    if preparedTarget.wholeValueDecision == .eligiblePlainWebComposer
      || preparedTarget.wholeValueDecision == .eligiblePlainWebSelection
    {
      let attributesStillEligible =
        preparedTarget.value.map { value in
          environment.textAttributeDecision(preparedTarget.element, value)
        } ?? .rejectedUnavailableOrInconsistent
      guard
        environment.webAreaAncestorDepth(preparedTarget.element) != nil,
        attributesStillEligible == preparedTarget.attributeDecision,
        attributesStillEligible.permitsMutation,
        Self.placeholderState(
          value: preparedTarget.value,
          placeholderValue: environment.placeholderValue(preparedTarget.element)
        ) == preparedTarget.placeholderState
      else {
        environment.release(preparedTarget.element)
        return .unsupportedField
      }
    }
    if preparedTarget.wholeValueDecision == .eligibleSemanticallyEmptyWebComposer {
      guard
        preparedTarget.profile.application == .codexOrChatGPT,
        environment.webAreaAncestorDepth(preparedTarget.element) != nil,
        environment.semanticContentEvidence(
          preparedTarget.element,
          preparedTarget.value ?? "",
          preparedTarget.profile.application ?? .unknown
        ) == preparedTarget.semanticContentEvidence,
        preparedTarget.semanticContentEvidence.decision.provesEmptyComposer
      else {
        environment.release(preparedTarget.element)
        return .unsupportedField
      }
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
    var semanticVerificationUnavailable = false

    for attempt in 0...Self.verificationRetryDelays.count {
      guard !Task.isCancelled else { return .unavailable }
      if attempt > 0 {
        await environment.waitForMutation(Self.verificationRetryDelays[attempt - 1])
      }
      guard !environment.isSecure(preparedTarget.element) else {
        return .secureField
      }
      guard focusStillMatches(preparedTarget) else { return .unavailable }

      let insertedRangeText = environment.text(preparedTarget.element, insertedRange)
      let currentValue = expectedValue.map { _ in environment.value(preparedTarget.element) }
      readMutationState = readMutationState || insertedRangeText != nil || currentValue != nil
      let contentMatches =
        insertedRangeText == insertedText
        || (expectedValue != nil && currentValue == expectedValue)
      guard contentMatches else { continue }

      if preparedTarget.wholeValueDecision == .eligibleSemanticallyEmptyWebComposer {
        guard let expectedValue else { continue }
        guard
          environment.semanticContentEvidence(
            preparedTarget.element,
            expectedValue,
            preparedTarget.profile.application ?? .unknown
          ).decision == .logicalContentPresent
        else {
          semanticVerificationUnavailable = true
          continue
        }
      }

      if environment.selectedRange(preparedTarget.element) == expectedCaret {
        return .verified(.contentAndCaret)
      }

      // Web content-editable surfaces can accept AXValue and then restore
      // their old DOM selection asynchronously. Once the single text mutation
      // is proven, reassert only the captured caret—never the value—and keep
      // the same focus and secure-field checks on every bounded retry.
      if expectedValue != nil,
        attempt < Self.verificationRetryDelays.count,
        environment.setSelectedRange(preparedTarget.element, expectedCaret)
      {
        continue
      }

      if attempt == Self.verificationRetryDelays.count {
        return .verified(.contentOnly)
      }
    }

    if semanticVerificationUnavailable { return .unavailable }
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

  private static func wholeValueDecision(
    profile: FocusedTextTargetProfile,
    value: String?,
    selectedRange: FocusedTextRange,
    selectionRelation: FocusedTextSelectionRelation,
    placeholderState: FocusedTextPlaceholderState,
    webAreaAncestorDepth: Int?,
    textAttributeDecision: () -> FocusedTextAttributeDecision,
    semanticContentDecision: () -> FocusedTextSemanticContentDecision
  ) -> FocusedTextWholeValueDecision {
    guard profile.role == .textField || profile.role == .textArea else {
      return .rejectedUnsupportedRole
    }
    guard profile.canSetValue else { return .rejectedValueNotSettable }
    guard let value else { return .rejectedValueUnavailableOrInconsistent }
    let length = (value as NSString).length
    if profile.role == .textField { return .eligibleTextField }
    if length == 0 { return .eligibleEmptyTextArea }
    guard placeholderState != .matchesValue else { return .rejectedPlaceholderBackedValue }
    if selectedRange.location == 0 && selectedRange.length == length {
      return .eligibleFullValueReplacement
    }
    guard webAreaAncestorDepth != nil else { return .rejectedNonWebTextArea }
    guard length <= maximumWebComposerUTF16Length else {
      return .rejectedOversizedWebValue
    }
    guard !value.contains("\u{FFFC}") else { return .rejectedObjectBearingWebValue }
    if profile.application == .codexOrChatGPT,
      selectionRelation == .caretAtStart,
      semanticContentDecision().provesEmptyComposer
    {
      return .eligibleSemanticallyEmptyWebComposer
    }
    let isPlainWebAppend = selectionRelation == .caretAtEnd
    let isBoundedNotionCaretInsertion =
      profile.application == .notion
      && (selectionRelation == .caretAtStart || selectionRelation == .caretInMiddle)
      && !value.contains("\n")
      && !value.contains("\r")
    guard isPlainWebAppend || isBoundedNotionCaretInsertion else {
      return .rejectedAmbiguousWebSelection
    }
    guard textAttributeDecision().permitsMutation else { return .rejectedRichWebValue }
    return isBoundedNotionCaretInsertion
      ? .eligiblePlainWebSelection : .eligiblePlainWebComposer
  }

  private static func selectionRelation(
    value: String?,
    selectedRange: FocusedTextRange
  ) -> FocusedTextSelectionRelation {
    guard let value else {
      return selectedRange.length == 0 ? .emptyValue : .partialSelection
    }
    let length = (value as NSString).length
    if length == 0 { return .emptyValue }
    if selectedRange.location == 0 && selectedRange.length == length { return .fullValue }
    if selectedRange.length > 0 { return .partialSelection }
    if selectedRange.location == 0 { return .caretAtStart }
    if selectedRange.location == length { return .caretAtEnd }
    return .caretInMiddle
  }

  private static func placeholderState(
    value: String?,
    placeholderValue: String?
  ) -> FocusedTextPlaceholderState {
    guard let placeholderValue, !placeholderValue.isEmpty else { return .absent }
    return value == placeholderValue ? .matchesValue : .present
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

    let focusResolution = resolveFocusedElement(
      expectedProcessIdentifier: undoReceipt.processIdentifier
    )
    guard case .resolved(let focusedElement, _, _) = focusResolution else {
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
      requiresSeparatorBeforeWord(after: last)
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

  private static func requiresSeparatorBeforeWord(after character: Character) -> Bool {
    isWordLike(character)
      || sentenceBoundaryPunctuation.contains(character)
      || closingDelimiters.contains(character)
  }

  private static let sentenceBoundaryPunctuation: Set<Character> = [
    ",", ".", ":", ";", "!", "?",
  ]

  private static let closingDelimiters: Set<Character> = [
    "\"", "'", ")", "]", "}",
  ]
}

@MainActor
private final class AccessibilityElementRegistry {
  private let systemWideElement = AXUIElementCreateSystemWide()
  private var elements: [FocusedTextElementID: AXUIElement] = [:]

  func focusedElement() -> FocusedTextElementID? {
    registerFocusedElement(from: systemWideElement)
  }

  func focusedElement(processIdentifier: pid_t) -> FocusedTextElementID? {
    registerFocusedElement(from: AXUIElementCreateApplication(processIdentifier))
  }

  private func registerFocusedElement(from source: AXUIElement) -> FocusedTextElementID? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(
        source,
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

  func targetApplication(processIdentifier: pid_t) -> FocusedTextTargetApplication {
    guard
      let bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?
        .bundleIdentifier
    else { return .unknown }

    switch bundleIdentifier {
    case "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary":
      return .chrome
    case "com.openai.codex", "com.openai.chat", "com.openai.chatgpt":
      return .codexOrChatGPT
    case "notion.id":
      return .notion
    case "com.apple.Notes":
      return .notes
    case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
      return .safari
    case "com.apple.Terminal", "com.googlecode.iterm2":
      return .terminal
    case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.visualstudio.code.oss":
      return .visualStudioCode
    default:
      return .other
    }
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

  func webAreaAncestorDepth(_ id: FocusedTextElementID) -> Int? {
    guard var current = elements[id] else { return nil }
    var visited: [AXUIElement] = []

    for depth in 0...32 {
      guard !visited.contains(where: { CFEqual($0, current) }) else { return nil }
      visited.append(current)
      if copyStringAttribute(kAXRoleAttribute as CFString, from: current) == "AXWebArea" {
        return depth
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
      else { return nil }
      let parent = unsafeDowncast(value, to: AXUIElement.self)
      guard !CFEqual(current, parent) else { return nil }
      current = parent
    }
    return nil
  }

  func textAttributeDecision(
    _ value: String,
    on id: FocusedTextElementID
  ) -> FocusedTextAttributeDecision {
    guard let element = elements[id] else { return .rejectedUnavailableOrInconsistent }
    let length = (value as NSString).length
    guard length > 0 else { return .eligibleFontOnly }
    var range = CFRange(location: 0, length: length)
    guard let parameter = AXValueCreate(.cfRange, &range) else {
      return .rejectedUnavailableOrInconsistent
    }
    var rawAttributedString: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXAttributedStringForRangeParameterizedAttribute as CFString,
        parameter,
        &rawAttributedString
      ) == .success,
      let attributedString = rawAttributedString as? NSAttributedString,
      attributedString.length == length,
      attributedString.string == value
    else { return .rejectedUnavailableOrInconsistent }

    return FocusedTextAttributeClassifier.classify(attributedString, expectedValue: value)
  }

  func semanticContentEvidence(
    _ value: String,
    application: FocusedTextTargetApplication,
    on id: FocusedTextElementID
  ) -> FocusedTextSemanticContentEvidence {
    guard let element = elements[id], !value.isEmpty else {
      return FocusedTextSemanticContentEvidence(
        decision: .evidenceUnavailable,
        suggestionAttributeState: .unavailable,
        characterCountState: .unavailable,
        textMarkerState: .unavailable,
        knownSuggestionState: .notEvaluated
      )
    }

    var markedText: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      element,
      kAXTextInputMarkedTextMarkerRangeAttribute as CFString,
      &markedText
    ) == .success, markedText != nil {
      return FocusedTextSemanticContentEvidence(
        decision: .markedTextActive,
        suggestionAttributeState: .notEvaluated,
        characterCountState: .notEvaluated,
        textMarkerState: .notEvaluated,
        knownSuggestionState: .notEvaluated
      )
    }

    let suggestionAttributeState = suggestionAttributeState(value, in: element)
    let characterCountState = characterCountState(in: element)
    let textMarkerState = textMarkerState(in: element)
    let knownSuggestionState = FocusedTextKnownComposerSuggestionClassifier.classify(
      value,
      application: application
    )

    // Chromium can expose suggestion chrome through AXValue and
    // AXNumberOfCharacters while the editor-specific marker range remains
    // empty. The resolver therefore evaluates all signals before deciding.
    // The exact known-suggestion rule is app-scoped and revalidated immediately
    // before mutation when stronger native suggestion metadata is absent.
    let decision = FocusedTextSemanticContentResolver.resolve(
      suggestionAttributeState: suggestionAttributeState,
      characterCountState: characterCountState,
      textMarkerState: textMarkerState,
      knownSuggestionState: knownSuggestionState
    )

    return FocusedTextSemanticContentEvidence(
      decision: decision,
      suggestionAttributeState: suggestionAttributeState,
      characterCountState: characterCountState,
      textMarkerState: textMarkerState,
      knownSuggestionState: knownSuggestionState
    )
  }

  private func suggestionAttributeState(
    _ value: String,
    in element: AXUIElement
  ) -> FocusedTextSemanticSuggestionAttributeState {
    guard let attributedString = attributedString(value, in: element) else {
      return .unavailable
    }
    switch FocusedTextSuggestionClassifier.classify(
      attributedString,
      expectedValue: value
    ) {
    case .explicitSuggestionOnly:
      return .suggestionOnly
    case .mixedSuggestionAndContent:
      return .mixed
    case .logicalContentPresent:
      return .notSuggestion
    case .evidenceInconsistent:
      return .inconsistent
    case .notEvaluated, .corroboratedLogicalEmpty, .knownApplicationSuggestion,
      .markedTextActive, .evidenceUnavailable:
      return .inconsistent
    }
  }

  private func characterCountState(
    in element: AXUIElement
  ) -> FocusedTextSemanticCharacterCountState {
    guard
      let characterCount = numberAttribute(
        kAXNumberOfCharactersAttribute as CFString,
        from: element
      )
    else { return .unavailable }
    guard characterCount >= 0 else { return .invalid }
    return characterCount == 0 ? .zero : .positive
  }

  private func textMarkerState(
    in element: AXUIElement
  ) -> FocusedTextSemanticTextMarkerState {
    guard let webArea = webAreaAncestor(of: element) else { return .unavailable }
    var fullRange: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        webArea,
        kAXTextMarkerRangeForUIElementParameterizedAttribute as CFString,
        element,
        &fullRange
      ) == .success,
      let fullRange
    else { return .unavailable }

    var lengthValue: CFTypeRef?
    var stringValue: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        webArea,
        kAXLengthForTextMarkerRangeParameterizedAttribute as CFString,
        fullRange,
        &lengthValue
      ) == .success,
      AXUIElementCopyParameterizedAttributeValue(
        webArea,
        kAXStringForTextMarkerRangeParameterizedAttribute as CFString,
        fullRange,
        &stringValue
      ) == .success,
      let markerLength = (lengthValue as? NSNumber)?.intValue,
      let markerString = stringValue as? String
    else { return .unavailable }

    guard markerLength >= 0 else { return .inconsistent }
    let stringLength = (markerString as NSString).length
    guard markerLength == stringLength else { return .inconsistent }
    return markerLength == 0 ? .empty : .nonempty
  }

  private func attributedString(
    _ value: String,
    in element: AXUIElement
  ) -> NSAttributedString? {
    let length = (value as NSString).length
    var range = CFRange(location: 0, length: length)
    guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
    var rawValue: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        element,
        kAXAttributedStringForRangeParameterizedAttribute as CFString,
        parameter,
        &rawValue
      ) == .success,
      let attributedString = rawValue as? NSAttributedString,
      attributedString.length == length,
      attributedString.string == value
    else { return nil }
    return attributedString
  }

  private func numberAttribute(_ attribute: CFString, from element: AXUIElement) -> Int? {
    var value: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
      let number = value as? NSNumber
    else { return nil }
    return number.intValue
  }

  private func webAreaAncestor(of element: AXUIElement) -> AXUIElement? {
    var current = element
    var visited: [AXUIElement] = []
    for _ in 0...32 {
      guard !visited.contains(where: { CFEqual($0, current) }) else { return nil }
      visited.append(current)
      if copyStringAttribute(kAXRoleAttribute as CFString, from: current) == "AXWebArea" {
        return current
      }
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &value) == .success,
        let value,
        CFGetTypeID(value) == AXUIElementGetTypeID()
      else { return nil }
      current = unsafeDowncast(value, to: AXUIElement.self)
    }
    return nil
  }

  func placeholderValue(_ id: FocusedTextElementID) -> String? {
    guard let element = elements[id] else { return nil }
    return copyStringAttribute(kAXPlaceholderValueAttribute as CFString, from: element)
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
