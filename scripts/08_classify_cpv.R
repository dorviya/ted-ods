# Step 8: classify the CPV codes used in TED 2016-2023 into COFOG functions with an LLM, at codebook level:
# one call per batch of 40 codes, strict JSON. Same prompt for every provider so their agreement can be measured.
# Results are appended per batch to reference/cpv_cofog_<provider>.csv (a rerun resumes; failed batches are skipped
# and picked up next time). Usage: Rscript scripts/08_classify_cpv.R <openai|gemini> <model> [max_batches]
source("R/packages.R")
args <- commandArgs(trailingOnly = TRUE); provider <- args[1]; model <- args[2]
max_batches <- if (length(args) >= 3) as.integer(args[3]) else Inf
out <- sprintf("reference/cpv_cofog_%s.csv", provider)
system_prompt <- paste(readLines("docs/prompts/cpv_cofog_v1.md"), collapse = "\n")

con <- dbConnect(duckdb())
used <- setDT(dbGetQuery(con, "
  WITH lab AS (SELECT * FROM read_csv('reference/cpv_labels.csv', types = {'cpv': 'VARCHAR'})),
       u AS (SELECT cpv, count(*) AS notices FROM (SELECT cpv FROM 'outputs/panel/notice_cn.parquet' UNION ALL
                                                    SELECT cpv FROM 'outputs/panel/notice_can.parquet') GROUP BY 1)
  SELECT u.cpv, u.notices, l.label_en AS label, d.label_en AS division, g.label_en AS grp
  FROM u JOIN lab l USING (cpv)
  LEFT JOIN lab d ON d.cpv = u.cpv[1:2] || '000000'
  LEFT JOIN lab g ON g.cpv = u.cpv[1:3] || '00000'
  ORDER BY u.cpv"))
done <- if (file.exists(out)) fread(out, colClasses = list(character = "cpv"))$cpv else character()
todo <- used[!cpv %in% done]
message(nrow(used), " codes with a label; ", length(done), " done; ", nrow(todo), " to do")

ask <- function(user) {
  if (provider == "openai") {
    r <- request("https://api.openai.com/v1/chat/completions") |>
      req_auth_bearer_token(Sys.getenv("OPENAI_API_KEY")) |>
      req_body_json(list(model = model, response_format = list(type = "json_object"),
                         messages = list(list(role = "system", content = system_prompt), list(role = "user", content = user))))
  } else {
    r <- request(sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent", model)) |>
      req_headers(`x-goog-api-key` = Sys.getenv("GOOGLE_API_KEY")) |>
      req_body_json(list(systemInstruction = list(parts = list(list(text = system_prompt))),
                         contents = list(list(role = "user", parts = list(list(text = user)))),
                         generationConfig = list(responseMimeType = "application/json", temperature = 0)))
  }
  js <- r |> req_timeout(300) |>
    req_retry(max_tries = 5, backoff = \(i) 10 * i, is_transient = \(x) resp_status(x) %in% c(429, 500, 502, 503, 504)) |>
    req_perform() |> resp_body_json()
  txt <- if (provider == "openai") js$choices[[1]]$message$content else js$candidates[[1]]$content$parts[[1]]$text
  res <- jsonlite::fromJSON(gsub("^```json|^```|```$", "", trimws(txt)))
  setDT(if (is.data.frame(res)) res else res$items)
}

batches <- split(todo, ceiling(seq_len(nrow(todo)) / 40))
for (i in seq_len(min(length(batches), max_batches))) {
  b <- batches[[i]]
  user <- paste0("Classify these ", nrow(b), " CPV codes.\n",
                 paste(sprintf("%s | %s | division: %s | group: %s", b$cpv, b$label, b$division, b$grp), collapse = "\n"))
  res <- tryCatch(ask(user), error = \(e) { message("batch ", i, " failed: ", conditionMessage(e)); NULL })
  if (is.null(res) || !"cpv" %in% names(res)) next
  res[, names(res) := lapply(.SD, as.character)]
  res <- res[cpv %in% b$cpv][, `:=`(provider = provider, model = model, run_at = format(Sys.time(), "%Y-%m-%d %H:%M"))]
  fwrite(res, out, append = file.exists(out))
  message(sprintf("batch %d/%d  %d codes  %s", i, length(batches), nrow(res), format(Sys.time(), "%H:%M:%S")))
  Sys.sleep(1)
}
