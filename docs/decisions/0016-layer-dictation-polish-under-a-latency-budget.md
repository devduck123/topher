# 0016: Layer dictation polish under an explicit latency budget

- Status: accepted
- Date: 2026-07-16

## Context

Raw on-device speech recognition can faithfully expose a spoken restart such as
“I I think.” High-quality dictation products make those utterances feel cleaner,
but a general grammar or language-model rewrite on every key-up can add visible
latency, alter developer terminology, require network access, and obscure
whether recognition or formatting caused a defect.

[Wispr documents](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack)
smart formatting over the full dictation, a raw-mode switch, and removal of only
clear self-corrections. [Willow publicly describes](https://willowvoice.com/blog/automatic-punctuation-dictation)
context-aware formatting and approximately 200 ms response, including more
conservative behavior in code editors; its timing is a vendor claim rather than
Topher evidence. Topher needs the useful product shape without trusting
external latency claims or expanding context authority prematurely.

## Decision

Dictation polish has two separately measured tiers:

1. The current fast tier runs synchronously, locally, and deterministically on
   finalized text. It applies presentation normalization and may remove an
   exact adjacent restart of at most three words only when a following word
   makes the restart non-terminal. Punctuation/newline boundaries, numbers,
   acronyms, single-letter ambiguity, and common intentional repeated words
   prevent cleanup. The single-pass tail-collapse algorithm is linear in the
   number of recognized words and bounded by `DictationText`'s maximum length.
2. A future smart tier may use the full finalized utterance and typed identity
   of the destination application. It must be optional, preserve raw text,
   produce application-owned typed change reasons, meet a precommitted deadline,
   and fall back to the fast tier on timeout, failure, or uncertainty. Screen,
   page, or document content is not acquired merely to format prose.

**Clean repeated speech** defaults on and persists an explicit opt-out. Turning
it off retains presentation normalization but performs no repeated-speech
cleanup. Recovered partials are presentation-only because incomplete text may
still be revised and is never inserted automatically.

Raw finalized text and polished text remain distinct in bounded dogfood
diagnostics. An unremoved stutter/filler feedback reason is distinct from whole
text being inserted more than once.

This decision extends, rather than rewrites, decision 0014's safe insertion
boundary. It does not authorize command interpretation, submission, arbitrary
input synthesis, or broader Accessibility context.

## Consequences

- Common clear restarts improve without a model/network hop on the insertion
  path.
- False-negative cleanup is preferred to silently deleting intentional prose.
- Filler removal, punctuation, grammar, and tone remain visibly incomplete.
- Raw-versus-polished evidence can attribute recognition and cleanup defects.
- A smarter tier cannot become the default until accuracy, semantic safety,
  privacy, fallback behavior, and end-to-end latency pass the frozen corpus.

## Rejected alternatives

- Run an LLM on every dictation: rejected because latency, availability,
  privacy, cost, and semantic-rewrite risk are not justified by current data.
- Aggressively delete fillers and repeated tokens with regexes: rejected because
  developer prose, emphasis, numbers, acronyms, and natural repetition are not
  safely distinguishable without evidence.
- Rewrite text asynchronously after insertion: rejected because it creates a
  second mutation, stale-target races, confusing native undo, and visible text
  movement.
- Switch speech engines to solve formatting before benchmarking recognition:
  rejected because it conflates ASR quality, endpoint latency, and polish.
