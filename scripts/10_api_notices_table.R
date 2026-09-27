# Step 10: the raw API pages (data/api/notices/*.jsonl.gz, Oct 2023 -> today) as one typed table with the same
# columns as notice_cn/notice_can plus the text fields. One row per notice; lot-level fields kept as JSON text.
source("R/packages.R"); options(width = 200)
con <- dbConnect(duckdb())
dbExecute(con, "CREATE MACRO fs(j, p) AS coalesce(json_extract_string(j, p || '[0]'), json_extract_string(j, p))")   -- first element or scalar
dbExecute(con, "CREATE MACRO first_lang(j) AS fs(j, '$.' || json_keys(j)[1])")                                          -- value in the notice's language
dbExecute(con, "CREATE TABLE cc (iso3 VARCHAR, iso2 VARCHAR); INSERT INTO cc VALUES
  ('AUT','AT'),('BEL','BE'),('BGR','BG'),('HRV','HR'),('CYP','CY'),('CZE','CZ'),('DNK','DK'),('EST','EE'),('FIN','FI'),('FRA','FR'),
  ('DEU','DE'),('GRC','GR'),('HUN','HU'),('IRL','IE'),('ITA','IT'),('LVA','LV'),('LTU','LT'),('LUX','LU'),('MLT','MT'),('NLD','NL'),
  ('POL','PL'),('PRT','PT'),('ROU','RO'),('SVK','SK'),('SVN','SI'),('ESP','ES'),('SWE','SE'),('NOR','NO'),('ISL','IS'),('LIE','LI'),
  ('CHE','CH'),('GBR','UK'),('MKD','MK')")

dbExecute(con, "CREATE TABLE api AS
  WITH n AS (
    SELECT unnest(notices) AS j, regexp_extract(filename, '(\\d{4}-\\d{2})', 1) AS month
    FROM read_json('data/api/notices/*.jsonl.gz', format = 'newline_delimited', columns = {'notices': 'JSON[]'},
                   filename = true, maximum_object_size = 67108864))
  SELECT json_extract_string(j, '$.publication-number')                    AS pub_number,
         TRY_CAST(left(json_extract_string(j, '$.publication-date'), 10) AS DATE) AS pub_date,
         TRY_CAST(left(json_extract_string(j, '$.dispatch-date'), 10) AS DATE)    AS dispatch_date,
         month,
         json_extract_string(j, '$.notice-type')                            AS notice_type,
         json_extract_string(j, '$.form-type')                              AS form_type,
         CASE json_extract_string(j, '$.form-type') WHEN 'competition' THEN 'cn' WHEN 'result' THEN 'can' END AS type,
         fs(j, '$.buyer-country')                                           AS country_iso3,
         cc.iso2                                                            AS country,
         CASE fs(j, '$.contract-nature') WHEN 'works' THEN 'W' WHEN 'supplies' THEN 'U' WHEN 'services' THEN 'S' END AS contract_type,
         json_extract_string(j, '$.procedure-type')                         AS procedure_type,
         fs(j, '$.classification-cpv')                                      AS cpv,
         fs(j, '$.classification-cpv')[1:2]                                 AS cpv_div,
         fs(j, '$.place-of-performance')                                    AS nuts,
         CASE WHEN length(fs(j, '$.place-of-performance')) >= 4 THEN fs(j, '$.place-of-performance')[1:4] END AS nuts2,
         first_lang(json_extract(j, '$.buyer-name'))                        AS buyer_name,
         fs(j, '$.organisation-identifier-buyer')                           AS buyer_id,
         json_keys(json_extract(j, '$.title-proc'))[1]                      AS lang,
         first_lang(json_extract(j, '$.title-proc'))                        AS title,
         first_lang(json_extract(j, '$.description-proc'))                  AS description,
         json_extract(j, '$.title-lot')::VARCHAR                            AS lot_titles,
         json_extract(j, '$.description-lot')::VARCHAR                      AS lot_descriptions,
         TRY_CAST(fs(j, '$.estimated-value-proc') AS DOUBLE)                AS est_value,
         fs(j, '$.estimated-value-cur-proc')                                AS est_value_cur,
         TRY_CAST(fs(j, '$.total-value') AS DOUBLE)                         AS total_value,
         fs(j, '$.total-value-cur')                                         AS total_value_cur,
         json_extract(j, '$.tender-value')::VARCHAR                         AS tender_values,
         json_extract(j, '$.winner-name')::VARCHAR                          AS winner_names,
         json_extract(j, '$.organisation-identifier-tenderer')::VARCHAR     AS winner_ids
  FROM n LEFT JOIN cc ON cc.iso3 = fs(j, '$.buyer-country')
  QUALIFY row_number() OVER (PARTITION BY pub_number ORDER BY month) = 1")

print(dbGetQuery(con, "SELECT count(*) AS notices, min(pub_date) AS first, max(pub_date) AS last, count(DISTINCT country) AS countries,
  round(avg((country IS NULL)::INT), 3) AS unmapped_country FROM api"))
print(dbGetQuery(con, "SELECT month, type, count(*) AS notices, round(avg((description IS NOT NULL)::INT), 2) AS has_description,
  round(avg((coalesce(total_value, est_value) IS NOT NULL)::INT), 2) AS has_value, round(avg((nuts2 IS NOT NULL)::INT), 2) AS has_nuts2
  FROM api GROUP BY ALL ORDER BY 1 DESC, 2 LIMIT 10"))
cnt <- fread("data/api/counts.csv")[country == "ALL" & type %in% c("competition", "result")][, .(month = format(month, "%Y-%m"), form_type = type, counted = n)]
prs <- setDT(dbGetQuery(con, "SELECT month, form_type, count(*) AS parsed FROM api GROUP BY ALL"))
print(merge(prs, cnt, by = c("month", "form_type"))[order(-month)][1:8])

dbExecute(con, "COPY api TO 'outputs/panel/notice_api.parquet' (FORMAT parquet, COMPRESSION zstd)")
system2("mc", c("--quiet", "cp", "outputs/panel/notice_api.parquet", "s3/dorviya/diffusion/ted-ods/panel/"))
cat("written:", round(file.size("outputs/panel/notice_api.parquet") / 1e6), "MB\n")
