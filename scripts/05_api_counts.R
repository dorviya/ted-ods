# Step 5: monthly notice counts from the TED Search API, per country and notice type, 2016 -> today.
# One request per cell, most recent months first. Results are appended to data/api/counts.csv as they
# arrive and copied to the bucket every 500 requests. Rerunnable: cells already counted are skipped,
# cells with NA are retried (deduplicate on read, keeping the last row per cell).
source("R/packages.R")
countries <- c("AUT","BEL","BGR","HRV","CYP","CZE","DNK","EST","FIN","FRA","DEU","GRC","HUN","IRL","ITA","LVA","LTU",
               "LUX","MLT","NLD","POL","PRT","ROU","SVK","SVN","ESP","SWE","NOR","ISL","LIE","CHE","GBR","MKD","ALL")
types  <- c(cn = "notice-type=cn-standard", can = "notice-type=can-standard",
            competition = "form-type=competition", result = "form-type=result")
months <- rev(as.character(seq(as.Date("2016-01-01"), Sys.Date(), by = "month")))
out    <- "data/api/counts.csv"; dir.create("data/api", showWarnings = FALSE)
done   <- if (file.exists(out)) fread(out)[!is.na(n), paste(month, country, type)] else character()

ted_count <- function(query) {
  resp <- tryCatch(
    request("https://api.ted.europa.eu/v3/notices/search") |>
      req_headers(Accept = "application/json") |>
      req_body_json(list(query = query, fields = list("publication-number"), page = 1, limit = 1,
                         scope = "ALL", paginationMode = "PAGE_NUMBER")) |>
      req_retry(max_tries = 6, backoff = \(i) 5 * i,
                is_transient = \(r) resp_status(r) %in% c(429, 500, 502, 503, 504)) |>
      req_error(is_error = \(r) FALSE) |>
      req_perform(),
    error = \(e) NULL)
  if (!is.null(resp) && resp_status(resp) == 200) resp_body_json(resp)$totalNoticeCount else NA_integer_
}

i <- 0
for (m in months) for (cty in countries) for (ty in names(types)) {
  if (paste(m, cty, ty) %in% done) next
  d0 <- as.Date(m); d1 <- seq(d0, by = "month", length.out = 2)[2] - 1
  q  <- sprintf("publication-date>=%s AND publication-date<=%s AND %s%s", format(d0, "%Y%m%d"), format(d1, "%Y%m%d"),
                types[[ty]], if (cty == "ALL") "" else paste0(" AND buyer-country=", cty))
  fwrite(data.table(month = m, country = cty, type = ty, n = ted_count(q), asof = Sys.Date()), out, append = file.exists(out))
  Sys.sleep(0.5)
  if ((i <- i + 1) %% 500 == 0) { system2("mc", c("--quiet", "cp", out, "s3/dorviya/diffusion/ted-ods/api/")); message(i, " requests, at ", m) }
}
system2("mc", c("--quiet", "cp", out, "s3/dorviya/diffusion/ted-ods/api/"))
message("done ", Sys.time())
