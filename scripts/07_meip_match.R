# Step 7: TED winners (2016 - Sep 2023) matched to the OECD-UNSD MEIP register (500 largest MNEs, ~127k subsidiaries).
# Names normalised the same way on both sides; exact match within country (normalised names of 5+ characters that map
# to a single parent); Jaro-Winkler >= 0.95 for near misses, blocked by country and first word; registration numbers as
# an independent match and as a precision estimate. Award values are capped at EUR 100M and shown second: the raw data
# holds absurd amounts (2,067 awards above EUR 1bn, 200 above EUR 100bn), so shares of awards are the robust headline.
source("R/packages.R"); options(width = 200)
con <- dbConnect(duckdb())
xl  <- function(s) setDT(readxl::read_excel("data/meip/meip.xlsx", s))
reg <- xl("Group Register")[, .(parent = `Parent MNE`, iso3 = ISO3, sub_name = `Subsidiary Name (Clean)`, oc = OpenCorporates)]
hq  <- unique(xl("Pivot")[Heirarchy == "MNE Head", .(parent = `Parent MNE`, hq_iso3 = ISO3)])[!duplicated(parent)]
cc  <- rbind(xl("Country_Code_mapping")[, .(iso2 = `ISO-alpha2 Code`, iso3 = ISO3)], data.table(iso2 = "UK", iso3 = "GBR"))
for (t in c("reg", "hq", "cc")) dbWriteTable(con, t, get(t))

dbExecute(con, "CREATE MACRO norm(s) AS trim(regexp_replace(regexp_replace(regexp_replace(upper(strip_accents(replace(s, '.', ''))),
  '[^A-Z0-9]+', ' ', 'g'),
  '\\b(SA|SAS|SASU|SARL|EURL|SNC|SCA|SCS|SE|GMBH|AG|KG|CO|MBH|OHG|SRL|SRLS|SPA|SL|SLU|SAU|BV|NV|VOF|AB|OY|OYJ|AS|ASA|APS|A S|LTD|LIMITED|PLC|LLC|INC|CORP|CORPORATION|COMPANY|SP Z OO|SP Z O O|S R O|SRO|KFT|ZRT|NYRT|DOO|D O O|AD|EOOD|OOD|EAD|UAB|SIA|OU|AKTIENGESELLSCHAFT|GESELLSCHAFT MIT BESCHRANKTER HAFTUNG|SOCIETE ANONYME|SOCIEDAD ANONIMA|SOCIEDAD LIMITADA|SOCIETA PER AZIONI)\\b', ' ', 'g'),
  ' +', ' ', 'g'))")
dbExecute(con, "CREATE MACRO digits(s) AS regexp_replace(s, '[^0-9]', '', 'g')")
dbExecute(con, "CREATE MACRO regid(s, iso3) AS CASE WHEN iso3 = 'FRA' THEN left(digits(s), 9) ELSE digits(s) END")

dbExecute(con, "CREATE TABLE winners AS SELECT * FROM (
    SELECT winner, winner_country AS iso2, cc.iso3, norm(winner) AS name_norm, any_value(winner_id) AS winner_id,
           count(*) AS awards, sum(least(award_value_eur_fin1, 1e8)) AS value_capped
    FROM 'outputs/panel/award.parquet' a LEFT JOIN cc ON cc.iso2 = a.winner_country
    WHERE winner IS NOT NULL GROUP BY ALL) WHERE length(name_norm) >= 5")
dbExecute(con, "CREATE TABLE regn AS
  WITH r AS (SELECT DISTINCT parent, iso3, sub_name, norm(sub_name) AS name_norm, digits(regexp_extract(oc, '/(.*)$', 1)) AS oc_digits FROM reg),
       u AS (SELECT iso3, name_norm FROM r WHERE length(name_norm) >= 5 GROUP BY ALL HAVING count(DISTINCT parent) = 1)
  SELECT r.* FROM r JOIN u USING (iso3, name_norm)")

dbExecute(con, "CREATE TABLE m_exact AS
  SELECT w.winner, w.iso3, w.awards, w.value_capped, r.parent, r.sub_name, 1.0 AS sim, 'exact' AS how
  FROM winners w JOIN regn r USING (iso3, name_norm)
  QUALIFY row_number() OVER (PARTITION BY w.winner, w.iso3 ORDER BY r.sub_name) = 1")
dbExecute(con, "CREATE TABLE m_fuzzy AS
  SELECT * FROM (
    SELECT w.winner, w.iso3, w.awards, w.value_capped, r.parent, r.sub_name,
           jaro_winkler_similarity(w.name_norm, r.name_norm) AS sim, 'fuzzy' AS how
    FROM winners w JOIN regn r
      ON w.iso3 = r.iso3 AND split_part(w.name_norm, ' ', 1) = split_part(r.name_norm, ' ', 1) AND w.name_norm <> r.name_norm
    WHERE w.awards >= 3 OR w.value_capped >= 5e6)
  WHERE sim >= 0.95
  QUALIFY row_number() OVER (PARTITION BY winner, iso3 ORDER BY sim DESC) = 1")
dbExecute(con, "CREATE TABLE m_id AS
  SELECT w.winner, w.iso3, w.awards, w.value_capped, r.parent, r.sub_name, 1.0 AS sim, 'id' AS how
  FROM winners w JOIN regn r ON w.iso3 = r.iso3 AND length(regid(w.winner_id, w.iso3)) >= 6 AND regid(w.winner_id, w.iso3) = regid(r.oc_digits, r.iso3)
  QUALIFY row_number() OVER (PARTITION BY w.winner, w.iso3 ORDER BY r.sub_name) = 1")
dbExecute(con, "CREATE TABLE m AS
  SELECT * FROM (SELECT *, row_number() OVER (PARTITION BY winner, iso3 ORDER BY how = 'exact' DESC, how = 'id' DESC, sim DESC) AS rk
                 FROM (SELECT * FROM m_exact UNION ALL SELECT * FROM m_id UNION ALL SELECT * FROM m_fuzzy)) WHERE rk = 1")

cat("\n-- matched winners by method (first method that matched), shares of all awards with a named winner\n")
print(dbGetQuery(con, "SELECT how, count(*) AS winners, sum(awards) AS awards,
  round(100 * sum(awards) / (SELECT sum(awards) FROM winners), 2) AS pct_of_awards,
  round(sum(value_capped) / 1e9, 1) AS value_bn_capped, round(100 * sum(value_capped) / (SELECT sum(value_capped) FROM winners), 1) AS pct_of_value_capped
  FROM m GROUP BY 1 ORDER BY 1"))
cat("\n-- precision check: name matches where both sides carry a registration number, share where the numbers agree\n")
print(dbGetQuery(con, "SELECT m.how, count(*) AS checkable, round(100 * avg((regid(w.winner_id, w.iso3) = regid(r.oc_digits, r.iso3))::INT), 1) AS pct_ids_agree
  FROM m JOIN winners w USING (winner, iso3) JOIN regn r ON r.iso3 = m.iso3 AND r.sub_name = m.sub_name
  WHERE m.how IN ('exact', 'fuzzy') AND length(regid(w.winner_id, w.iso3)) >= 6 AND length(regid(r.oc_digits, r.iso3)) >= 6 GROUP BY 1"))
cat("\n-- share of awards going to top-500 subsidiaries, by winner country\n")
print(dbGetQuery(con, "SELECT w.iso3, sum(w.awards) AS awards, round(100 * sum(CASE WHEN m.winner IS NOT NULL THEN w.awards ELSE 0 END) / sum(w.awards), 1) AS pct_awards_mne,
  round(100 * sum(CASE WHEN m.winner IS NOT NULL THEN w.value_capped ELSE 0 END) / sum(w.value_capped), 1) AS pct_value_capped_mne
  FROM winners w LEFT JOIN m USING (winner, iso3) GROUP BY 1 ORDER BY awards DESC LIMIT 15"))
cat("\n-- top parents by awards\n")
print(dbGetQuery(con, "SELECT m.parent, hq.hq_iso3, count(*) AS winner_names, sum(awards) AS awards, round(sum(value_capped) / 1e9, 2) AS value_bn_capped
  FROM m LEFT JOIN hq USING (parent) GROUP BY 1, 2 ORDER BY awards DESC LIMIT 15"))
cat("\n-- fuzzy pairs to eyeball\n")
print(dbGetQuery(con, "SELECT winner, sub_name, parent, round(sim, 3) AS sim, awards FROM m WHERE how = 'fuzzy' ORDER BY awards DESC LIMIT 20"))

fwrite(setDT(dbGetQuery(con, "SELECT m.*, hq.hq_iso3 FROM m LEFT JOIN hq USING (parent)")), "outputs/meip_matches.csv")
system2("mc", c("--quiet", "cp", "outputs/meip_matches.csv", "s3/dorviya/diffusion/ted-ods/panel/"))
