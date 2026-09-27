# Step 10: build outputs/panel/notice_api.parquet from the raw API pages (SQL in 10_api_notices_table.sql, run by the
# duckdb CLI because the R package lacks the json extension here), check it, push it to the bucket.
source("R/packages.R"); options(width = 200)
status <- system2("duckdb", c("-c", ".read scripts/10_api_notices_table.sql")); stopifnot(status == 0)
con <- dbConnect(duckdb()); dbExecute(con, "CREATE VIEW api AS SELECT * FROM 'outputs/panel/notice_api.parquet'")
print(dbGetQuery(con, "SELECT count(*) AS notices, min(pub_date) AS first, max(pub_date) AS last, count(DISTINCT country) AS countries,
  round(avg((country IS NULL)::INT), 3) AS unmapped_country FROM api"))
print(dbGetQuery(con, "SELECT month, type, count(*) AS notices, round(avg((description IS NOT NULL)::INT), 2) AS has_description,
  round(avg((coalesce(total_value, est_value) IS NOT NULL)::INT), 2) AS has_value, round(avg((nuts2 IS NOT NULL)::INT), 2) AS has_nuts2
  FROM api GROUP BY ALL ORDER BY 1 DESC, 2 LIMIT 10"))
cnt <- fread("data/api/counts.csv")[country == "ALL" & type %in% c("competition", "result")][, .(month = format(month, "%Y-%m"), form_type = type, counted = n)]
prs <- setDT(dbGetQuery(con, "SELECT month, form_type, count(*) AS parsed FROM api GROUP BY ALL"))
print(merge(prs, cnt, by = c("month", "form_type"))[order(-month)][1:8])
system2("mc", c("--quiet", "cp", "outputs/panel/notice_api.parquet", "s3/dorviya/diffusion/ted-ods/panel/"))
cat("written:", round(file.size("outputs/panel/notice_api.parquet") / 1e6), "MB\n")
