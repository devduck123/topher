# Documentation map

Topher's documentation separates current behavior, durable contracts, evolving
plans, decisions, and historical verification. Start with the smallest source
that answers the question instead of reading every file.

## Sources of truth

| Question | Canonical source |
|---|---|
| What does Topher do today? | [`README.md`](../README.md) |
| What product are we building toward? | [Product vision](product/vision.md) |
| How can requests reach Topher? | [Interaction modes](product/interaction-modes.md) |
| How do requests, context, policy, and capabilities interact? | [Request lifecycle and context](architecture/request-lifecycle.md) |
| What should be built next? | [Implementation plan](implementation-plan.md) |
| What risks remain open? | [Risk register](risks.md) |
| What are the security and privacy invariants? | [`SECURITY.md`](../SECURITY.md) |
| How should contributors build and validate changes? | [`CONTRIBUTING.md`](../CONTRIBUTING.md) |
| How do local logs and retained dogfood diagnostics work? | [Local diagnostics](local-diagnostics.md) |
| What should I say during manual testing? | [Dogfood query corpus](../dogfood/README.md) |
| How will speech quality be selected? | [Speech benchmark](speech-benchmark.md) |

## Document classes

### Current state

- `README.md` describes implemented user-visible behavior and known limits.
- `docs/implementation-plan.md` tracks completed, active, and future slices.
- `docs/risks.md` tracks current risk and the next proof required.

These files should change as the product changes.

### Durable contracts

- `docs/product/vision.md` records product direction and priorities.
- `docs/product/interaction-modes.md` separates activation, ingress, dictation,
  command, remote, and follow-up modes.
- `docs/architecture/request-lifecycle.md` defines trust and execution boundaries.
- `SECURITY.md` states non-negotiable security and privacy invariants.

Change these deliberately when product or architecture contracts change, not
merely to describe an implementation detail.

### Decisions

`docs/decisions/` records consequential choices, rejected alternatives, and the
evidence available at decision time. Add a new ADR or explicitly supersede an
older one when a decision changes. Do not silently rewrite accepted history.

### Evidence

`docs/evidence/` contains dated checkpoint records. An evidence file says what
was verified for that checkpoint; it is not automatically proof of current
behavior. Add a new record for new measurements or acceptance results. Never
edit an older record to claim a test that was not run then.

### Investigations and procedures

- `docs/technical-investigation.md` captures the initial platform and technology
  investigation; revalidate time-sensitive claims against current primary
  sources before using them for a new decision.
- `docs/local-diagnostics.md` and `docs/speech-benchmark.md` define repeatable
  operational procedures and acceptance measurements.
- `dogfood/manual-corpus.json` is the sanitized human acceptance checklist;
  `.topher-local` observed-query data is private and never committed.

## Common reading routes

- **Small deterministic command change:** README → relevant Core source/tests →
  implementation plan → relevant ADR.
- **Speech or capture change:** contributing guide → speech benchmark → risks →
  capture/transcription source and tests → latest relevant evidence.
- **Permission or context feature:** product vision → interaction modes → request
  lifecycle → security policy → risks → relevant ADRs.
- **Release or installation work:** contributing guide → README security posture
  → latest release evidence → install helper.
- **Code review:** changed files and tests → `AGENTS.md` review priorities →
  relevant contract and risk documents.

Repository-wide agent instructions live in [`AGENTS.md`](../AGENTS.md). Claude
Code loads the same canonical guidance through [`CLAUDE.md`](../CLAUDE.md).
