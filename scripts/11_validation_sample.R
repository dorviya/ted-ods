# Step 11: 200 notices with text for hand-labelling, stratified by the agreement band of their CPV code.
# outputs/validation_sample.csv is for the labellers (machine labels withheld); outputs/validation_key.csv holds them.
source("R/packages.R")
con <- dbConnect(duckdb()); dbExecute(con, "SELECT setseed(0.42)")
cons <- fread("reference/cpv_cofog_consensus.csv", colClasses = list(character = "cpv")); dbWriteTable(con, "cons", cons)
lab  <- fread("reference/cpv_labels.csv", colClasses = list(character = "cpv")); dbWriteTable(con, "lab", lab)
s <- setDT(dbGetQuery(con, "
  WITH pool AS (
    SELECT a.pub_number, a.type, a.country, a.lang, a.cpv, l.label_en, a.buyer_name, a.title, left(a.description, 1500) AS description,
           c.band, c.consensus, c.agree, c.votes
    FROM 'outputs/panel/notice_api.parquet' a JOIN cons c USING (cpv) JOIN lab l USING (cpv)
    WHERE a.description IS NOT NULL AND length(a.description) BETWEEN 80 AND 4000 AND a.lang IN ('fra', 'eng', 'deu', 'spa', 'ita'))
  SELECT * FROM (SELECT *, row_number() OVER (PARTITION BY band ORDER BY random()) AS rn FROM pool)
  WHERE rn <= CASE WHEN band LIKE 'unanimous%' THEN 60 WHEN band LIKE 'strong%' THEN 50 WHEN band LIKE 'majority%' THEN 50 ELSE 40 END
  ORDER BY random()"))
s[, sample_id := seq_len(.N)]
fwrite(s[, .(sample_id, pub_number, type, country, lang, cpv, label_en, buyer_name, title, description,
             human_cofog_primary = "", human_cofog_secondary = "", comment = "")], "outputs/validation_sample.csv")
fwrite(s[, .(sample_id, pub_number, cpv, band, consensus, agree, votes)], "outputs/validation_key.csv")
print(s[, .N, by = .(band, lang)][order(band, -N)])
