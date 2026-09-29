# scripts/13_quality.R — coverage and quality tables for docs/DATA_NOTES.md (DuckDB group-bys on the clean tables)
# Unit of counting: the procedure (eForms procedure_id; the notice number where absent), dated at its first notice.
source("R/packages.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
dir.create("outputs/quality", showWarnings = FALSE)
NA_ <- "outputs/panel/notice_all.parquet"

# 1. Procedures, notices and field coverage per type × dispatch year × country (notice_all has one row per notice)
cov <- q(sprintf("
  SELECT type, year(dispatch_date) AS year, country,
         count(DISTINCT coalesce(procedure_id, pub_number)) AS procedures, count(*) AS notices,
         round(avg((value_eur IS NOT NULL)::int), 3)                        AS value_raw,
         round(avg(coalesce(value_eur BETWEEN 1e3 AND 1e9, false)::int), 3) AS value_ok,
         round(avg(coalesce(framework, false)::int), 3)                     AS framework,
         round(avg(coalesce(eu_funds, false)::int), 3)                      AS eu_funds,
         round(avg((nuts2 IS NOT NULL)::int), 3)                            AS nuts2,
         round(avg((activity IS NOT NULL)::int), 3)                         AS activity,
         round(avg((buyer_type IS NOT NULL)::int), 3)                       AS buyer_type,
         round(avg((cpv IS NOT NULL)::int), 3)                              AS cpv
  FROM '%s' WHERE dispatch_date >= '2016-01-01' AND country IS NOT NULL
  GROUP BY 1, 2, 3 ORDER BY 1, 2, 3", NA_))
fwrite(cov, "outputs/quality/coverage_country_year.csv")

# 2. Monthly procedures by type × country, each procedure dated at its first notice
m <- q(sprintf("
  WITH p AS (
    SELECT type, coalesce(procedure_id, pub_number) AS proc, any_value(country) AS country,
           min(dispatch_date) AS first_date, count(*) AS notices
    FROM '%s' WHERE dispatch_date >= '2016-01-01' AND country IS NOT NULL
    GROUP BY 1, 2)
  SELECT type, country, date_trunc('month', first_date)::date AS ym, count(*) AS procedures, sum(notices) AS notices
  FROM p GROUP BY 1, 2, 3 ORDER BY 1, 2, 3", NA_))
setnames(m, "ym", "month")
fwrite(m, "outputs/quality/monthly_procedures.csv")

print(m[, .(procedures = sum(procedures), notices = sum(notices)), by = .(type, year = year(month))
        ][, ratio := round(notices / procedures, 2)][year >= 2021][order(type, year)])
print(m[type == "cn" & month %between% as.Date(c("2023-06-01", "2024-03-01")), .(procedures = sum(procedures)), by = month])
