# Step 6 (v2): every competition and result notice published from October 2023 (where the CSV thins out) to today, with
# text, buyer activity and legal type, lot-level values, framework and EU-funds flags, winner country and size, award
# date and the procedure identifier. One gzipped file of raw response pages per month (newline-delimited JSON, 250
# notices per page) in api/notices_v2/. Newest month first; months already in the bucket are skipped; a failed month is
# logged and redone on the next run; a rejected field list stops the run immediately.
source("R/packages.R")
fields <- c("publication-number","publication-date","dispatch-date","notice-type","form-type","procedure-identifier",
            "buyer-country","buyer-name","organisation-identifier-buyer","main-activity","entity-main-activity","buyer-legal-type",
            "classification-cpv","place-of-performance","contract-nature","procedure-type",
            "title-proc","description-proc","title-lot","description-lot",
            "estimated-value-proc","estimated-value-cur-proc","estimated-value-lot","estimated-value-cur-lot",
            "framework-agreement-lot","framework-maximum-value-lot","framework-maximum-value-cur-lot","eu-fund-lot","funding",
            "duration-period-value-lot","duration-period-unit-lot",
            "total-value","total-value-cur","tender-value","tender-value-cur",
            "winner-name","organisation-identifier-tenderer","winner-identifier","winner-country","winner-size","winner-decision-date")
bucket <- "s3/dorviya/diffusion/ted-ods/api/notices_v2/"
dir.create("data/api/notices_v2", showWarnings = FALSE, recursive = TRUE)
months    <- rev(as.character(seq(as.Date("2023-10-01"), Sys.Date(), by = "month")))
in_bucket <- suppressWarnings(system2("mc", c("ls", bucket), stdout = TRUE, stderr = FALSE))

ted_page <- function(query, token = NULL) {
  body <- list(query = query, fields = fields, limit = 10000 %/% (length(fields) + 1), scope = "ALL", paginationMode = "ITERATION")
  if (!is.null(token)) body$iterationNextToken <- token
  request("https://api.ted.europa.eu/v3/notices/search") |>
    req_headers(Accept = "application/json") |> req_body_json(body) |> req_timeout(120) |>
    req_error(body = \(r) substr(tryCatch(resp_body_json(r)$message, error = \(e) ""), 1, 300)) |>
    req_retry(max_tries = 8, backoff = \(i) 5 * i, is_transient = \(r) resp_status(r) %in% c(429, 500, 502, 503, 504)) |>
    req_perform() |> resp_body_string()
}

for (m in months) {
  file <- sprintf("%s.jsonl.gz", m); path <- file.path("data/api/notices_v2", file)
  if (any(grepl(file, in_bucket, fixed = TRUE))) { message("skip ", m); next }
  d0 <- as.Date(m); d1 <- seq(d0, by = "month", length.out = 2)[2] - 1
  q  <- sprintf("publication-date>=%s AND publication-date<=%s AND form-type IN (competition, result)",
                format(d0, "%Y%m%d"), format(d1, "%Y%m%d"))
  out <- gzfile(path, "w"); token <- NULL; n <- 0; pages <- 0; total <- NA
  ok <- tryCatch({
    repeat {
      txt <- ted_page(q, token); js <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
      writeLines(gsub("[\r\n]", "", txt), out)
      pages <- pages + 1; n <- n + length(js$notices); token <- js$iterationNextToken
      if (pages == 1) total <- js$totalNoticeCount
      if (length(js$notices) == 0 || is.null(token) || n >= total) break
      Sys.sleep(0.5)
    }; TRUE }, error = \(e) { message("FAILED ", m, ": ", conditionMessage(e)); if (grepl("HTTP 400", conditionMessage(e))) "STOP" else FALSE })
  close(out)
  if (identical(ok, "STOP")) { file.remove(path); message("field list rejected, stopping"); break }
  if (!isTRUE(ok)) { file.remove(path); next }
  system2("mc", c("--quiet", "cp", path, bucket))
  fwrite(data.table(month = m, total = total, fetched = n, pages = pages, asof = Sys.Date()),
         "data/api/notices_v2_log.csv", append = file.exists("data/api/notices_v2_log.csv"))
  message(sprintf("%s  %d / %d notices in %d pages  %s", m, n, total, pages, format(Sys.time(), "%H:%M")))
}
