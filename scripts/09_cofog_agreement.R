# Step 9: agreement across the classification runs -> per-code consensus and uncertainty band; pairwise agreement between
# runs attributed to the one factor that differs (family, size, prompt, language, order, repeat).
# Output: reference/cpv_cofog_consensus.csv.
source("R/packages.R"); options(width = 200)
files <- list.files("reference", pattern = "^cpv_cofog_.*\\.csv$", full.names = TRUE); files <- files[!grepl("consensus", files)]
x <- rbindlist(setNames(lapply(files, fread, colClasses = "character"), sub("^cpv_cofog_(.*)\\.csv$", "\\1", basename(files))), idcol = "run", fill = TRUE)
x <- unique(x, by = c("run", "cpv"))
x[, div := fifelse(cofog_primary == "buyer-dependent", "BD", substr(cofog_primary, 1, 2))]
x[!div %in% c("BD", sprintf("%02d", 1:10)), div := "??"]

con <- dbConnect(duckdb())
w   <- setDT(dbGetQuery(con, "SELECT cpv, count(*) AS notices FROM (SELECT cpv FROM 'outputs/panel/notice_cn.parquet' UNION ALL SELECT cpv FROM 'outputs/panel/notice_can.parquet') GROUP BY 1"))
lab <- fread("reference/cpv_labels.csv", colClasses = list(character = "cpv"))[, .(cpv, label_en)]
cons <- x[, { t <- sort(table(div), decreasing = TRUE)
              .(n_runs = .N, consensus = names(t)[1], agree = as.numeric(t[1]) / .N, n_distinct = length(t),
                votes = paste(names(t), t, sep = ":", collapse = " ")) }, by = cpv]
cons <- merge(merge(cons, w, by = "cpv", all.x = TRUE), lab, by = "cpv", all.x = TRUE)
cons[, band := cut(agree, c(0, 0.5, 0.75, 0.999, 1), labels = c("contested (<=50%)", "majority (50-75%)", "strong (75-99%)", "unanimous"))]

cat("\n-- runs:", paste(sort(unique(x$run)), collapse = ", "), "\n-- codes:", nrow(cons), " mean runs per code:", round(mean(cons$n_runs), 1),
    " notice-weighted mean agreement:", round(cons[, weighted.mean(agree, notices, na.rm = TRUE)], 3), "\n")
print(cons[, .(codes = .N, pct_codes = round(100 * .N / nrow(cons), 1),
               pct_notices = round(100 * sum(notices, na.rm = TRUE) / sum(cons$notices, na.rm = TRUE), 1)), by = band][order(band)])
cat("\n-- consensus division, share of notices\n")
print(cons[, .(codes = .N, pct_notices = round(100 * sum(notices, na.rm = TRUE) / sum(cons$notices, na.rm = TRUE), 1)), by = consensus][order(-pct_notices)])
cat("\n-- most contested codes among the most used\n")
print(head(cons[agree <= 0.5][order(-notices)], 15)[, .(cpv, label = substr(label_en, 1, 55), notices, votes)])

runs <- sort(unique(x$run)); pw <- CJ(a = runs, b = runs)[a < b]
pw[, agree := mapply(\(a, b) { m <- merge(x[run == a, .(cpv, da = div)], x[run == b, .(cpv, db = div)], by = "cpv"); round(mean(m$da == m$db), 3) }, a, b)]
A <- rbindlist(lapply(runs, \(r) { p <- strsplit(r, "_")[[1]]
  data.table(run = r, family = p[1], size = fifelse(p[2] %in% c("large", "pro"), "large", "small"), prompt = p[3],
             lang = fifelse(p[4] == "fr", "fr", "en"), order = fifelse(p[4] == "shuf", "shuffled", "sorted")) }))
f <- c("family", "size", "prompt", "lang", "order")
pw[, factor := mapply(\(a, b) { d <- f[unlist(A[run == a, ..f]) != unlist(A[run == b, ..f])]
                                if (length(d) == 0) "repeat (noise floor)" else if (length(d) == 1) d else "several" }, a, b)]
cat("\n-- pairwise agreement between runs (share of common codes with the same division)\n")
print(dcast(pw, a ~ b, value.var = "agree"))
cat("\n-- agreement by the one factor that differs between two runs\n")
print(pw[factor != "several", .(pairs = .N, mean_agreement = round(mean(agree), 3), min = min(agree), max = max(agree)), by = factor][order(-mean_agreement)])
fwrite(cons, "reference/cpv_cofog_consensus.csv")
