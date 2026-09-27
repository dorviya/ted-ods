# Step 8: classify the CPV codes used in TED 2016-2023 into COFOG functions with an LLM, at codebook level: one call
# per batch of 40 codes, strict JSON. One output file per run (reference/cpv_cofog_<run_id>.csv); a rerun resumes.
# Runs vary one thing at a time (model, prompt, label language, batch order) so their agreement can be attributed.
# Usage: Rscript scripts/08_classify_cpv.R <openai|gemini> <model> <run_id> [prompt_file] [en|fr|de] [shuffle_seed] [max_batches]
source("R/packages.R")
a <- commandArgs(trailingOnly = TRUE); provider <- a[1]; model <- a[2]; run_id <- a[3]
prompt_file <- if (length(a) >= 4) a[4] else "docs/prompts/cpv_cofog_v1.md"
lang        <- if (length(a) >= 5) a[5] else "en"
seed        <- if (length(a) >= 6) as.integer(a[6]) else 0L
max_batches <- if (length(a) >= 7) as.integer(a[7]) else Inf
out  <- sprintf("reference/cpv_cofog_%s.csv", run_id)
keep <- c("cpv", "cofog_primary", "cofog_secondary", "secondary_condition", "justification", "confidence")
cols <- c(keep, "run", "provider", "model", "prompt", "lang", "seed", "run_at")
system_prompt <- paste(readLines(prompt_file), collapse = "\n")

con <- dbConnect(duckdb())
used <- setDT(dbGetQuery(con, sprintf("
  WITH lab AS (SELECT cpv, label_%s AS label FROM read_csv('reference/cpv_labels.csv', types = {'cpv': 'VARCHAR'})),
       u AS (SELECT cpv, count(*) AS notices FROM (SELECT cpv FROM 'outputs/panel/notice_cn.parquet' UNION ALL
                                                    SELECT cpv FROM 'outputs/panel/notice_can.parquet') GROUP BY 1)
  SELECT u.cpv, u.notices, l.label, d.label AS division, g.label AS grp
  FROM u JOIN lab l USING (cpv)
  LEFT JOIN lab d ON d.cpv = u.cpv[1:2] || '000000'
  LEFT JOIN lab g ON g.cpv = u.cpv[1:3] || '00000'
  ORDER BY u.cpv", lang)))
done <- if (file.exists(out)) fread(out, colClasses = "character")$cpv else character()
todo <- used[!cpv %in% done]
if (seed > 0) { set.seed(seed); todo <- todo[sample(.N)] }
message(run_id, ": ", nrow(used), " codes; ", length(done), " done; ", nrow(todo), " to do")

# The model's answer as one row per code, whatever shape it chose: {"items": [...]}, a bare array, or an object keyed
# by code. Extra fields are dropped, nested values flattened, nulls become NA.
parse_items <- function(txt) {
  js <- jsonlite::fromJSON(gsub("^```json|^```|```$", "", trimws(txt)), simplifyVector = FALSE)
  items <- if (is.list(js) && !is.null(js$items)) js$items else js
  if (!is.null(names(items)) && all(grepl("^[0-9]{8}$", names(items))))
    items <- Map(\(k, v) c(list(cpv = k), v), names(items), items)
  rbindlist(lapply(items, \(it) {
    if (!is.list(it)) return(NULL)
    it <- it[intersect(keep, names(it))]
    as.data.table(lapply(it, \(v) if (length(v) == 0) NA_character_ else paste(unlist(v), collapse = "; ")))
  }), fill = TRUE)
}

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
    req_retry(max_tries = 6, backoff = \(i) 10 * i, is_transient = \(x) resp_status(x) %in% c(429, 500, 502, 503, 504)) |>
    req_perform() |> resp_body_json()
  parse_items(if (provider == "openai") js$choices[[1]]$message$content else js$candidates[[1]]$content$parts[[1]]$text)
}

batches <- split(todo, ceiling(seq_len(nrow(todo)) / 40))
for (i in seq_len(min(length(batches), max_batches))) {
  b <- batches[[i]]
  user <- paste0("Classify these ", nrow(b), " CPV codes (labels in ", c(en = "English", fr = "French", de = "German")[[lang]], ").\n",
                 paste(sprintf("%s | %s | division: %s | group: %s", b$cpv, b$label, b$division, b$grp), collapse = "\n"))
  res <- tryCatch(ask(user), error = \(e) { message("batch ", i, " failed: ", conditionMessage(e)); if (grepl("40[12]", conditionMessage(e))) "STOP" else NULL })
  if (identical(res, "STOP")) { message("credentials or credits problem, stopping the run"); break }
  if (is.null(res) || !"cpv" %in% names(res) || nrow(res) == 0) { message("batch ", i, ": unusable answer, skipped"); next }
  res <- res[cpv %in% b$cpv]
  for (k in setdiff(cols, names(res))) res[, (k) := NA_character_]
  res[, `:=`(run = run_id, provider = provider, model = model, prompt = basename(prompt_file), lang = lang,
             seed = as.character(seed), run_at = format(Sys.time(), "%Y-%m-%d %H:%M"))]
  fwrite(res[, ..cols], out, append = file.exists(out))
  message(sprintf("%s batch %d/%d  %d codes  %s", run_id, i, length(batches), nrow(res), format(Sys.time(), "%H:%M:%S")))
  Sys.sleep(1)
}
