# Dogfood query corpus

Topher keeps two deliberately different datasets:

1. `manual-corpus.json` is sanitized, reviewed, and safe to commit publicly. It
   is the canonical human acceptance checklist: say the exact `utterance` using
   the named `mode`, establish `setup`, and verify `expectedResult` plus every
   item in `checks`.
2. `.topher-local/dogfood/observed-queries.json` is an explicit local export of
   real assistant queries from the rolling developer trace. It is gitignored,
   may contain private text, and persists until the user deletes it.

Validate the public corpus:

```sh
ruby scripts/check_dogfood_corpus.rb
ruby scripts/test_observed_query_export.rb
```

Print the human checklist, optionally filtered by mode or category:

```sh
ruby scripts/check_dogfood_corpus.rb --list
ruby scripts/check_dogfood_corpus.rb --list --mode dictation
ruby scripts/check_dogfood_corpus.rb --list --category web-search
```

Snapshot currently retained assistant queries into the private local dataset:

```sh
ruby scripts/export_observed_queries.rb
```

The exporter excludes free-form dictation by default, merges duplicate phrases,
deduplicates imported trace records, keeps at most 500 entries and 1 MiB,
applies owner-only permissions, and rejects symlinked storage. Along with
outcomes and ratings, it aggregates fixed unsupported, insertion, capture,
interpretation/polish, and incorrect-action reasons, plus insertion method,
verification, target role, and automatic-finalization counts. Use
`--include-dictation` only when retaining dictated prose is intentional. Delete
`.topher-local/dogfood/observed-queries.json` to clear the durable local dataset;
clearing it does not affect Topher's rolling diagnostics.

Observed behavior is evidence, not automatically the desired specification.
Promote a useful real phrase into `manual-corpus.json` only after removing
private content and choosing an explicit expected behavior.
