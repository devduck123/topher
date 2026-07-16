# Decision 0007: Personalized, safe transcript interpretation

Status: accepted for local dogfooding, 2026-07-15

Use Apple `SpeechTranscriber` alternatives, confidence attributes, and a
bounded `AnalysisContext` vocabulary before considering a replacement speech
engine. Keep the exact raw final transcript and interpret it through a pure,
testable layer before deterministic intent resolution.

Contextual vocabulary is a fail-soft experiment: if the installed speech stack
rejects `AnalysisContext`, Topher continues with the base transcriber. Measure
its actual effect in the speech benchmark before treating it as proven.

The interpreter may select a different reading only when one supported speech
alternative maps to one unique typed command, or when an explicit built-in or
user vocabulary replacement produces an allowlisted typed command. Ambiguous
alternatives and corrections that remain unsupported do not execute. The layer
cannot create a URL, bundle identifier, capability, policy decision, or raw
input action.

Personal vocabulary is local, user-editable, capped at 40 entries, merged with
a curated developer vocabulary, and capped again at 100 active contextual
strings. Do not silently mine repositories, browser history, messages,
clipboard contents, or screen context. Persist only accepted vocabulary.

Known web destinations own target-specific language rules. Bare “Open
Crunchyroll,” “Search Crunchyroll,” and “Search for Crunchyroll” navigate to the
allowlisted Crunchyroll homepage. Query-bearing provider forms continue to use
their provider, and other bare searches use Google through the system default
browser, which is Chrome for current dogfood use.

Developer diagnostics may retain bounded raw and interpreted text, a fixed
correction reason, and confidence summary under the existing local retention
policy. They never retain raw audio or the full alternative list.
