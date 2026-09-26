# Step 2: one per-year zip -> one parquet file, every column kept as text (casting comes later).
# One file at a time to fit the 10 GB volume; each parquet is pushed to the bucket as it completes.
source("R/packages.R")
con    <- dbConnect(duckdb())
bucket <- "s3/dorviya/diffusion/ted-ods/parquet/"
zips   <- list.files("data/raw/zip", pattern = "notices-\\d{4}\\.zip$", full.names = TRUE)  # per-year files only
for (z in zips) {
  type <- if (grepl("award", z)) "can" else "cn"
  year <- sub(".*-(\\d{4})\\.zip$", "\\1", z)
  out  <- sprintf("data/parquet/%s_%s.parquet", type, year)
  if (!file.exists(out)) {
    csv <- unzip(z, exdir = "data/raw/csv")
    dbExecute(con, sprintf("COPY (SELECT * FROM read_csv('%s', header = true, all_varchar = true))
                            TO '%s' (FORMAT parquet, COMPRESSION zstd)", csv, out))
    file.remove(csv)
  }
  id <- if (type == "can") "ID_NOTICE_CAN" else "ID_NOTICE_CN"
  n  <- dbGetQuery(con, sprintf("SELECT count(*) AS rows, count(DISTINCT %s) AS notices FROM '%s'", id, out))
  system2("mc", c("--quiet", "cp", out, bucket))
  message(sprintf("%-18s %9d rows %8d notices %5.0f MB", basename(out), n$rows, n$notices, file.size(out) / 1e6))
}
dbDisconnect(con)
