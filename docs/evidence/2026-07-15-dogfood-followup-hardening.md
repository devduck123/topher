# Dogfood follow-up hardening

Date: 2026-07-15

This checkpoint responds to the first nine-request personalized-command smoke
test. The run produced seven successful allowlisted actions and two correctly
transcribed but unsupported application requests. No Topher crash or capture
failure was observed.

## Findings converted into changes

- “Search Chrome Extensions” succeeded but was unnecessarily interpreted as
  “Search Google Chrome Extensions.” Canonical recognition context, known ASR
  mistakes, and valid resolver aliases are now separate concepts.
- Apple receives only canonical desired terms. Strings representing known bad
  recognizer output, such as `gidhub`, remain interpreter-only.
- Already-resolved application and website wording is preserved. Search-query
  correction remains available for explicit developer or personal corrections
  such as `get lab` to `GitLab`, without changing search provider.
- The installed ChatGPT/Codex application is allowlisted with verified bundle
  identifier `com.openai.codex`; Xcode is allowlisted as `com.apple.dt.Xcode`.
- Dogfood build number advances from 3 to 4 so new diagnostic records can be
  distinguished from the earlier installed candidate.
- Voice evidence now carries monotonic hold-to-listening,
  listening-to-first-transcript, and key-up-to-final durations into the bounded
  local diagnostic record. Command processing duration remains separate.

## Scope boundary

The progressive-versus-accuracy preset tradeoff and a custom pronunciation
language model remain benchmark experiments. This checkpoint does not add a
second speech engine, retain audio, inspect browser tabs, read screen content,
or grant a model execution authority.

## Automated verification

- Strict recursive `swift-format` lint passed.
- `swift test` passed 133 tests with zero failures.
- The same 133 tests passed under Thread Sanitizer with no reported data race.
- Dependency parity passed for KeyboardShortcuts 3.0.1 across SwiftPM, Xcode,
  and both lockfiles.
- The unsigned universal Release app built successfully and contains arm64 and
  x86_64 executable slices. Its bundle build number is 4.
- Debug `xcodebuild analyze` succeeded. Xcode emitted only the existing App
  Intents metadata warning because Topher does not link AppIntents.
- `git diff --check` and a targeted credential-term scan passed.
