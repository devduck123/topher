# Build 19 caret, composition, and query-formatting verification

- Date: 2026-07-19
- Version: 0.4.0 (19)
- Scope: source, automated tests, concurrency checks, native analysis, and local Release bundle
- Live Build 19 acceptance: pending

## Dogfood findings addressed

The installed Build 18 session confirmed successful empty and end-append Codex
insertion and Notion start, middle, end, and indented-block insertion. It also
showed:

- the semantic-empty Codex whole-value path verified content but left the caret
  at the beginning;
- a punctuated Notion prepend omitted the separator before existing text;
- authored Codex bullet content exposed no verifiable selected-text mutation;
- `Search Chrome for ... UI slash UX ...` executed once but preserved the
  spoken notation in the query; and
- Apple selected `Kodex` and `impending` in two developer-context phrases.

Build 19 keeps ambiguous Codex content fail-closed and addresses the remaining
gaps with the boundary documented in decision 0022.

## Change under verification

- A permitted whole-value path still performs exactly one value mutation. After
  exact content readback, it may reassert only the expected caret and requires a
  delayed stable range readback under unchanged focus and secure state.
- Insertion composition adds one separator when punctuated dictated text is
  placed before existing word-like text.
- The narrow uppercase-token spoken-slash formatter is shared by dictation and
  extracted search-query payloads. Raw diagnostics remain unchanged and
  lowercase prose remains literal.
- `Kodex` → `Codex` and `impending` → `prepending` require one exact
  vocabulary-equivalent Apple alternative; neither primary transcript is
  rewritten without corroboration.
- Authored or ambiguous Codex start/middle content retains the review/copy
  fallback and now explains that Topher left the content unchanged.

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
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug -derivedDataPath /tmp/topher-build19-debug build
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Release -derivedDataPath /tmp/topher-build19-release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
xcodebuild -project Topher.xcodeproj -scheme TopherApp -configuration Debug -derivedDataPath /tmp/topher-build19-analyze analyze
git diff --check
```

Normal and Thread Sanitizer runs each executed 289 tests with zero failures.
The sanitized public dogfood corpus contains 39 cases. New regression coverage
proves:

- an ignored first web-caret write is retried and rechecked after a delay;
- the value is written exactly once while the caret ends at the expected range;
- punctuated Notion prepends include one separator;
- strong-token slash normalization is identical in dictation and web-search
  payloads while lowercase prose is preserved;
- observed developer corrections require exact Apple-alternative evidence; and
- authored Codex content is unchanged and receives the specific safe fallback.

Dependency parity, exporter behavior, Ruby syntax, strict Swift formatting, and
whitespace checks passed. A credential-pattern scan found no private-key marker
or common token-shaped credential value.

## Release bundle verification

The exact checked artifact is:

```text
/tmp/topher-build19-release/Build/Products/Release/Topher.app
```

It reports version `0.4.0 (19)`, `LSUIElement = true`, and a universal
`x86_64 arm64` executable. Strict deep signature and designated-requirement
verification pass. The signature is local ad hoc with Hardened Runtime; it has
no Team identifier and its only entitlement is
`com.apple.security.device.audio-input`. The executable SHA-256 is:

```text
03d578a12aa5be3dd25bcffd31ee49525db120b5ac4a943413fc837f4a077398
```

## Unverified manual acceptance

Build 19 has not been installed. Before calling this checkpoint accepted in the
live app, replace Build 18 through the checked installer and verify:

1. Empty Codex insertion replaces only the known suggestion and leaves the
   caret at the end after a short observation delay.
2. A second Codex end-append inserts once at the expected position.
3. Authored Codex bullet start/middle insertion leaves content unchanged and
   shows the specific review/copy explanation.
4. A punctuated Notion prepend contains one separator before the original word;
   start, middle, end, and indented-block behavior otherwise remains intact.
5. `Search Chrome for what are some good UI slash UX principles?` opens exactly
   one search whose query contains `UI/UX`.
6. `Kodex`/`Codex` and `impending`/`prepending` results are rated separately for
   raw transcription and selected alternative behavior.
7. Diagnostics show `contentAndCaret` for supported whole-value insertions and
   no duplicate value mutation or false success.

VS Code, Terminal, rich editors, permission persistence, sleep/wake,
audio-route changes, long sessions, and controlled speech accuracy/latency
remain separate acceptance gates.
