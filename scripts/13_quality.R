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
         round(avg(coalesce(value_eur BETWEEN 1e3 AND 999999999, false)::int), 3) AS value_ok,
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

# 3. Winners and competition fields: coverage per year × country (CSV years: award ↔ notice_can; API years: notice_api)
API <- "outputs/panel/notice_api.parquet"
win_csv <- q("
  SELECT year(c.dispatch_date) AS year, c.country, count(*) AS awards,
         round(avg((a.winner IS NOT NULL)::int), 3)                                   AS winner,
         round(avg((a.winner_country IS NOT NULL)::int), 3)                           AS winner_country,
         round(avg((try_cast(a.offers AS INT) IS NOT NULL)::int), 3)                  AS offers,
         round(avg(CASE WHEN try_cast(a.offers AS INT) IS NOT NULL
                        THEN (try_cast(a.offers AS INT) = 1)::int END), 3)            AS single_bid,
         round(avg(CASE WHEN a.winner_country IS NOT NULL
                        THEN (replace(replace(a.winner_country, c.country, ''), '---', '') <> '')::int END), 3)            AS cross_border
  FROM 'outputs/panel/award.parquet' AS a JOIN 'outputs/panel/notice_can.parquet' AS c ON a.id::varchar = c.id::varchar
  GROUP BY 1, 2 ORDER BY 1, 2")
fwrite(win_csv, "outputs/quality/winners_csv_years.csv")
win_api <- q(sprintf("
  SELECT year(dispatch_date) AS year, country, count(*) AS notices,
         round(avg((winner_country IS NOT NULL)::int), 3) AS winner_country,
         round(avg(CASE WHEN winner_country IS NOT NULL THEN (winner_country <> country_iso3)::int END), 3) AS cross_border
  FROM '%s' WHERE type = 'can' AND country IS NOT NULL AND dispatch_date >= '2023-10-01'
  GROUP BY 1, 2 ORDER BY 1, 2", API))
fwrite(win_api, "outputs/quality/winners_api_years.csv")

# 4. Value outliers per type × year × country (euro values, before the bounds)
out <- q(sprintf("
  SELECT type, year(dispatch_date) AS year, country, count(*) AS with_value,
         count(*) FILTER (WHERE value_eur < 1e3)  AS under_1k,
         count(*) FILTER (WHERE value_eur > 1e9)  AS over_1bn,
         count(*) FILTER (WHERE value_eur > 1e10) AS over_10bn, round(max(value_eur)) AS max_value
  FROM '%s' WHERE value_eur IS NOT NULL AND country IS NOT NULL AND dispatch_date >= '2016-01-01'
  GROUP BY 1, 2, 3 ORDER BY 1, 2, 3", NA_))
fwrite(out, "outputs/quality/value_outliers.csv")

# 5. Lags: publication minus dispatch (API years); call to award (CSV: future_can_id; API: procedure_id)
pub_lag <- q(sprintf("
  SELECT type, year(pub_date) AS year, country, count(*) AS notices,
         median(date_diff('day', dispatch_date, pub_date)) AS lag_med,
         quantile_cont(date_diff('day', dispatch_date, pub_date), 0.9) AS lag_p90
  FROM '%s' WHERE source = 'api' AND country IS NOT NULL AND date_diff('day', dispatch_date, pub_date) BETWEEN 0 AND 365
  GROUP BY 1, 2, 3 ORDER BY 1, 2, 3", NA_))
fwrite(pub_lag, "outputs/quality/publication_lag.csv")
c2a <- rbind(
  q("SELECT 'csv' AS source, year(cn.dispatch_date) AS year, cn.country, count(*) AS calls,
            round(avg((can.id IS NOT NULL)::int), 3) AS linked,
            median(date_diff('day', cn.dispatch_date, can.dispatch_date)) AS lag_med_days
     FROM 'outputs/panel/notice_cn.parquet' AS cn LEFT JOIN 'outputs/panel/notice_can.parquet' AS can
       ON cn.future_can_id::varchar = can.id::varchar
     GROUP BY 1, 2, 3"),
  q(sprintf("
     WITH cn AS (SELECT procedure_id, any_value(country) AS country, min(dispatch_date) AS d FROM '%s'
                 WHERE source = 'api' AND type = 'cn' AND procedure_id IS NOT NULL AND country IS NOT NULL GROUP BY 1),
          can AS (SELECT procedure_id, min(dispatch_date) AS d FROM '%s'
                  WHERE source = 'api' AND type = 'can' AND procedure_id IS NOT NULL GROUP BY 1)
     SELECT 'api' AS source, year(cn.d) AS year, cn.country, count(*) AS calls,
            round(avg((can.d IS NOT NULL)::int), 3) AS linked, median(date_diff('day', cn.d, can.d)) AS lag_med_days
     FROM cn LEFT JOIN can USING (procedure_id) GROUP BY 1, 2, 3", NA_, NA_)))
fwrite(c2a[order(source, year, country)], "outputs/quality/call_to_award_lag.csv")

big <- c("DE", "FR", "PL", "ES", "IT", "NL", "SE", "CZ")
print(win_csv[year == 2022 & country %in% big])
print(win_api[year == 2025 & country %in% big])
print(q(sprintf("SELECT winner_country, count(*) AS n FROM '%s' WHERE type = 'can' GROUP BY 1 ORDER BY 2 DESC LIMIT 6", API)))
print(c2a[year %in% c(2022, 2024) & country %in% big][order(source, country)])
print(out[, .(under_1k = sum(under_1k), over_1bn = sum(over_1bn), over_10bn = sum(over_10bn)), by = .(type, period = fifelse(year <= 2023, "to 2023", "from 2024"))])
