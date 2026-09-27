# Step 4: clean notice-level tables from the CSV parquet for the CSV's reliable period (dispatch dates
# 2016-01-01 to 2023-09-30; from October 2023 the CSV thins out and the API takes over).
# notice_cn / notice_can: one row per notice. award: one row per award (contract) of an award notice.
source("R/packages.R")
con <- dbConnect(duckdb())
dbExecute(con, "CREATE MACRO parse_dt(d) AS coalesce(try_strptime(d, '%d/%m/%y'), try_strptime(d, '%d-%b-%y'), try_strptime(concat(d[1:4], lower(d[5:6]), d[7:9]), '%d-%b-%y'))")  # dd/mm/yy in 2017+ exports, dd-MON-yy in the 2008-2016 exports
dbExecute(con, "CREATE VIEW cn  AS SELECT * FROM read_parquet('data/parquet/cn_20*.parquet')  WHERE YEAR >= '2016'")
dbExecute(con, "CREATE VIEW can AS SELECT * FROM read_parquet('data/parquet/can_20*.parquet') WHERE YEAR >= '2016'")

common <- "
  any_value(ISO_COUNTRY_CODE)                            AS country,
  parse_dt(any_value(DT_DISPATCH))::DATE AS dispatch_date,
  any_value(TYPE_OF_CONTRACT)                            AS contract_type,
  any_value(CAE_TYPE)                                    AS buyer_type,
  replace(any_value(MAIN_ACTIVITY), '\\', ' ')           AS main_activity,
  any_value(TOP_TYPE)                                    AS procedure_type,
  any_value(B_FRA_AGREEMENT) = 'Y'                       AS framework,
  any_value(B_EU_FUNDS) = 'Y'                            AS eu_funds,
  any_value(CPV)                                         AS cpv,
  any_value(CPV)[1:2]                                    AS cpv_div,
  any_value(TAL_LOCATION_NUTS)                           AS nuts,
  CASE WHEN length(any_value(TAL_LOCATION_NUTS)) >= 4 THEN any_value(TAL_LOCATION_NUTS)[1:4] END AS nuts2,
  any_value(CANCELLED) = '1'                             AS cancelled,
  any_value(TRY_CAST(VALUE_EURO AS DOUBLE))              AS value_eur,
  any_value(TRY_CAST(VALUE_EURO_FIN_1 AS DOUBLE))        AS value_eur_fin1,
  count(*)                                               AS n_rows"
period <- "WHERE dispatch_date BETWEEN DATE '2016-01-01' AND DATE '2023-09-30'"

dbExecute(con, sprintf("CREATE TABLE notice_cn AS SELECT * FROM (
  SELECT ID_NOTICE_CN AS id, %s, any_value(FUTURE_CAN_ID) AS future_can_id, any_value(TRY_CAST(LOTS_NUMBER AS INT)) AS lots
  FROM cn GROUP BY 1) %s", common, period))

dbExecute(con, "CREATE TABLE award_all AS
  SELECT ID_NOTICE_CAN AS id, ID_AWARD AS award_id, any_value(ID_LOT_AWARDED) AS lot,
         any_value(TRY_CAST(AWARD_VALUE_EURO AS DOUBLE))       AS award_value_eur,
         any_value(TRY_CAST(AWARD_VALUE_EURO_FIN_1 AS DOUBLE)) AS award_value_eur_fin1,
         any_value(TRY_CAST(AWARD_EST_VALUE_EURO AS DOUBLE))   AS award_est_value_eur,
         any_value(WIN_NAME) AS winner, any_value(WIN_COUNTRY_CODE) AS winner_country, any_value(WIN_NATIONALID) AS winner_id,
         any_value(B_CONTRACTOR_SME) AS sme, any_value(TRY_CAST(NUMBER_OFFERS AS INT)) AS offers,
         any_value(TRY_CAST(NUMBER_TENDERS_OTHER_EU AS INT)) AS offers_other_eu,
         any_value(TRY_CAST(NUMBER_TENDERS_NON_EU AS INT))   AS offers_non_eu,
         parse_dt(any_value(DT_AWARD))::DATE AS award_date, any_value(TITLE) AS title, count(*) AS n_rows
  FROM can GROUP BY 1, 2")

dbExecute(con, sprintf("CREATE TABLE notice_can AS
  SELECT n.*, a.awards, a.award_value_sum, a.award_value_fin1_sum, a.award_est_value_sum
  FROM (SELECT ID_NOTICE_CAN AS id, %s FROM can GROUP BY 1) n
  LEFT JOIN (SELECT id, count(*) AS awards, sum(award_value_eur) AS award_value_sum,
                    sum(award_value_eur_fin1) AS award_value_fin1_sum, sum(award_est_value_eur) AS award_est_value_sum
             FROM award_all GROUP BY 1) a USING (id) %s", common, period))
dbExecute(con, "CREATE TABLE award AS SELECT a.* FROM award_all a JOIN notice_can USING (id)")

print(dbGetQuery(con, "
  SELECT 'cn' AS type, year(dispatch_date) AS year, count(*) AS notices, round(avg((value_eur_fin1 > 0)::INT), 2) AS value_share FROM notice_cn GROUP BY ALL
  UNION ALL
  SELECT 'can', year(dispatch_date), count(*), round(avg((award_value_fin1_sum > 0)::INT), 2) FROM notice_can GROUP BY ALL ORDER BY 1, 2"))
print(dbGetQuery(con, "SELECT count(*) AS awards, count(DISTINCT id) AS notices, round(avg(n_rows), 2) AS rows_per_award FROM award"))
print(dbGetQuery(con, "SELECT count(*) AS unparsed_dates FROM (SELECT any_value(DT_DISPATCH) AS d FROM cn GROUP BY ID_NOTICE_CN) WHERE parse_dt(d) IS NULL"))

for (t in c("notice_cn", "notice_can", "award"))
  dbExecute(con, sprintf("COPY %s TO 'outputs/panel/%s.parquet' (FORMAT parquet, COMPRESSION zstd)", t, t))
dbExecute(con, "COPY (
  SELECT 'cn' AS type, country, date_trunc('month', dispatch_date) AS month, contract_type, count(*) AS notices, sum(value_eur_fin1) AS value_eur_fin1
  FROM notice_cn GROUP BY ALL
  UNION ALL
  SELECT 'can', country, date_trunc('month', dispatch_date), contract_type, count(*), sum(award_value_fin1_sum)
  FROM notice_can GROUP BY ALL ORDER BY 1, 2, 3, 4) TO 'outputs/panel/monthly_country_type.csv' (HEADER)")
system2("mc", c("--quiet", "cp", "--recursive", "outputs/panel/", "s3/dorviya/diffusion/ted-ods/panel/"))
dbDisconnect(con)
