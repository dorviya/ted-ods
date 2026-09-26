# ted-ods

TED (Tenders Electronic Daily, the EU's journal of public-procurement notices) turned into monthly,
cross-country indicators of public demand. OECD Statistics and Data Directorate hackathon, 29-30 September 2026.

## Rerun on a fresh pod (SSP Cloud datalab, VS Code R + Python service)

    cd ~/work && git clone https://github.com/dorviya/ted-ods.git && bash ted-ods/setup.sh

`setup.sh` restores the R packages (renv). Data is not in git: it lives in the bucket (below).
`Rscript main.R` runs the numbered scripts in `scripts/` in order.

## Data

- Bucket `s3/<bucket>/diffusion/ted-ods/`, public read at `https://minio.lab.sspcloud.fr/<bucket>/diffusion/ted-ods/`:
  `raw/` (TED CSV files as downloaded, plus the codebook), `parquet/`, `api/`, `panel/`.
- In-house data (MEIP, GDELT extracts) never enters git or the public prefix.

## Layout

`main.R` entry point - `R/` functions - `scripts/` numbered steps - `reference/` small lookup tables (committed) -
`outputs/` panel and figures - `docs/` data notes, decisions log, prompts - `data/` local scratch (ignored).

Source line under every figure: "Source: TED CSV open data (DG GROW), TED Search API; authors' calculations.
Above-threshold notices only; counts of distinct notices."
