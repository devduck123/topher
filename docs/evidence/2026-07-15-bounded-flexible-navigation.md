# Bounded flexible navigation evidence

Date: 2026-07-15

## Dogfood input

Build 5 retained ten voice requests with both user ratings. All ten transcripts
were rated accurate, while five actions were rated incorrect. The incorrect
actions clustered in deterministic behavior: two Chrome Extensions handoffs,
two destination-first YouTube queries, and one explicit domain navigation.
This small rated set is useful product evidence, not a speech word-error-rate
benchmark.

Apple's final transcript included sentence punctuation in “Open YouTube for
dining with Derek.” The raw transcript remains unchanged. Build 6 removes one
likely terminal sentence mark only from the extracted command query/domain;
future text dictation remains a separate formatting path.

## Build 6 behavior

- Chrome Extensions is delivered as `chrome://extensions/` to the installed
  Chrome application through `NSWorkspace.open(_:withApplicationAt:...)`.
  Unlike launch arguments, this handoff applies when Chrome is already running.
- Exact allowlisted targets accept terse forms such as “Notes,” “Notion,” “VS
  Code,” “YouTube,” and “GitHub.”
- Known search providers accept destination-first forms including “YouTube for
  dining with Derek,” “YouTube, dining with Derek,” and “Google: local macOS
  speech recognition.”
- Explicit navigation verbs may produce the new typed `HTTPSDomain` command.
  It forces HTTPS and rejects paths, credentials, ports, IP addresses, custom
  schemes, and local/reserved names.
- Known targets resolve before arbitrary domains. The observed `gidhub.com`
  spelling remains a bounded GitHub alias rather than navigating to an
  unintended lookalike host.
- Diagnostics identify explicit domain navigation separately as `openDomain`.

## Automated verification

- Focused final resolver/processor/diagnostics suite: 51 tests, 0 failures.
- `swift test`: 151 tests, 0 failures.
- `swift test --sanitize=thread`: 151 tests, 0 failures.
- Strict recursive `swift-format` lint passed.
- Dependency parity, Ruby syntax, project-plist validation, `git diff --check`,
  and repository credential-pattern/file scans passed.
- Unsigned universal Release build succeeded; the executable contains `arm64`
  and `x86_64`.
- Xcode Release static analysis succeeded.
- Signed arm64 Release `0.3.0 (6)` passed deep strict signature validation with
  only the audio-input entitlement. Its executable SHA-256 is
  `c2893ab2ef4b6d59ef9404420bd5960377bfb7741f92dfedc5b6a08660f32fe6`.

## Remaining live proof

The bundle has not been installed during this implementation pass. A manual
build-6 dogfood check must still confirm Chrome Extensions with Chrome already
running and the new phrase variants through the real microphone. macOS
accepting an `NSWorkspace` handoff is not proof that Topher inspected the final
browser page; screen-aware verification remains future work.
