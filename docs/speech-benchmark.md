# Speech benchmark plan

Status: not yet run. No user voice recordings were provided, and no result below
should be read as an accuracy or latency claim.

During ordinary dogfooding, Topher's bounded local diagnostics provide separate
thumb ratings for transcript accuracy and action correctness. Run
`scripts/summarize_dogfood_diagnostics.rb` for aggregate counts and latency
percentiles without printing command text. These subjective ratings help find
regressions but do not replace the controlled corpus below: Apple confidence,
capability success, and intent success are not proxies for word error rate.

Dictation records use the same transcript rating plus a separate insertion
rating, and retain raw versus formatted/inserted text when those differ. A good
insertion rating is not an accuracy claim: the controlled corpus must evaluate
recognition, formatting, and focused-field behavior separately.

Measure recognition and polish independently. Score recognition against the
raw final transcript; score polish against the inserted text and the recorded
typed reason. Otherwise a cleanup improvement can hide an ASR regression.

## Corpus

The checked-in [`dogfood/manual-corpus.json`](../dogfood/manual-corpus.json) is
the human acceptance menu for current commands, negative cases, dictation, and
future context requests. The private gitignored observed-query corpus records
what the user actually tried and is an input for expanding that checklist. It
does not replace this controlled audio benchmark: sanitize and choose expected
behavior before promoting any observed phrase.

Use five natural takes of each phrase in a quiet room and five with typical room
noise. Do not coach identical cadence between takes.

1. “Topher, open Chrome.”
2. “Bring me to YouTube.”
3. “Search YouTube for Jujutsu Kaisen season three.”
4. “Open Visual Studio Code.”
5. “Open GitHub dot com.”
6. “Search Crunchyroll.”
7. “Search for Oracle Fusion Data Intelligence.”
8. “Open Notion.”
9. “Open Xcode.”
10. “Search for pnpm workspace filtering.”
11. “What app am I currently using?”
12. “What is this Chrome tab?”
13. “What tabs do I have open?”
14. “Switch to the Chrome tab titled Example Domain.”

The Chrome phrases use public, non-sensitive example tabs only. For activation,
replace `Example Domain` with one exact title from the current bounded result;
do not put private tab titles into a shared benchmark report. The negative
corpus must also include “Close the Chrome tab,” “What’s on my YouTube feed?”,
two regular tabs with the same example title, one incognito tab, and a file URL.
Those cases must refuse, remain unsupported, or be explicitly excluded without
capturing page bodies or broadening permissions.

Add a distinct prose/dictation corpus with developer terminology and natural
punctuation, including `GraphQL`, `URLSession`, `pnpm`, repository names,
domains, selected-text replacement, text adjacent to an existing word, two
short paragraphs, and an utterance that should not receive terminal
punctuation. Test the exact same audio independently from assistant commands so
intent correction cannot hide recognition errors.

Include clear one- to three-word restarts, repeated stutters, terminal repeated
words, rhetorical repetition, repeated acronyms/numbers, punctuation and
newline boundaries, and real user stutters. Preserve the user's actual intended
repetition even when the raw transcript contains duplicate words.

Expand this into 40–60 phrases covering supported navigation/search, developer
terms, personal sites/apps, ambiguous negatives that must not execute, and
context-dependent requests that must report a missing capability. Add five
unscripted variations. Run each engine without context, with the built-in
developer vocabulary, and with accepted personal terms.

Record only after explicit consent. Keep recordings only for the benchmark,
store them outside source control, and delete them after results are accepted.

For each run record the macOS build, Topher revision, engine package tag and
commit, exact model/quantization and license, microphone, input sample rate,
mouth-to-microphone distance, room/noise condition, contextual vocabulary, and
whether model assets were already warm.

## Candidates

- Direct Apple `SpeechTranscriber` and AuralKit, counted as one recognition
  engine but compared for integration/recovery behavior.
- FluidAudio Parakeet; test the normal ASR path first. Do not add its learned EOU
  model unless a toggle/ambient mode creates a measured need.
- WhisperKit.
- whisper.cpp only after selecting a roughly comparable model size to the
  WhisperKit and FluidAudio configurations.

## Measurements

For every clip capture:

- Exact normalized command success.
- Semantic command success even when wording differs.
- Word error rate and proper-noun accuracy.
- Developer-term accuracy, correction reason, and false-correction count.
- False execution count across unsupported and ambiguous negatives.
- Time from capture start to first nonempty partial.
- Time from key-up/end-of-audio to stable final text.
- Cold model/session start time and warm session time.
- Peak resident memory and model storage.
- CPU, GPU, and Neural Engine utilization during a 20-command loop.
- Idle CPU after warm-up, ten-minute energy impact, thermal-state changes, and
  battery delta under the same brightness/power conditions.
- Partial-result revisions and early truncation.
- Raw-to-formatted dictation diff, invented punctuation/capitalization count,
  missing/extra boundary spaces, and semantic text changes (acceptance: zero).
- Disfluency-removal precision and recall, intentional-repetition preservation,
  and polish-only CPU latency. Report the fast tier separately from any future
  context-aware tier and include timeout/fallback counts.
- Focused-field insertion success by AppKit field, Chrome form control and
  contenteditable surface, code editor, chat composer, and multiline editor.
- Visible insertion success versus Topher's typed outcome, split by fixed
  insertion method, verification level, and target role. False-positive success
  acceptance is zero; report unverifiable and not-observed results separately.
- Selection replacement, guarded undo, focus-change fallback, secure-field
  refusal, and proof that no path synthesizes Return or writes the clipboard
  without the explicit Copy action.
- Failure and recovery after 100 sessions, sleep/wake, and microphone changes.

Key-up is the normal end-of-utterance signal for push-to-talk. VAD may skip
silence but must not delay or override explicit finalization. The mode-specific
maximum is a second bounded finalization signal—30 seconds for assistant
commands and 120 seconds for dictation—and must preserve rather than discard
the best transcript exactly once.

## Precommitted acceptance thresholds

Freeze these thresholds before listening to benchmark outputs. Change one only
with a written reason recorded before comparing candidates.

- Exact normalized intent success: at least 98% in quiet and 95% in typical room
  noise.
- Semantic command success on the supported corpus: at least 95%.
- Exact proper-noun phrase success: at least 95% across the named-term clips.
- Developer-term accuracy: at least 90%, with zero false auto-corrections and
  zero unintended executions in the negative corpus.
- Warm speech-onset-to-first-partial latency: p50 at most 300 ms and p95 at most
  600 ms.
- Warm key-up-to-final latency: p50 at most 350 ms and p95 at most 800 ms.
- Fast deterministic polish latency: p95 at most 10 ms for a maximum-length
  accepted utterance on the target Mac, with no asynchronous or network wait.
- Polish safety: 100% preservation of intentional/ambiguous repetition and zero
  semantic rewrites in the frozen corpus. Report recall rather than widening
  rules to chase every stutter.
- Cold start to first usable partial: p95 at most 2 seconds.
- Reliability: 100 consecutive sessions complete or fail visibly, with zero
  wedged sessions; sleep/wake and microphone changes recover within one retry.
- Idle cost after warm-up: no active microphone outside a session and less than
  1% average CPU over ten minutes.
- Resource bound: peak resident memory below 1.5 GiB, no growth above 15% of the
  post-warm baseline after 100 sessions, no serious/critical thermal state, and
  no model asset above 1 GiB without a material accuracy advantage.
- Privacy/cost hard gates: offline after assets are installed, no raw-audio
  retention, and no recurring service cost.

If no candidate clears the accuracy and latency gates, do not choose the least
bad result; revise the command/audio experiment and rerun it.

## Results table

| Candidate/configuration | Exact intent quiet/noise | Proper nouns | Cold p95 | Warm partial p50/p95 | Key-up final p50/p95 | Peak/baseline memory | CPU/GPU/ANE | Idle/10-min energy and thermal | Model storage | 100-session/recovery notes |
|---|---:|---:|---:|---:|---:|---:|---|---|---:|---|
| Apple direct, no context | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | OS-managed, measure | Not run |
| Apple direct, alternatives/confidence | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | OS-managed, measure | Not run |
| Apple direct, developer/personal context | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | OS-managed, measure | Not run |
| AuralKit, context | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | OS-managed, measure | Not run |
| FluidAudio, chosen model | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Measure | Not run |
| WhisperKit, chosen model | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Measure | Not run |
| whisper.cpp, matched model | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Measure | Not run |

## Selection rule

Choose the smallest integration that reaches acceptable command success and a
comfortable key-up-to-final delay on this Mac. Prefer Apple direct when it meets
that bar. Prefer AuralKit if it materially improves route/sleep/repetition
reliability enough to justify its currently documented extra speech-recognition
permission burden. Use a bundled model only if the Apple path misses the
measured accuracy or latency bar.
