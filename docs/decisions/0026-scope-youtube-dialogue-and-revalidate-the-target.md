# 0026: Scope YouTube dialogue and revalidate the selected target

- Status: Accepted
- Date: 2026-07-22

## Context

The first YouTube Home slice proved the narrow permission, packaged extractor,
bounded snapshot, and exactly-once open path. Real use exposed four product
gaps:

1. People ask for their feed and choose videos with many ordinary variations,
   including “recommendations,” “homepage,” “play video three,” a pronoun
   followed by “number three,” or the exact title alone.
2. A local native-host manifest can be correct while Chrome, the extension, or
   the optional origin permission is unavailable. One green setup indicator
   overstated readiness.
3. One truncation flag coupled display completeness to exact-title safety. A
   card missing a channel could disable a title whose uniqueness was otherwise
   provable.
4. Mutation revalidation treated unrelated feed reorder, lazy loading, and tab
   presentation changes as target changes. That was safe but unnecessarily
   brittle for YouTube's dynamic Home surface.

There is no language model in Topher. Adding one would not recover a referent the
user did not specify, and model output cannot authorize navigation under
Topher's existing policy contract.

## Decision

### Keep interpretation deterministic and explicitly state-scoped

Topher expands only the reviewed YouTube grammar: Home/feed/recommendation read
requests; open/play/watch plus number, ordinal, or exact-title selection; and a
small set of explicit pronouns.

“Open that YouTube video” never guesses. With a multi-item feed it asks for a
shown number or exact title; with exactly one item it safely selects that item.
A bare number, ordinal, “last,” or exact displayed title may bind only to the
existing visible, clearable, 90-second session. Existing registered commands
retain precedence. A pronoun without a current session asks for a fresh feed
instead of falling back to web search. If ordinal and title evidence name
different videos, Topher refuses the request. No additional page content or
general conversational memory is retained.

Bounded on-device speech alternatives may replace a misheard title only when
the current feed maps the evidence to one exact video. Alternatives that map to
different listed videos refuse rather than voting or choosing by confidence.

### Version the browser contract and separate completeness

Chrome protocol version 3 carries:

- separate presentation truncation and title-observation completeness;
- whether each displayed title was unique in the bounded title observation;
- the selection kind used for revalidation; and
- one content-free integration-status response.

The packaged extractor scans at most 60 semantic recommendation candidates and
returns at most 20 complete title/channel rows. A bounded ID/title candidate set
exists only inside the extension request so a missing-channel or later candidate
can still prove or disprove title uniqueness. Those additional strings do not
cross native messaging, enter Topher memory, or reach ordinary diagnostics.

### Revalidate authority, source, and target—not incidental layout

The source fingerprint binds the regular Chrome tab, window, and canonical
YouTube Home route. It excludes tab index and page title. Immediately before a
single open, the extension revalidates:

- optional YouTube permission;
- the same active regular source tab/window and exact Home route;
- snapshot expiry;
- presence of the selected strict video ID and its stable observation identity;
  and
- for title selection, fresh complete and unique title evidence.

Unrelated recommendation order/content changes and tab-title/index churn neither
invalidate nor substitute the selected item. The app consumes the session before
dispatch. It does not retry a dispatched mutation whose outcome is unknown.

### Report readiness without acquiring context

The primary Topher process creates its authenticated local relay socket eagerly
so Chrome's native host can connect before the first command. A typed status
operation reports only live extension connection and the optional YouTube
permission bit. It reads no tabs or page data. The UI continues to show local
native-host registration separately from live extension/permission readiness.

## Consequences

- The common read, clarify, terse-select, and direct-select loops remain fast,
  local, testable, and available without Apple Intelligence or a cloud service.
- Exact-title matching stays normalized-exact rather than fuzzy. Requests such
  as “open the interesting one,” semantic topic matching, personalized ranking,
  or summarization remain unsupported unless a later decision introduces a
  constrained interpretation layer with measured benefit.
- YouTube DOM coupling remains isolated in one packaged extractor and fixtures.
- Protocol v2 peers fail with an explicit compatibility error and must be
  updated together.
- A narrow race remains between final revalidation and Chrome completing its one
  tab update. Unknown post-dispatch outcomes remain non-retriable.
- Automated tests cannot prove extension loading, Chrome profile permission UX,
  live YouTube DOM compatibility, spoken recognition quality, or real perceived
  latency. Those remain named manual acceptance gates.

## Rejected alternatives

- **Add an LLM for this feature now.** It cannot safely invent a missing ordinal
  or title, adds latency/cost/data-boundary work, and is unnecessary for the
  observed deterministic phrasings.
- **Treat every bare number/title as a YouTube follow-up without a visible feed
  session.** This would steal unrelated commands and imply general
  conversational memory.
- **Fuzzy-match titles or choose the first duplicate.** Either can open a video
  the user did not identify.
- **Return all 60 candidates to the app.** This expands sensitive data exposure
  without improving the visible product.
- **Require the whole feed to remain byte-for-byte identical.** This converts
  harmless dynamic-page churn into frequent false stale failures.
- **Use `activeTab` instead of optional host access.** Voice and manual requests
  are not extension invocation gestures, so Chrome's temporary grant does not
  cover this demand-driven path or provide durable, understandable recovery.
- **Poll or mirror browser context to improve readiness.** Connection and
  permission state do not require page acquisition; context remains on demand.
