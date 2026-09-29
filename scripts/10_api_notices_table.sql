-- Step 10 (run by the duckdb CLI): the raw API pages (data/api/notices_v2/*.jsonl.gz, Oct 2023 -> today) as one typed
-- table with the same columns as notice_cn/notice_can plus text, buyer activity and legal type, lot values, flags,
-- winner country and size, award date, procedure id. One row per notice; lot-level fields kept as JSON text.
INSTALL json; LOAD json;
SET lambda_syntax = 'ENABLE_SINGLE_ARROW'; SET memory_limit = '40GB'; SET threads = 4; SET preserve_insertion_order = false; SET temp_directory = '/tmp/duckdb_tmp';
CREATE MACRO fs(j, p) AS coalesce(json_extract_string(j, p || '[0]'), json_extract_string(j, p));
CREATE MACRO first_lang(j) AS fs(j, '$.' || json_keys(j)[1]);
CREATE MACRO strs(j, p) AS from_json(json_extract(j, p), '["VARCHAR"]');                                 -- JSON array -> VARCHAR[]
CREATE MACRO any_true(j, p, v) AS list_aggregate(list_transform(strs(j, p), x -> x = v), 'bool_or');   -- any element equal to v
CREATE TABLE cc (iso3 VARCHAR, iso2 VARCHAR);
INSERT INTO cc VALUES ('AUT','AT'),('BEL','BE'),('BGR','BG'),('HRV','HR'),('CYP','CY'),('CZE','CZ'),('DNK','DK'),('EST','EE'),('FIN','FI'),
  ('FRA','FR'),('DEU','DE'),('GRC','GR'),('HUN','HU'),('IRL','IE'),('ITA','IT'),('LVA','LV'),('LTU','LT'),('LUX','LU'),('MLT','MT'),
  ('NLD','NL'),('POL','PL'),('PRT','PT'),('ROU','RO'),('SVK','SK'),('SVN','SI'),('ESP','ES'),('SWE','SE'),('NOR','NO'),('ISL','IS'),
  ('LIE','LI'),('CHE','CH'),('GBR','UK'),('MKD','MK');
CREATE TABLE api AS
  WITH n AS (
    SELECT unnest(notices) AS j, regexp_extract(filename, '(\d{4}-\d{2})', 1) AS month
    FROM read_json('__INPUT__', format = 'newline_delimited', columns = {'notices': 'JSON[]'},
                   filename = true, maximum_object_size = 67108864))
  SELECT json_extract_string(j, '$.publication-number')                              AS pub_number,
         fs(j, '$.procedure-identifier')                                              AS procedure_id,
         TRY_CAST(left(json_extract_string(j, '$.publication-date'), 10) AS DATE)    AS pub_date,
         TRY_CAST(left(json_extract_string(j, '$.dispatch-date'), 10) AS DATE)       AS dispatch_date,
         month,
         json_extract_string(j, '$.notice-type')                                      AS notice_type,
         json_extract_string(j, '$.form-type')                                        AS form_type,
         CASE json_extract_string(j, '$.form-type') WHEN 'competition' THEN 'cn' WHEN 'result' THEN 'can' END AS type,
         fs(j, '$.buyer-country')                                                     AS country_iso3,
         cc.iso2                                                                      AS country,
         first_lang(json_extract(j, '$.buyer-name'))                                  AS buyer_name,
         fs(j, '$.organisation-identifier-buyer')                                     AS buyer_id,
         fs(j, '$.main-activity')                                                     AS main_activity,
         fs(j, '$.entity-main-activity')                                              AS entity_main_activity,
         fs(j, '$.buyer-legal-type')                                                  AS buyer_legal_type,
         CASE fs(j, '$.contract-nature') WHEN 'works' THEN 'W' WHEN 'supplies' THEN 'U' WHEN 'services' THEN 'S' END AS contract_type,
         json_extract_string(j, '$.procedure-type')                                   AS procedure_type,
         fs(j, '$.classification-cpv')                                                AS cpv,
         fs(j, '$.classification-cpv')[1:2]                                           AS cpv_div,
         fs(j, '$.place-of-performance')                                              AS nuts,
         CASE WHEN length(fs(j, '$.place-of-performance')) >= 4 THEN fs(j, '$.place-of-performance')[1:4] END AS nuts2,
         list_aggregate(list_transform(strs(j, '$.framework-agreement-lot'), x -> x <> 'none'), 'bool_or') AS framework,
         any_true(j, '$.eu-fund-lot', 'eu-funds')                                         AS eu_funds,
         json_keys(json_extract(j, '$.title-proc'))[1]                                AS lang,
         first_lang(json_extract(j, '$.title-proc'))                                  AS title,
         left(first_lang(json_extract(j, '$.description-proc')), 20000)                            AS description,
         left(json_extract(j, '$.title-lot')::VARCHAR, 50000)                                      AS lot_titles,
         left(json_extract(j, '$.description-lot')::VARCHAR, 50000)                                AS lot_descriptions,
         TRY_CAST(fs(j, '$.estimated-value-proc') AS DOUBLE)                          AS est_value,
         fs(j, '$.estimated-value-cur-proc')                                          AS est_value_cur,
         list_sum(list_transform(strs(j, '$.estimated-value-lot'), x -> TRY_CAST(x AS DOUBLE))) AS est_value_lots,
         fs(j, '$.estimated-value-cur-lot')                                           AS est_value_lot_cur,
         list_sum(list_transform(strs(j, '$.framework-maximum-value-lot'), x -> TRY_CAST(x AS DOUBLE))) AS framework_max_value_lots,
         TRY_CAST(fs(j, '$.total-value') AS DOUBLE)                                   AS total_value,
         fs(j, '$.total-value-cur')                                                   AS total_value_cur,
         left(json_extract(j, '$.tender-value')::VARCHAR, 50000)                                   AS tender_values,
         left(json_extract(j, '$.duration-period-value-lot')::VARCHAR, 50000)                      AS lot_durations,
         fs(j, '$.duration-period-unit-lot')                                          AS lot_duration_unit,
         left(json_extract(j, '$.winner-name')::VARCHAR, 50000)                                    AS winner_names,
         left(json_extract(j, '$.organisation-identifier-tenderer')::VARCHAR, 50000)               AS winner_ids,
         fs(j, '$.winner-country')                                                    AS winner_country,
         left(json_extract(j, '$.winner-country')::VARCHAR, 50000)                                 AS winner_countries,
         left(json_extract(j, '$.winner-size')::VARCHAR, 50000)                                    AS winner_sizes,
         TRY_CAST(left(fs(j, '$.winner-decision-date'), 10) AS DATE)                  AS award_date
  FROM n LEFT JOIN cc ON cc.iso3 = fs(j, '$.buyer-country')
  ;
COPY api TO '__OUTPUT__' (FORMAT parquet, COMPRESSION zstd);
