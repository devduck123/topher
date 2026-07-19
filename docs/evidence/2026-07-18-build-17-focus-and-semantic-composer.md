# Build 17 focus recovery and semantic composer evidence

- Date: 2026-07-18
- Version: 0.4.0 (17)
- Branch: `codex/global-dictation-foundation`
- Scope: automated source, concurrency, native-boundary, bundle, install, and
  launch verification. Live cross-application acceptance remains pending.

## Observed problems addressed

Build 16 dogfooding reported reliable Notion append but no insertion into
Codex/ChatGPT, Visual Studio Code, or Terminal. Codex exposed the built-in “Ask
for follow-up changes” suggestion as a nonempty Accessibility value at a
caret-at-start selection. A harder developer sentence also surfaced several
misspelled technical terms in one transcript.

## Implemented boundary

- System-wide focus remains authoritative. If and only if it is unavailable,
  Topher queries the frontmost application's focused element. Preparation,
  insertion, verification, and undo remain bound to one process identifier.
- Preparation diagnostics retain only a fixed focus source, known application
  family, and fixed failure reason. Terminal and Visual Studio Code are now
  recognized families.
- Codex/ChatGPT caret-at-start whole-value replacement is eligible only when the
  full attributed value is suggestion-only or both character-count and full web
  text-marker evidence prove logical emptiness. The proof is re-read before one
  write; post-write content must be exact and semantically authored. Evidence
  drift causes zero writes, and missing post-write semantic evidence produces an
  uncertain result rather than false success.
- The semantic-empty path writes the transcript alone. It never appends the
  suggestion, writes selected text, submits, presses Return, or changes the
  clipboard.
- Terminal remains a specific review/copy fallback. VS Code receives only the
  bounded focus recovery and still requires a standard writable Accessibility
  editor surface.
- One Apple alternative may correct multiple known developer terms only when
  every changed lexical span is an independently known, unique correction.
  Dictation-only risky spoken forms do not expand command vocabulary.

## Automated verification

The following completed successfully against the final source:

```text
ruby scripts/check_dependency_parity.rb
ruby scripts/check_dogfood_corpus.rb
ruby scripts/test_observed_query_export.rb
xcrun swift-format lint --strict -r Package.swift Sources Tests
swift test
swift test --sanitize=thread
xcodebuild ... Debug ... build
xcodebuild ... Release ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
xcodebuild ... Debug ... analyze
git diff --check
```

- The public corpus contains 32 validated cases.
- All 276 Swift tests passed normally.
- All 276 Swift tests passed under Thread Sanitizer with no sanitizer report.
- Xcode Debug build, universal Release build, and static analysis succeeded.
- Targeted tests prove: system focus precedence; frontmost-app fallback;
  cross-PID refusal; PID drift refusal; secure-field early refusal; precise
  preparation failures; full suggestion-only coverage; mixed/authored refusal;
  Codex transcript-only whole-value mutation; zero writes after semantic drift;
  uncertain outcome when post-write semantics disappear; explicit Terminal
  fallback; persisted preparation evidence; multiple developer-term correction;
  ambiguity refusal; and no correction-form leakage into commands.
- Dependency parity, diagnostic exporter tests, dogfood corpus validation,
  strict Swift formatting, whitespace checks, and a credential-pattern scan all
  passed.

## Release bundle and installation

The checked Release product reported:

- bundle identifier `dev.topher.app`;
- version `0.4.0`, build `17`;
- `LSUIElement = true`;
- universal `x86_64 arm64` executable;
- valid strict ad-hoc signature with Hardened Runtime;
- only `com.apple.security.device.audio-input` in Release entitlements;
- no detected credential pattern in tracked source/config inputs.

The checked installer reset only `dev.topher.app` Accessibility consent,
installed the Release bundle to `/Applications/Topher.app`, launched exactly one
Topher process, and reverified the installed signature. The source and installed
executables had the same SHA-256:

```text
73140e8cdfa92fa79bfbd726cae547e773df97b5a7e31e7a5b03261afc628d95
```

## Explicitly unverified

Automated tests cannot certify how the current Codex, ChatGPT, VS Code, Terminal,
Notion, or Chrome releases expose their live Accessibility trees. The user must
re-enable Accessibility for Build 17 and run the Build 17 corpus cases. In
particular, verify the exact Codex suggestion regression, Codex authored-text
refusal, VS Code with screen-reader optimized mode enabled, Terminal's
non-mutating fallback, Notion append, Chrome/Notion empty insertion, menu
diagnostics/ratings, multi-term developer recognition, IME/emoji/rich-content
refusal, app-switch races, sleep/wake, and repeated holds. No source-only result
in this record claims those interactive paths passed.
