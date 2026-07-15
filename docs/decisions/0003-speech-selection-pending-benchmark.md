# Decision 0003: Speech selection requires a local benchmark

Status: provisional, 2026-07-14

Treat direct Apple `SpeechTranscriber` as the leading candidate and AuralKit as
the wrapper comparison. Benchmark FluidAudio and WhisperKit as independent
local alternatives; retain whisper.cpp only if its lower-level control is
measurably useful.

The local Apple transcriber and English asset are available, but no candidate
has been tested on the user's voice, command vocabulary, microphone, or recovery
scenarios. Selecting from repository claims would violate the reliability goal.

Decision closes only after `speech-benchmark.md` contains local results.
