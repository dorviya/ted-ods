# TED for the hackathon — team briefing

*State on Sunday 27 September 2026. Facts about the data: `docs/DATA_NOTES.md`. Why we did what we did: `docs/DECISIONS_LOG.md`. Column definitions from the source: `docs/codebook_ted_csv_v3.4.pdf`.*

## 1. What TED is, in one paragraph

TED (Tenders Electronic Daily) is the supplement to the Official Journal of the EU in which public buyers — ministries, regions, municipalities, hospitals, universities, publicly-owned utilities — must advertise a purchase once its estimated value passes EU thresholds (roughly €140–220k for supplies and services, €5.5 million for works, revised every two years). Two notices matter. The **contract notice** is the call for tenders: "we intend to buy X, estimated at Y euros, bids due by Z". The **contract award notice** is the result: "we awarded X to firm W for V euros; D bids were received". Neither is a payment: TED records intentions and commitments, published within days of the event, so everything we build measures **public demand** or **procurement activity** — never "public spending". About 700,000 notices a year come from the EU-27, Norway, Iceland, Liechtenstein and Switzerland (and the UK until 2020): 25 OECD members under one harmonised form. Purchases below the thresholds are invisible, and the visible share differs by country and by type of contract.

## 2. Two sources, three periods

| Source | Period | Content | In the bucket |
|---|---|---|---|
| TED CSV open data (DG GROW) | dispatch dates Jan 2016 – Sep 2023 | one row per lot or award, ~100 columns, values converted to euro | `parquet/` (raw, all text), `panel/` (clean tables) |
| TED Search API, notices | published Oct 2023 – today | every call and award notice with 24 fields, including titles, descriptions, values, winners | `api/notices/` (raw JSON pages; a typed table follows on Monday) |
| TED Search API, monthly counts | Jan 2016 – Sep 2026 | notices per country × month × type | `api/counts.csv` |

The cut in October 2023 is the switch to **eForms**, a new notice format mandatory since late October 2023 that the CSV export does not contain: the CSV is complete to September 2023 and thins out afterwards (Germany switched almost entirely in November). The count series is the only one built from a single source over the whole period, which is why the headline chart uses it.

## 3. Where the data is and how to read it

Everything is public, served over HTTPS from `https://minio.lab.sspcloud.fr/dorviya/diffusion/ted-ods/`; no account, no download needed. DuckDB reads a parquet file straight from its URL and fetches only the columns a query touches:

    library(DBI); library(duckdb); con <- dbConnect(duckdb())
    base <- "https://minio.lab.sspcloud.fr/dorviya/diffusion/ted-ods/"
    dbGetQuery(con, paste0("SELECT country, year(dispatch_date) AS y, count(*) AS n FROM '", base, "panel/notice_cn.parquet' GROUP BY ALL ORDER BY 1, 2"))
    x <- dbGetQuery(con, paste0("SELECT * FROM '", base, "panel/award.parquet' WHERE country = 'FR' AND cpv LIKE '45%'"))   # then data.table / dplyr as usual

Python: `duckdb.sql("SELECT ... FROM 'https://.../panel/notice_cn.parquet'")`. Or download a file with the URL in a browser. The whole clean set weighs 450 MB. Whether the OECD network lets these URLs through is untested: try one before Tuesday.

## 4. The tables

**`panel/notice_cn.parquet` — calls for tenders, one row per notice (1.87 million, Jan 2016 – Sep 2023)**

| column | meaning |
|---|---|
| `id` | notice identifier, year + publication number: `2023263753` is notice `263753-2023` (https://ted.europa.eu/en/notice/-/detail/263753-2023) |
| `country` | buyer country, ISO two-letter (`UK`, `GR`) |
| `dispatch_date` | day the buyer sent the notice; publication follows within about five days |
| `contract_type` | `U` supplies, `S` services, `W` works |
| `buyer_type` | 1 national authority · 3 regional or local authority · 4 utility · 5/5A EU or international body · 6 body governed by public law · 8 other · N/R national or regional agency · Z unspecified |
| `main_activity` | the buyer's main activity, a COFOG-like list (Health, Education, General public services, Defence, Public order and safety, Environment, Economic and financial affairs, Housing and community amenities, Social protection, Recreation culture and religion, Other, Not specified) plus utility activities (electricity, gas, water, rail, urban transport, ports, airports, postal) |
| `procedure_type` | `OPE` open · `RES` restricted · `COD` competitive dialogue · `NEG`/`NEC` negotiated with a call · `NOC`/`NOP` negotiated without a call · `AWP` award without prior publication · `INP` innovation partnership · others: codebook §4 |
| `framework` | TRUE for a framework agreement (its value is a multi-year ceiling, not an amount to be spent) |
| `eu_funds` | TRUE when the purchase is EU-funded |
| `cpv`, `cpv_div` | main product code (8 digits) and its division (first two digits, 45 divisions) |
| `nuts`, `nuts2` | region of performance as given (country, NUTS-1/2/3) and its NUTS-2 code when the level allows |
| `cancelled` | TRUE for a cancelled notice (a few dozen a year) |
| `value_eur`, `value_eur_fin1` | estimated total value, raw and Commission-cleaned |
| `lots`, `n_rows` | number of lots; rows the notice occupied in the raw file |
| `future_can_id` | `id` of the award notice that later concluded this call, when linked |

**`panel/notice_can.parquet` — award notices, one row per notice (1.98 million)**: the same columns (`value_eur_fin1` is here the Commission-cleaned total of the awards, the value column to use), plus `awards` (number of awards), `award_value_sum`, `award_value_fin1_sum`, `award_est_value_sum` (sums over the awards below).

**`panel/award.parquet` — awards, one row per contract inside an award notice (6.3 million)**

| column | meaning |
|---|---|
| `id`, `award_id`, `lot` | award notice, award, lot awarded |
| `award_value_eur`, `award_value_eur_fin1`, `award_est_value_eur` | awarded value raw and cleaned; the buyer's estimate for this award (often missing) |
| `winner`, `winner_country`, `winner_id` | winner name (free text), country, national registration number (32% filled; SIREN in France) |
| `sme` | Y/N, several values joined by `---` when several winners |
| `offers`, `offers_other_eu`, `offers_non_eu` | number of bids received, of which from other EU / non-EU firms |
| `award_date`, `title` | award date (often missing); contract title (often generic) |

**`panel/monthly_country_type.csv`**: `type` (cn/can) × `country` × `month` × `contract_type` → `notices`, `value_eur_fin1`. The quick way to plot.

**`api/counts.csv` (17,544 rows)**: `month`, `country` (ISO three-letter, or `ALL`), `type` — `cn` = standard contract notices, `can` = standard award notices, `competition` = all calls for competition (≈ the CSV's definition), `result` = all result notices — `n`, `asof`. Jan 2016 to Sep 2026 (September incomplete).

**`api/notices/YYYY-MM.jsonl.gz`**: raw API pages, 250 notices each, Oct 2023 → today, fields `publication-number, publication-date, dispatch-date, notice-type, form-type, buyer-country, buyer-name, organisation-identifier-buyer, classification-cpv, place-of-performance, contract-nature, procedure-type, title-proc, description-proc, title-lot, description-lot, estimated-value-proc, total-value, tender-value, winner-name, organisation-identifier-tenderer`. Descriptions exist for eForms notices only. A typed table with the same columns as `notice_cn`/`notice_can` plus the text is produced on Monday.

**`outputs/coverage.csv`** (in the repo): distinct notices per country × year × type with the shares of notices carrying a value, a framework flag, a NUTS-2 region.

**`panel/meip_matches.csv`**: TED winners matched to the OECD-UNSD register of the 500 largest multinationals — `winner`, `iso3`, `awards`, `value_capped`, `parent`, `sub_name`, `how` (exact / id / fuzzy), `sim`, `hq_iso3`. Join to `award` on winner name and country.

**`reference/cpv_labels.csv`**: the 9,454 CPV codes with English, French and German labels. **`reference/cpv_cofog_<run>.csv`**: LLM classification of the 8,215 codes used, one file per run (`cofog_primary`, `cofog_secondary`, `secondary_condition`, `justification`, `confidence`); **`reference/cpv_cofog_consensus.csv`** (Monday): majority function per code with an agreement score across runs.

**Raw layers**, for checks only: `parquet/{cn,can}_YYYY.parquet` (2006–2023, every column as text, exactly the CSV) and `raw/` (the zips).

How the tables relate: `notice_cn.future_can_id → notice_can.id` (call to award); `award.id → notice_can.id`; `notice_*.cpv → cpv_labels.cpv → cpv_cofog_*.cpv`; `award.winner + winner_country → meip_matches`; `counts.country` (three-letter) ↔ `notice.country` (two-letter; `UK`↔`GBR`, `GR`↔`GRC`, others by the usual ISO table).

## 5. Seven things to hold in mind before drawing anything

1. Count distinct notices, never rows: one notice can span thousands of rows (lots, awards).
2. Values are the weak spot: 30–50% missing at row level, placeholders (0.01, 1), and thousand-fold typos that survive the Commission's cleaning (2,067 awards above €1 bn, 200 above €100 bn). Cap or filter, and prefer counts for headlines. Use `value_eur_fin1` of award notices when you must use values, and keep frameworks apart.
3. TED sees only above-threshold purchases: a window, not the house; the window's size differs by country (EU-funds rules make eastern members very complete) and by contract type (the works threshold is high).
4. Timing: a call leads activity by the tender period (months); an award leads delivery by the contract's duration. Work monthly; use year-on-year changes; expect December and pre-summer peaks.
5. Breaks: 2016 new forms (richer data); the UK leaves after 2020; COVID in spring 2020; the eForms switch from October 2023 — the CSV ends in September 2023, the API takes over.
6. Regions are uneven: NUTS-2 or finer for most notices in most countries, but under 30% in NL, CH, LT, SI, EE, IE.
7. Identities are free text: aggregate by region, buyer type and activity; winner names may be sole traders (natural persons) — never publish names.

## 6. Idea starters — what is ready to explore

- The pulse: monthly calls by country since 2016, up to last month (`counts.csv`), year-on-year, with the events annotated.
- Do works tenders lead public investment? Quarterly works calls (`notice_cn`, `contract_type = W`) against Eurostat government investment.
- Public demand by function, monthly: `notice_*` × the COFOG mapping, validated against Eurostat's annual COFOG expenditure.
- Double tagging: the green and digital share of demand from secondary tags and title keywords (API notices give descriptions from Oct 2023).
- Who wins: the share of contracts going to the 500 largest multinationals, by country and sector (`award` × `meip_matches`) — health suppliers dominate.
- Competition: single-bid share by country and sector (`award.offers`); cross-border awards (`winner_country` ≠ buyer country).
- Speed of the state: median call-to-award duration by country and year (`future_can_id`).
- Where EU money goes: `eu_funds` by NUTS-2, 2021–2023 against 2016–2019.
- The PPE scramble: daily medical-supply notices, spring 2020 (`cpv_div` 33 and 18, `procedure_type`).
- Rearmament: CPV division 35 and defence buyers since February 2022, monthly, to last month.
- Election cycles, floods, price signals (awarded versus estimated values, with heavy cleaning): see `05_data_stories` in the project files.

## 7. What has been done

Repository `github.com/dorviya/ted-ods` with numbered scripts (`01` download → `02` parquet → `03` coverage → `04` clean tables → `05` API counts → `06` API notices → `07` MEIP matching → `08` COFOG classification → `09` agreement); everything in the public bucket; renv lockfile and a pod setup script so a fresh machine rebuilds in minutes. Data note and decisions log kept as we go.

## 8. For the data-quality lead

### 8.1 History of the source, in short

Procurement directives of 2004, replaced by the 2014 directives applied from 2016 (new standard forms with more fields: SME flag, EU-funds flag, bids by origin); the CPV vocabulary revised in 2008; thresholds revised every two years (approximately €135k/€209k/€5.2m in 2016–17 for central-government supplies and services / other bodies / works, €143k/€221k/€5.5m in 2024–25 — check the exact figures in the Commission's threshold regulations). The Commission's CSV export exists in three generations (December 2021 for 2006–07, October 2022 for 2008–16, January 2024 for 2017–23), with a codebook (v3.4, December 2021, `docs/`) and advanced notes. From 14 November 2022 the Publications Office published both the old forms and eForms; eForms became mandatory on 25 October 2023 and the CSV export does not include them. The Search API (v3) indexes both formats and maps old notices onto the new vocabulary; the TED Open Data Service (knowledge graph, SPARQL) is a fourth door we did not use. TED also received "voluntary ex-ante transparency notices" and corrigenda, which are outside our tables.

### 8.2 Quality facts

- **Relevance**: TED answers questions about public demand (intentions, commitments), competition in public markets, sub-national and product-level detail, timeliness; it cannot answer questions about spending, deliveries, or below-threshold purchases.
- **Accuracy**: values (see §5.2); estimated value present at notice level for ~99% of calls, cleaned awarded total for 87–95% of award notices; regions mixed-level; winner names free text with a registration number on 32% of awards from country-specific registers; a spurious backslash in `main_activity` ("General public\services"); `TITLE` on award notices only and often generic.
- **Timeliness**: notices searchable within days of publication (September 2026 available in full on 27 September); the CSV lags by a year or more and stops in September 2023; monthly counts by country available for any month since 2016 in one API request per cell.
- **Coherence and comparability**: three export generations with identical column sets per type but two date formats (`dd/mm/yy` from 2017, `dd-MON-yy` before); CSV country codes ISO-2 with `UK`/`GR` versus API ISO-3; the API's `form-type = competition` matches the CSV's "all calls for competition" within ±5% over January–September 2023; the UK exit (21,000 award notices in 2019, 1,800 in 2023); publication culture and EU-funds rules make coverage uneven across countries (see `outputs/coverage.csv`).
- **Accessibility**: CSV 38 zips / 2.2 GB (9 GB of text, 1 GB in parquet); API without key, 250 notices per page, about one request per second accepted; text fields for eForms notices only; everything mirrored in a public bucket with the citation the codebook requests.
- **Interpretability**: rows are lots and awards, notices are the unit; the call-to-award link is `future_can_id` on the call (award notices carry no call id); `_fin1` values are the Commission's fallback chain (final value → lowest offer → highest offer → estimate → 0 when no winner; notice total substituted for frameworks).

### 8.3 Checks done, and checks worth doing

Done: distinct notices per country × year × type and quality shares (`03_coverage.R`); monthly profile of 2023 in the CSV against the API (locates the eForms break); date parsing verified (0 unparsed); sum of API counts over countries against the `ALL` cell (differs by a few dozen a month); distribution of absurd values; MEIP matching precision where registration numbers exist (82.5% agree for exact name matches, registers permitting).

Worth doing, in order of value for the note: (1) recompute monthly counts by country from `notice_cn`/`notice_can` and compare with `counts.csv` for 2016–2023 — the coherence figure for the whole period; (2) shares of missing values for each key field by country and year (`coverage.csv` gives three; add `nuts`, `main_activity`, `offers`, `winner_country`); (3) duplicates and corrections: the raw `parquet/` files carry `CORRECTIONS` and `CANCELLED` columns we only used for the cancelled flag; (4) the publication lag (dispatch to publication) from the API notices, and the call-to-award lag from `future_can_id`; (5) framework agreements: share by country and their weight in values; (6) external benchmarks: the Commission's Single Market Scoreboard publishes annual single-bidder and no-call shares by country computed from TED; Eurostat's COFOG expenditure for functional shares; Opentender's cleaned data for counts; (7) a below-threshold share estimate (the codebook says some below-threshold notices are present); (8) the human validation of the COFOG mapping (200 notices, stratified by the agreement band) and its calibration: are unanimous codes more often right?

### 8.4 Licence, citation, privacy, reproducibility

TED data is reusable under the Commission's reuse decision; the codebook asks to cite "TED csv dataset (YYYY–YYYY), Tenders Electronic Daily, supplement to the Official Journal of the European Union. DG Internal Market, Industry, Entrepreneurship and SMEs, European Commission, Brussels. Available at https://data.europa.eu/data/datasets/ted-csv. Version 3.4. Accessed on 2026-09-26." The MEIP register is public OECD-UNSD data; the CPV codelist comes from the Publications Office's eForms SDK. Winner names can be natural persons: publish aggregates only. Everything is rerunnable: scripts in order, data in the bucket, package versions locked; a rerun of the API steps on another day gives more recent months and, for revisable notices, slightly different counts — record the `asof` date with any figure.
