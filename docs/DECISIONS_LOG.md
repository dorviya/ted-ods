# Decisions log (append-only)

## 2026-09-26 — Work on SSP Cloud (Onyxia) pods rather than work laptops
Context: the brief assumed locked-down laptops and local storage.
Decision: code in a public GitHub repo; data in the personal bucket under diffusion/ (public read); packages via renv
restored by setup.sh, usable as the pod's init script.
Alternatives rejected: laptops (no admin rights, storage); a private repo (blocks the init-script URL and teammates' clones).
Consequence: nothing lives on a pod's disk; a fresh pod is rebuilt in minutes; teammates query parquet over HTTPS without credentials.

## 2026-09-26 — API count series from January 2016, not January 2024
Context: the CSV stops on 2023-12-31 and does not cover eForms (mandatory since late October 2023), so its last months are probably thin.
Decision: run the count loop from 2016 (about 7,700 requests) so the API series overlaps the CSV and the eForms break can be measured.
Consequence: one consistent count series for the headline story, and a free validation of the CSV's distinct-notice counts.

## 2026-09-27 — CSV period ends 30 September 2023; the API takes over from October 2023
Context: the eForms switch empties the CSV from October 2023 (DATA_NOTES §2).
Decision: notice-level tables from the CSV for dispatch dates 2016-01-01 to 2023-09-30; all competition and result notices
from 2023-10-01 fetched through the API with text fields; the headline count series from the API alone, 2016 → today, no splice.

## 2026-09-27 — Per-year files, everything as text in parquet, typed notice-level tables as the product
Decision: per-year zips (the 2018–2023 bundles are identical concatenations); one parquet file per year with all columns as
text; scripts/04 builds notice_cn and notice_can (one row per notice) and award (one row per award) with typed columns.
Rejected: a pre-aggregated cube — less useful than a GROUP BY on the notice table.
Challenge met: 2016 dates written dd-MON-yy (older export) silently dropped by a dd/mm/yy parser → a parse_dt macro tries both.

## 2026-09-27 — Values: FIN_1 at notice level, cap or filter, counts first
Decision: value stories use VALUE_EURO_FIN_1 of award notices (the Commission's cleaned notice total); placeholders below €1,000
treated as missing; frameworks separate; a cap or ratio filter to be agreed with the economists since absurd values survive
FIN_1. Shares by count are the headline wherever possible.

## 2026-09-27 — API pace and loop design
Decision: 0.5 s between requests (the server refuses beyond roughly one per second), retries with growing backoff, newest month
first, results appended as they arrive and copied to the bucket. Four count series per cell (cn, can, competition, result),
33 countries plus an ALL cell.

## 2026-09-27 — MEIP matching: three methods, precision from registration numbers
Decision: names normalised identically on both sides (dots removed, upper case, accents stripped, legal forms dropped); exact
match within country for normalised names of five or more characters mapping to a single parent; Jaro–Winkler ≥ 0.95 blocked by
country and first word; registration-number match; precision estimated where both sides carry a number. Values capped at €100M;
shares of awards as the headline. Challenge met: empty normalised names matched everything, assigning 18,000 winners to the
alphabetically first parent — fixed by the length and single-parent rules.

## 2026-09-27 — COFOG mapping by LLM at CPV-code level, two providers, agreement as the uncertainty measure
Decision: classify the 8,215 CPV codes used (not the notices) in batches of 40 with strict JSON; the same prompt on gpt-5.4-mini
and gemini-3.8-flash, plus prompt and batch perturbations; per-code agreement drives the human validation sample.
The prompt is stored verbatim (docs/prompts/cpv_cofog_v1.md).

## 2026-09-27 — Nothing large in git
Challenge met: a missing newline in .gitignore let 400 MB of parquet into a commit; caught during the push, amended.
Rule: outputs/panel/*.parquet ignored; the bucket is the only home of data.
