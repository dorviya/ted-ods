# TED data for OECD statistics — a practitioner's note

## 1. What the data is
TED (Tenders Electronic Daily) is the Supplement to the Official Journal of the EU in which public buyers publish
procurement notices above the EU thresholds. We use two access doors. The TED CSV open data (DG GROW, data.europa.eu,
dataset "ted-csv": one file per year for contract notices and one for contract award notices, 2006-01-01 to 2023-12-31,
values converted to euro, with a codebook PDF) covers 2016–2023. The TED Search API
(POST https://api.ted.europa.eu/v3/notices/search) provides monthly counts by country and notice type from 2016 to last month.
Citation format requested by the codebook: "TED csv dataset (YYYY-YYYY), Tenders Electronic Daily, supplement to the
Official Journal of the European Union. DG Internal Market, Industry, Entrepreneurship, and SMEs, European Commission,
Brussels. Available at https://data.europa.eu/data/datasets/ted-csv. Version X. Accessed on YYYY-MM-DD." (version to be
filled from the downloaded codebook). A copy of the raw files, reused under the Commission's reuse decision, is kept at
https://minio.lab.sspcloud.fr/dorviya/diffusion/ted-ods/raw/.

## 2. Coverage (CSV open data, 2016 – September 2023)
- Distinct notices per country, year and type: outputs/coverage.csv. Calls for tenders in 2023: DE 55k, FR 52k, PL 29k, ES 20k,
  IT 14k, RO and CZ 9k, SE 8k; the UK falls from 21k award notices in 2019 to 1.8k in 2023.
- The CSV thins out from October 2023 (eForms): calls in the CSV against the API were −22% in October, −60% in November, −71% in
  December 2023; Germany had almost fully switched by November (230 vs 6,033), France only partly. The usable CSV period is
  dispatch dates up to 30 September 2023; January–September 2023 matches the API's "all calls for competition" within ±5%.
- The 2016 files come from an older export (October 2022) with dates written dd-MON-yy; the 2017–2023 files (January 2024 export)
  use dd/mm/yy. Column sets are identical across years within each type: 64 columns for calls, 75 for award notices.
- Rows are lots and awards, not notices: 2022 calls are 1.72M rows for 279k notices, and one notice can span thousands of rows.
  Always count distinct identifiers.

## 3. Quality dimensions
Accuracy — Values: the estimated value is missing on ~48% of call rows but present at notice level for ~99% of calls; the awarded
value at notice level exists for 87–95% of award notices, placeholders 0.01 and 1 included. Absurd values survive the Commission's
_FIN_1 treatment: 2,067 awards above €1bn, 499 above €10bn, 200 above €100bn (municipal waste contracts at €40 trillion). Any value
aggregate must cap or filter; counts are robust. Regions: TAL_LOCATION_NUTS mixes levels (country, NUTS-1/2/3); NUTS-2 or finer
is available for most award notices in most countries but for fewer than 30% in NL, CH, LT, SI, EE and IE. Winners: free-text
names (mixed case, legal forms, spelling variants); a national registration number on 32% of awards, from registers that differ
by country (SIREN in FR; KRS versus tax numbers in PL).
Timeliness — API notices are searchable within days of publication (September 2026 available in full on 27 September); monthly
counts by country for any month since 2016 in one request per cell; the API accepts about one request per second.
Coherence — Country codes: the CSV uses ISO alpha-2 with UK and GR (not Eurostat's EL); the API uses alpha-3. The API maps legacy
notices onto the eForms vocabulary (notice-type cn-standard/can-standard, form-type competition/result), so one consistent count
series from 2016 to today exists; form-type=competition ≈ the CSV's "calls for competition" (about 3% above cn-standard).
Accessibility — CSV open data: 38 zips, 2.2 GB, about 9 GB of CSV, about 1 GB in parquet. Search API: POST /v3/notices/search,
no key, 250 notices per page in iteration mode, about one request per second; fields include title-proc, description-proc,
title-lot, description-lot, buyer and tenderer identifiers, CPV, NUTS and values — text only for eForms notices (late 2023 on);
legacy notices return title, CPV and NUTS but no description (per-notice XML would be needed).
Interpretability — The call-to-award link is FUTURE_CAN_ID on the call for tenders (award notices carry no ID_NOTICE_CN). TITLE
exists only on award notices and is often generic ("Contract", "Acord cadru"). MAIN_ACTIVITY has a stray backslash in
"General public\services". CAE_TYPE: 1 national authority, 3 regional or local authority, 4 utilities, 5/5A EU or international
body, 6 body governed by public law, 8 other, N/R national or regional agency, Z unspecified.
