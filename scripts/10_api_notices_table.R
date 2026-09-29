# Step 10: build outputs/panel/notice_api.parquet from the raw API pages, one month at a time (the whole span at once
# exceeds the pod's memory), through the duckdb CLI (the R package lacks the json extension here); check; push to the bucket.
source("R/packages.R"); options(width = 200)
tpl <- paste(readLines("scripts/10_api_notices_table.sql"), collapse = "\n")
dir.create("data/api/table_v2", showWarnings = FALSE)
for (f in sort(list.files("data/api/notices_v2", "\\.jsonl\\.gz$", full.names = TRUE))) {
  out <- file.path("data/api/table_v2", sub("\\.jsonl\\.gz$", ".parquet", basename(f)))
  if (file.exists(out)) next
  sql <- gsub("__OUTPUT__", out, gsub("__INPUT__", f, tpl, fixed = TRUE), fixed = TRUE)
  if (system2("duckdb", input = sql, stdout = FALSE) != 0) stop("month failed: ", f)
  message(basename(out), "  ", format(Sys.time(), "%H:%M:%S"))
}
con <- dbConnect(duckdb())
dbExecute(con, "COPY (SELECT * FROM read_parquet('data/api/table_v2/*.parquet', union_by_name = true))
                TO 'outputs/panel/notice_api.parquet' (FORMAT parquet, COMPRESSION zstd)")
dbExecute(con, "CREATE VIEW api AS SELECT * FROM 'outputs/panel/notice_api.parquet'")
print(dbGetQuery(con, "SELECT count(*) AS notices, min(pub_date) AS first, max(pub_date) AS last, count(DISTINCT country) AS countries,
  round(avg((main_activity IS NOT NULL)::INT), 2) AS has_activity, round(avg((buyer_legal_type IS NOT NULL)::INT), 2) AS has_legal_type,
  round(avg((procedure_id IS NOT NULL)::INT), 2) AS has_procedure_id, round(avg((description IS NOT NULL)::INT), 2) AS has_description FROM api"))
print(dbGetQuery(con, "SELECT type, count(*) AS notices, round(avg((coalesce(total_value, est_value, est_value_lots) IS NOT NULL)::INT), 2) AS has_value,
  round(avg(framework::INT), 2) AS framework, round(avg(eu_funds::INT), 2) AS eu_funds, round(avg((winner_country IS NOT NULL)::INT), 2) AS has_winner_cty,
  round(avg((award_date IS NOT NULL)::INT), 2) AS has_award_date FROM api GROUP BY 1"))
cnt <- fread("data/api/counts.csv")[country == "ALL" & type %in% c("competition", "result")][, .(month = format(month, "%Y-%m"), form_type = type, counted = n)]
prs <- setDT(dbGetQuery(con, "SELECT month, form_type, count(*) AS parsed FROM api GROUP BY ALL"))
print(merge(prs, cnt, by = c("month", "form_type"))[order(-month)][1:6])
system2("mc", c("--quiet", "cp", "outputs/panel/notice_api.parquet", "s3/dorviya/diffusion/ted-ods/panel/"))
cat("written:", round(file.size("outputs/panel/notice_api.parquet") / 1e6), "MB\n")
