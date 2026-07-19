# Build 16 semantic web append and menu feedback evidence

Date: 2026-07-16

## Trigger

Build 15 dogfooding exposed two reliability problems. A visually empty Codex
composer surfaced its suggestion text as a writable Accessibility value, so a
mechanically verified whole-value rewrite produced the user's transcript plus
`Ask for follow-up changes`. A Notion block with existing plain text did not
append because its attributed representation was more complex than the prior
single font-only run contract. The redesigned menu also removed the convenient
view and ratings for the latest local dogfood records.

## Change

- Classify the captured selection as empty, start, end, middle, full-value, or
  partial without retaining its location or content.
- Reject nonempty web whole-value insertion unless the selection is an empty
  caret exactly at the value end.
- Reject a whole-value write when the standard Accessibility placeholder equals
  the exposed value, preventing host suggestion text from being treated as an
  authored draft.
- Replace the single-run font check with a bounded attributed-run classifier.
  It permits a normal font with uniform foreground, background, or language
  presentation and varying proofing metadata; it rejects styled fonts,
  semantic or unknown attributes, and mixed presentation.
- Revalidate the web ancestry, placeholder state, and exact attribute decision
  immediately before the one permitted write. A changed surface fails closed.
- Retain only a fixed application family and structural classification enums in
  the local trace. No raw bundle identifier, process ID, window title, URL,
  selection, additional field content, or attributed value is persisted.
- Restore the latest three local records to the menu with independent
  transcript and action/insertion ratings, fixed issue tags for negative action
  feedback, and a route to the complete Developer view.
- Persist the selected Settings section so **View all** opens Developer rather
  than returning to General.
- Add sanitized Codex suggestion-refusal, Codex mid-draft refusal, and plain
  Notion end-append cases to the 28-case manual corpus.

The safety and compatibility tradeoff is recorded in
[decision 0019](../decisions/0019-require-semantic-web-append-evidence.md).

## Automated verification

- dependency parity passed;
- the 28-case sanitized dogfood corpus passed validation;
- the observed-query exporter fixture passed with the new fixed structural
  aggregate fields;
- strict Swift formatting, Xcode-project plist validation, a bounded
  credential-pattern scan, and `git diff --check` passed;
- all 256 tests passed normally;
- all 256 tests passed under Thread Sanitizer with no sanitizer report;
- Xcode Debug build passed;
- universal Xcode Release build passed; and
- Xcode Debug static analysis passed.

Regression coverage includes pre-Build-16 diagnostic decoding; uniform
presentation with varying proofing metadata; unknown, styled, and mixed
attribute refusal; exact Codex suggestion/caret-at-start refusal with zero value
writes; placeholder-backed refusal; verified Notion-like end append; mid-value
web refusal; pre-write attribute revalidation; exactly-one mutation behavior;
fixed diagnostic persistence/export; three-record menu policy; and stable
Developer-section routing.

## Release product verification

The checked Release product reported:

```text
CFBundleIdentifier = dev.topher.app
CFBundleShortVersionString = 0.4.0
CFBundleVersion = 16
LSUIElement = true
architectures = x86_64 arm64
executable SHA-256 = 82a814cec94802c7918b483567cbedc29939d3d818fcae4a7fe2d3b1e992a750
```

Strict signature verification passed. Release entitlements still contain only
`com.apple.security.device.audio-input`; this change adds no entitlement,
networking, Automation/Apple Events, Screen Recording, direct browser control,
clipboard automation, synthetic key, Return, submission, or send capability.

The installer reset only Topher's Accessibility decision, installed the exact
checked artifact at `/Applications/Topher.app`, and launched it. The installed
bundle reported version 0.4.0 build 16, universal `x86_64 arm64` architectures,
and a valid strict signature. Its executable SHA-256 exactly matched the checked
Release product, and one installed Topher process was running after launch.

The reset intentionally leaves Accessibility unapproved until the user grants
it again in System Settings. Installation and process liveness do not prove
permission recovery, menu presentation, or editor compatibility.

## Remaining live acceptance

Automated seams cannot prove what the user's current Codex, ChatGPT, Notion, or
other embedded web editor exposes through Accessibility, nor can they visually
certify the menu-bar popover. With the exact checked Build 16 artifact installed,
run these prioritized checks:

1. Approve Topher under **System Settings → Privacy & Security → Accessibility**
   when prompted, then confirm Topher reports global text insertion ready.
2. Open the menu and confirm the newest three records are readable, independently
   rateable, and **View all** opens **Settings → Developer**.
3. Focus a visually empty Codex composer that shows `Ask for follow-up changes`,
   dictate once, and confirm the suggestion is never appended or prepended. A
   safe local-review fallback is acceptable; sending is not.
4. Focus the caret at the end of a short existing plain Notion block and dictate
   once. Confirm one append with preserved existing text and no submission.
5. Put the caret in the middle of a Codex/ChatGPT or Notion draft and confirm the
   whole-value adapter refuses it without altering the draft.
6. Try a link, mention, list, authored style, and attachment using non-sensitive
   test content. Confirm every rich/semantic case remains unchanged and falls
   back for review.
7. Inspect the retained records. They should identify only the fixed application
   family, selection relation, placeholder state, attribute decision, mutation
   method, and readback result needed to explain the outcome.

Live third-party compatibility, menu layout, Accessibility permission recovery,
IME/non-Latin text, real latency, and repeated-session stability remain
unverified. This checkpoint does not claim universal editor compatibility or
Wispr-style transcription accuracy.
