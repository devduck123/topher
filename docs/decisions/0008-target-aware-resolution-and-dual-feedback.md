# 0008: Target-aware resolution and dual dogfood feedback

Status: accepted, 2026-07-15

## Context

Dogfood requests exposed two separate problems. The deterministic resolver did
not yet understand several known destinations or target-specific actions, and a
successful capability outcome could not reveal whether speech recognition or
intent selection was actually correct. For example, “Search Google and open my
Gmail” previously became one Google query even though it contains two actions.

## Decision

- Keep applications, websites, browser-owned routes, search providers, and
  search values as separate typed targets.
- Give known destinations bounded target-specific semantics. Google and YouTube
  may accept a query in phrases such as “Open YouTube for …”; Gmail remains a
  homepage destination; Chrome Extensions is a fixed Chrome-owned route.
- Continue to prefer known website identity over a similarly named native app
  for phrases such as “Open Crunchyroll.” Unknown query subjects still use
  Google through the configured default browser.
- Reject a request as compound only when text on both sides of a connector
  independently resolves to executable commands. An ordinary query such as
  “Search cats and dogs” remains one search.
- Return a fixed typed unsupported reason for diagnostics and user-facing
  guidance. Unsupported input never becomes an executable command.
- Store optional, independent local ratings for transcript accuracy and action
  correctness with the bounded request record. Do not store raw audio and do
  not treat recognition confidence or capability success as accuracy.

## Consequences

Adding a new target or target-specific action remains an explicit code and test
change. Compound planning is deferred rather than guessed. The local ratings
make normal dogfooding actionable, while reproducible WER and proper-noun claims
still require the controlled speech corpus and engine benchmark.
