# Step 3: coverage table (distinct notices per country x year x type, quality shares) and the
# 2023 monthly profile of the CSV against the API, to locate the eForms break.
source("R/packages.R")
con <- dbConnect(duckdb())
dbExecute(con, "CREATE VIEW cn  AS SELECT * FROM read_parquet('data/parquet/cn_20*.parquet')")
dbExecute(con, "CREATE VIEW can AS SELECT * FROM read_parquet('data/parquet/can_20*.parquet')")

cov <- dbGetQuery(con, "
  WITH n AS (
    SELECT 'cn' AS type, YEAR AS year, ISO_COUNTRY_CODE AS country, ID_NOTICE_CN AS id, count(*) AS rows,
           bool_or(TRY_CAST(VALUE_EURO_FIN_1 AS DOUBLE) > 0) AS has_value,
           bool_or(B_FRA_AGREEMENT = 'Y') AS fra, bool_or(length(TAL_LOCATION_NUTS) >= 4) AS nuts2
    FROM cn GROUP BY ALL
    UNION ALL
    SELECT 'can', YEAR, ISO_COUNTRY_CODE, ID_NOTICE_CAN, count(*),
           bool_or(TRY_CAST(AWARD_VALUE_EURO_FIN_1 AS DOUBLE) > 0),
           bool_or(B_FRA_AGREEMENT = 'Y'), bool_or(length(TAL_LOCATION_NUTS) >= 4)
    FROM can GROUP BY ALL)
  SELECT type, year, country, count(*) AS notices, round(avg(rows), 1) AS rows_per_notice,
         round(avg(has_value::INT), 2) AS value_share, round(avg(fra::INT), 2) AS fra_share,
         round(avg(nuts2::INT), 2) AS nuts2_share
  FROM n GROUP BY ALL ORDER BY type, year, country")
setDT(cov); fwrite(cov, "outputs/coverage.csv")
print(dcast(cov[year %in% c("2019", "2023")], country ~ type + year, value.var = "notices")[order(-cn_2023)], nrows = 60)
print(cov[year == "2023" & type == "can"][order(-notices), .(country, notices, rows_per_notice, value_share, fra_share, nuts2_share)], nrows = 60)

m_csv <- dbGetQuery(con, "
  SELECT strftime(date_trunc('month', try_strptime(DT_DISPATCH, '%d/%m/%y')), '%Y-%m') AS month,
         count(DISTINCT ID_NOTICE_CN) AS csv_cn,
         count(DISTINCT CASE WHEN ISO_COUNTRY_CODE = 'FR' THEN ID_NOTICE_CN END) AS csv_FR,
         count(DISTINCT CASE WHEN ISO_COUNTRY_CODE = 'DE' THEN ID_NOTICE_CN END) AS csv_DE
  FROM cn WHERE YEAR = '2023' GROUP BY 1 ORDER BY 1")
api <- fread("data/api/counts.csv")[month >= "2023-01-01" & month <= "2023-12-01" & country %in% c("ALL", "FRA", "DEU") & type %in% c("cn", "competition")]
api[, month := format(month, "%Y-%m")]
print(merge(m_csv, dcast(api, month ~ country + type, value.var = "n"), by = "month", all = TRUE))
dbDisconnect(con)
