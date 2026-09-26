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
