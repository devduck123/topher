# Speech benchmark plan

Status: not yet run. No user voice recordings were provided, and no result below
should be read as an accuracy or latency claim.

## Corpus

Use five natural takes of each phrase in a quiet room and five with typical room
noise. Do not coach identical cadence between takes.

1. “Topher, open Chrome.”
2. “Open YouTube.”
3. “Search YouTube for Jujutsu Kaisen season three.”
4. “Open Visual Studio Code.”
5. “What app am I currently using?”
6. “Search for Oracle Fusion Data Intelligence.”
7. “Can you pull up YouTube for me?”

Add five unscripted variations that express the same intents. Run each engine
once without contextual vocabulary and once with installed application names,
“Topher,” “Jujutsu Kaisen,” and “Oracle Fusion Data Intelligence.”

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
- Word error rate and proper-noun accuracy.
- Time from capture start to first nonempty partial.
- Time from key-up/end-of-audio to stable final text.
- Cold model/session start time and warm session time.
- Peak resident memory and model storage.
- CPU, GPU, and Neural Engine utilization during a 20-command loop.
- Idle CPU after warm-up, ten-minute energy impact, thermal-state changes, and
  battery delta under the same brightness/power conditions.
- Partial-result revisions and early truncation.
- Failure and recovery after 100 sessions, sleep/wake, and microphone changes.

Key-up is the end-of-utterance signal for push-to-talk. VAD may skip silence but
must not delay or override explicit finalization.

## Precommitted acceptance thresholds

Freeze these thresholds before listening to benchmark outputs. Change one only
with a written reason recorded before comparing candidates.

- Exact normalized intent success: at least 98% in quiet and 95% in typical room
  noise.
- Exact proper-noun phrase success: at least 95% across the named-term clips.
- Warm speech-onset-to-first-partial latency: p50 at most 300 ms and p95 at most
  600 ms.
- Warm key-up-to-final latency: p50 at most 350 ms and p95 at most 800 ms.
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
| Apple direct, context | Not run | Not run | Not run | Not run | Not run | Not run | Not run | Not run | OS-managed, measure | Not run |
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
