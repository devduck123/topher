# Build 18 semantic signals and Notion caret verification

- Date: 2026-07-18
- Version: 0.4.0 (18)
- Scope: source, automated tests, native analysis, and local Release bundle
- Live app acceptance: pending

## Change under verification

Build 18 follows the failed Build 17 dogfood session in which Codex/ChatGPT
focus discovery succeeded but the visible empty-composer suggestion was
classified as authored content. It:

- evaluates suggestion attribution, character count, full web text-marker
  state, and exact known-suggestion state independently;
- checks an empty text-marker range before treating positive character count as
  authored content;
- accepts only the exact bounded `Ask for follow-up changes` value as the
  current Codex/ChatGPT compatibility suggestion, with unchanged evidence
  required immediately before one whole-value mutation;
- requires exact post-write text plus authored-content evidence and performs no
  selected-text write on the semantic path;
- permits Notion whole-value insertion at a start or middle caret only for a
  bounded, object-free, single-line, uniformly presented value;
- retains the fixed semantic signal states in local diagnostics and exporters;
  and
- allows `get status` to become `git status` only from one uniquely
  corroborating Apple alternative.

## Automated verification

The checked tree passed:

```text
ruby scripts/check_dependency_parity.rb
ruby scripts/check_dogfood_corpus.rb
ruby scripts/test_observed_query_export.rb
ruby -c scripts/summarize_dogfood_diagnostics.rb
ruby -c scripts/export_observed_queries.rb
xcrun swift-format lint --strict -r Package.swift Sources Tests
swift test
swift test --sanitize=thread
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug build
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug analyze
git diff --check
```

Normal and Thread Sanitizer runs each executed 283 tests with zero failures.
The sanitized public dogfood corpus contains 35 cases. Focused insertion tests
cover:

- exact and application-scoped known-suggestion classification;
- text-marker emptiness taking precedence over suggestion-inflated character
  count;
- mixed suggestion/authored content refusal;
- Codex suggestion replacement with no selected-text mutation;
- semantic evidence drift before mutation;
- missing post-write authored-content evidence;
- authored/ambiguous Codex value preservation;
- Notion start, middle, and end insertion with contextual spacing;
- Notion multiline and rich-content refusal; and
- fixed semantic signal persistence and private-export aggregation.

Dictation selector tests require an exact Apple alternative for `git` and
reject alternatives that also change the command or unrelated prose.

## Release bundle verification

The exact checked artifact is:

```text
/tmp/topher-build18-release/Build/Products/Release/Topher.app
```

It reports version `0.4.0 (18)`, `LSUIElement = true`, and a universal
`x86_64 arm64` executable. Strict deep signature verification and the designated
requirement check pass. The signature is local ad hoc with Hardened Runtime; the
only entitlement is `com.apple.security.device.audio-input`. The executable
SHA-256 is:

```text
e58600c2367af1a61098e3b53aabc9cdba2be946fcf0c3960401feae914d4e48
```

A credential-pattern scan found only ordinary in-process generation and
diagnostic token variable names; no credential value or private-key marker was
found.

## Unverified manual acceptance

This record does not claim that Build 18 is installed or that live insertion
works in current Codex/ChatGPT or Notion builds. Before calling the branch ready
to merge, install the exact checked bundle with an explicit Accessibility reset,
approve the new binary, and test:

1. Codex's empty composer showing `Ask for follow-up changes` inserts only the
   transcript and never appends the suggestion.
2. Authored Codex text at the start remains unchanged and produces review/copy
   fallback.
3. A plain single-line Notion block inserts at start, middle, and end exactly
   once with correct spacing.
4. Multiline, linked, mentioned, listed, styled, and object-bearing Notion
   content remains unchanged.
5. Notes inserts normally; VS Code is checked with screen-reader optimized mode;
   Terminal remains an explicit non-mutating fallback.
6. `git status` and the React/Next.js/Vercel/Kubernetes phrase are rated for
   both transcription and insertion.
7. Diagnostics show the fixed semantic signal bundle and no duplicate or
   falsely successful mutation.

Permission persistence, sleep/wake, audio-route changes, long sessions, and
controlled speech accuracy/latency remain separate dogfood gates.
