+++
title = "Week 4 Worklog"
weight = 4
chapter = false
pre = " <b> 1.4. </b> "
+++

**Project:** OTT Search Analytics pipeline ·
[ott-search-pipeline](https://github.com/thanhtrung102/ott-search-pipeline)

### Week 4 Objectives (7–12 May 2026)

- Build a **Vietnamese OTT search analytics** pipeline (what users search for on a streaming service,
  and where they abandon).
- Classify free-text search queries into **genres** with a hybrid rule + LLM approach.
- Package it as an FCJ workshop with verified, reproducible results.

### Tasks carried out this week

| Day | Task | Start | Completion | Commits |
| :-- | :--- | :--- | :--- | :--- |
| 1 | **Pipeline scaffold** — initial Vietnamese OTT search analytics pipeline; fixed critical workshop reproducibility gaps found via a codebase audit. | 07/05/2026 | 07/05/2026 | [`8d789c0`], [`b85de84`] |
| 2 | **Workshop & metrics** — added a workshop Hugo site and fixed governance-stack IAM permissions; corrected abandonment-rate discrepancies; added the FCJ proposal page; rewrote the workshop content with verified proof-of-results. | 08/05/2026 | 08/05/2026 | [`28c353b`], [`5dd9f43`], [`2554711`] |
| 3 | **Genre classifier** — diacritics normalization, LUT (lookup-table) expansion, and a regex fix; a Glue timeout fix (skip the fuzzy stage in fast mode); precision/recall improvements; added an **Amazon Bedrock (Nova) fallback** in the Lambda; built `evaluate_classifier.py` for full-dataset quality evaluation; expanded the curated LUT with **409 adjudicated entries** plus a ground-truth test set. | 11/05/2026 | 11/05/2026 | [`7a265b7`], [`9001db1`], [`7e79284`], [`78bfeb4`] |
| 4 | **End-to-end enrichment** — fixed the ingestion pipeline and enriched the production dataset end-to-end. | 12/05/2026 | 12/05/2026 | [`5a4d88c`] |

### Week 4 Achievements

- **A working OTT search analytics pipeline** that turns raw search logs into genre-classified,
  abandonment-aware analytics.
- **A hybrid genre classifier**: a diacritics-aware curated lookup table for precision, with an
  Amazon Bedrock (Nova) fallback for unknown queries — evaluated against a ground-truth set rather than
  guessed.
- **Reproducible workshop**: the FCJ workshop content was rewritten around verified, proof-of-results
  numbers after a reproducibility audit.

---

👉 **Outcome:** A second AWS data project delivered — search-behaviour analytics with a measurable,
evaluated NLP classification step and an FCJ workshop.

[`8d789c0`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/8d789c0
[`b85de84`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/b85de84
[`28c353b`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/28c353b
[`5dd9f43`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/5dd9f43
[`2554711`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/2554711
[`7a265b7`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/7a265b7
[`9001db1`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/9001db1
[`7e79284`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/7e79284
[`78bfeb4`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/78bfeb4
[`5a4d88c`]: https://github.com/thanhtrung102/ott-search-pipeline/commit/5a4d88c
