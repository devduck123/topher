# Decision 0011: Canonical spoken web destinations

Status: accepted for local dogfooding, 2026-07-15

Build 6 transcribed “Open Netflix,” “Open Hulu,” and “Open Amazon” accurately
but rejected them as unknown targets. Explicit `.com` forms worked. The same
run recognized an intended domain as `ballaslive.com`; because that string was
a syntactically valid public host, the browser accepted a potentially wrong
destination.

Known web brands now resolve through an application-owned catalog with fixed
canonical hosts. Amazon, Ballislife, Hulu, and Netflix join the existing typed
destinations. A brand match wins before application or arbitrary-domain
matching, preserving the established “Open/Search Crunchyroll” semantics.
Topher does not guess a domain by appending `.com` to an unknown name.

Canonical terms bias Apple's on-device recognizer, while observed mistakes stay
in the deterministic interpreter. A correction may narrow a free recognized
domain to an existing canonical website. It may not construct another free
host. For voice-originated unfamiliar domains, distinct hosts in Apple's
bounded hypotheses cause a typed rejection before policy and browser handoff.
Manual exact domains are unaffected because they have no speech uncertainty.

Confidence alone is not a navigation gate: dogfood evidence contained correct
low-confidence phrases and incorrect plausible-confidence domains. Structural
agreement and typed canonical destinations are stronger evidence.
