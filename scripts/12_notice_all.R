# Step 12: one continuous notice-level history, Jan 2016 -> today, in the CSV's schema with harmonised codes: the CSV
# tables (dispatch dates to 2023-09-30) + the API table (published from 2023-10-01), API row winning at the seam.
# The richer recent table stays outputs/panel/notice_api.parquet. API values are in the notice's currency: value_eur is
# filled only for EUR notices until an exchange-rate join is added. Also refreshes the monthly aggregate over the whole span.
source("R/packages.R"); options(width = 200)
con <- dbConnect(duckdb())
dbExecute(con, "CREATE VIEW cn  AS SELECT * FROM 'outputs/panel/notice_cn.parquet'")
dbExecute(con, "CREATE VIEW can AS SELECT * FROM 'outputs/panel/notice_can.parquet'")
dbExecute(con, "CREATE VIEW api AS SELECT * FROM 'outputs/panel/notice_api.parquet'")

dbExecute(con, "CREATE MACRO act_csv(x) AS CASE
  WHEN x ILIKE '%health%' THEN 'health' WHEN x ILIKE '%education%' THEN 'education' WHEN x ILIKE '%general public%' THEN 'gen-pub'
  WHEN x ILIKE '%public order%' THEN 'pub-os' WHEN x ILIKE '%defence%' THEN 'defence' WHEN x ILIKE '%environment%' THEN 'env-pro'
  WHEN x ILIKE '%economic%' THEN 'econ-aff' WHEN x ILIKE '%housing%' THEN 'hc-am' WHEN x ILIKE '%social%' THEN 'soc-pro'
  WHEN x ILIKE '%recreation%' THEN 'rcr' WHEN x ILIKE '%electricity%' THEN 'electricity' WHEN x ILIKE '%gas%' OR x ILIKE '%heat%' THEN 'gas-heat'
  WHEN x ILIKE '%water%' THEN 'water' WHEN x ILIKE '%railway%' THEN 'rail' WHEN x ILIKE '%urban%' THEN 'urttb'
  WHEN x ILIKE '%airport%' THEN 'airport' WHEN x ILIKE '%port%' THEN 'port' WHEN x ILIKE '%postal%' THEN 'post'
  WHEN x ILIKE '%exploration%' OR x ILIKE '%extraction%' THEN 'extraction' WHEN x ILIKE '%other%' THEN 'other' END")
dbExecute(con, "CREATE MACRO btype_csv(x) AS CASE WHEN x IN ('1', 'N') THEN 'central' WHEN x IN ('3', 'R') THEN 'regional-local'
  WHEN x = '4' THEN 'utility' WHEN x IN ('5', '5A') THEN 'eu-international' WHEN x = '6' THEN 'public-law-body' WHEN x = '8' THEN 'other' END")
dbExecute(con, "CREATE MACRO btype_api(x) AS CASE WHEN x = 'cga' THEN 'central' WHEN x IN ('ra', 'la') THEN 'regional-local'
  WHEN x LIKE 'body-pl%' THEN 'public-law-body' WHEN x LIKE 'pub-undert%' OR x = 'spec-rights-entity' THEN 'utility'
  WHEN x IN ('eu-ins-bod-ag', 'int-org') THEN 'eu-international' WHEN x IS NULL THEN NULL ELSE 'other' END")
dbExecute(con, "CREATE MACRO proc_csv(x) AS CASE WHEN x = 'OPE' THEN 'open' WHEN x = 'RES' THEN 'restricted' WHEN x = 'COD' THEN 'comp-dial'
  WHEN x IN ('NEC', 'NEG', 'NIC') THEN 'neg-w-call' WHEN x IN ('NOC', 'NOP', 'AWP') THEN 'neg-wo-call' WHEN x = 'INP' THEN 'innovation'
  WHEN x IS NULL THEN NULL ELSE 'other' END")
dbExecute(con, "CREATE MACRO proc_api(x) AS CASE WHEN x IN ('open', 'restricted', 'comp-dial', 'neg-w-call', 'neg-wo-call', 'innovation') THEN x
  WHEN x IS NULL THEN NULL ELSE 'other' END")

dbExecute(con, "CREATE TABLE notice_all AS SELECT * FROM (
  SELECT 'csv' AS source, 'cn' AS type, CAST(CAST(substr(id, 5) AS INT) AS VARCHAR) || '-' || substr(id, 1, 4) AS pub_number,
         NULL::VARCHAR AS procedure_id, dispatch_date, NULL::DATE AS pub_date, country, contract_type,
         btype_csv(buyer_type) AS buyer_type, buyer_type AS buyer_type_raw, act_csv(main_activity) AS activity, main_activity AS activity_raw,
         proc_csv(procedure_type) AS procedure, procedure_type AS procedure_raw, framework, eu_funds, cpv, cpv_div, nuts, nuts2, cancelled,
         value_eur_fin1 AS value, 'EUR' AS value_cur, value_eur_fin1 AS value_eur, future_can_id, NULL::INT AS awards
  FROM cn
  UNION ALL
  SELECT 'csv', 'can', CAST(CAST(substr(id, 5) AS INT) AS VARCHAR) || '-' || substr(id, 1, 4), NULL, dispatch_date, NULL, country, contract_type,
         btype_csv(buyer_type), buyer_type, act_csv(main_activity), main_activity, proc_csv(procedure_type), procedure_type,
         framework, eu_funds, cpv, cpv_div, nuts, nuts2, cancelled, value_eur_fin1, 'EUR', value_eur_fin1, NULL, awards
  FROM can
  UNION ALL
  SELECT 'api', type, pub_number, procedure_id, dispatch_date, pub_date, country, contract_type,
         btype_api(buyer_legal_type), buyer_legal_type, coalesce(main_activity, entity_main_activity), coalesce(main_activity, entity_main_activity),
         proc_api(procedure_type), procedure_type, framework, eu_funds, cpv, cpv_div, nuts, nuts2, NULL::BOOLEAN,
         CASE WHEN type = 'can' THEN coalesce(total_value, est_value, est_value_lots) ELSE coalesce(est_value, est_value_lots, framework_max_value_lots) END,
         CASE WHEN type = 'can' THEN coalesce(total_value_cur, est_value_cur, est_value_lot_cur) ELSE coalesce(est_value_cur, est_value_lot_cur) END,
         NULL::DOUBLE, NULL, NULL
  FROM api WHERE type IS NOT NULL)
  QUALIFY row_number() OVER (PARTITION BY type, pub_number ORDER BY source) = 1")
dbExecute(con, "UPDATE notice_all SET value_eur = value WHERE source = 'api' AND value_cur = 'EUR'")

print(dbGetQuery(con, "SELECT source, type, year(coalesce(dispatch_date, pub_date)) AS year, count(*) AS notices,
  round(avg((value_eur IS NOT NULL)::INT), 2) AS has_value_eur, round(avg((activity IS NOT NULL)::INT), 2) AS has_activity,
  round(avg((buyer_type IS NOT NULL)::INT), 2) AS has_buyer_type FROM notice_all GROUP BY ALL ORDER BY 3, 1, 2"))
for (v in c("activity", "buyer_type", "procedure")) {
  cat("\n--", v, ": raw code -> harmonised, by source (top 25)\n")
  print(dbGetQuery(con, sprintf("SELECT source, %s_raw AS raw, %s AS harmonised, count(*) AS notices FROM notice_all GROUP BY ALL ORDER BY notices DESC LIMIT 25", v, v)))
}
print(dbGetQuery(con, "SELECT source, value_cur, count(*) AS notices FROM notice_all WHERE value IS NOT NULL GROUP BY ALL ORDER BY 3 DESC LIMIT 12"))

dbExecute(con, "COPY notice_all TO 'outputs/panel/notice_all.parquet' (FORMAT parquet, COMPRESSION zstd)")
dbExecute(con, "COPY (SELECT source, type, country, date_trunc('month', coalesce(dispatch_date, pub_date)) AS month, contract_type,
  count(*) AS notices, count(value_eur) AS notices_with_value_eur, sum(value_eur) AS value_eur
  FROM notice_all GROUP BY ALL ORDER BY 2, 3, 4, 5) TO 'outputs/panel/monthly_country_type.csv' (HEADER)")
system2("mc", c("--quiet", "cp", "outputs/panel/notice_all.parquet", "s3/dorviya/diffusion/ted-ods/panel/"))
system2("mc", c("--quiet", "cp", "outputs/panel/monthly_country_type.csv", "s3/dorviya/diffusion/ted-ods/panel/"))
