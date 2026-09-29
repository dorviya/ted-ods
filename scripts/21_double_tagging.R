# scripts/21_double_tagging.R — secondary COFOG tags at code level (plurality of the 11 runs), the double-tagged share, the green share
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
files <- grep("consensus", list.files("reference", "^cpv_cofog_.*\\.csv$", full.names = TRUE), value = TRUE, invert = TRUE)
runs <- rbindlist(lapply(files, fread, colClasses = "character"), fill = TRUE)
sec <- runs[nzchar(trimws(cofog_secondary)), .(cpv, sec = substr(trimws(cofog_secondary), 1, 4))]
sec <- sec[, .(votes = .N), by = .(cpv, sec)][order(cpv, -votes)][, .SD[1], by = cpv]
sec[, `:=`(sec_div = substr(sec, 1, 2), green = substr(sec, 1, 2) == "05" | sec == "04.3")]
fwrite(sec, "reference/cpv_cofog_secondary.csv")
print(sec[, .(codes = .N), by = .(supported = votes >= 4)]); print(sec[votes >= 4, .N, by = sec_div][order(-N)])
dbWriteTable(con, "sec", sec[votes >= 4], overwrite = TRUE)

d <- q(sprintf("
  WITH map AS (SELECT cpv, consensus FROM read_csv('reference/cpv_cofog_consensus.csv', all_varchar = true)),
  n AS (
    SELECT coalesce(a.procedure_id, a.pub_number) AS proc, a.country, a.dispatch_date, s.sec_div, s.green,
           CASE WHEN a.value_eur BETWEEN 1e3 AND 1e9 AND NOT coalesce(a.framework, false) THEN a.value_eur END AS v,
           CASE WHEN m.consensus IS NULL THEN 'unmapped' WHEN m.consensus <> 'BD' THEN m.consensus ELSE %s END AS cofog
    FROM 'outputs/panel/notice_all.parquet' AS a LEFT JOIN map AS m ON a.cpv = m.cpv LEFT JOIN sec AS s ON a.cpv = s.cpv
    WHERE a.type = 'can' AND a.dispatch_date BETWEEN '2016-01-01' AND '2025-12-31' AND a.country IS NOT NULL),
  p AS (SELECT proc, any_value(country) AS country, year(min(dispatch_date)) AS year, arg_min(cofog, dispatch_date) AS cofog,
               arg_min(sec_div, dispatch_date) AS sec_div, bool_or(coalesce(green, false)) AS green, sum(DISTINCT v) AS value_eur
        FROM n GROUP BY 1)
  SELECT country, year, cofog, coalesce(sec_div, 'none') AS sec_div, green, count(*) AS procedures, sum(value_eur) AS value_eur
  FROM p GROUP BY 1, 2, 3, 4, 5", activity_cofog_sql))
fwrite(d, "outputs/quality/double_tagging_year.csv")

# A — one purchase, two purposes: share of awarded value with a secondary tag, by primary division
dd <- d[cofog %in% names(cofog_names)]
tagged <- dd[, sum(value_eur[sec_div != "none"], na.rm = TRUE) / sum(value_eur, na.rm = TRUE)]
dt <- dd[, .(v = sum(value_eur, na.rm = TRUE)), by = .(cofog, sec_div)][, share := v / sum(v), by = cofog][sec_div != "none"]
top <- dt[, .(v = sum(v)), by = sec_div][order(-v)][1:min(5, .N), sec_div]
dt[, sec_lab := fifelse(sec_div %in% top, cofog_names[sec_div], "Other secondary")]
dt <- dt[, .(share = sum(share)), by = .(cofog, sec_lab)]
dt[, `:=`(fn = factor(cofog_names[cofog], levels = rev(cofog_names)), sec_lab = factor(sec_lab, levels = c(cofog_names[top], "Other secondary")))]
pA <- ggplot(dt, aes(share, fn, fill = sec_lab)) + geom_col(width = 0.72) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_manual(values = c(unname(cofog_colours[cofog_names[top]]), "grey80")) +
  labs(title = sprintf("One purchase, two purposes: %.0f%% of awarded value carries a second government function", 100 * tagged),
       subtitle = paste("Share of awarded value whose product code carries a secondary COFOG tag, by primary division, 2016–2025, 33 countries;",
                        "colour: the secondary division. Tags: plurality of the 11 LLM runs, at least 4 votes."),
       caption = paste(ted_source, "Code-level tags only; conditional tags (e.g. 'electric' vehicles) not yet applied.")) +
  theme_ted(base_size = 14) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(pA, "06_double_tagging.png")

# B — the green share of awarded value, by country and year
sel12 <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT")
gg <- d[, .(green = sum(value_eur[green == TRUE], na.rm = TRUE) / sum(value_eur, na.rm = TRUE)), by = year][order(year)]
g <- d[country %in% sel12, .(green = sum(value_eur[green == TRUE], na.rm = TRUE) / sum(value_eur, na.rm = TRUE)), by = .(country, year)]
g[, name := factor(ted_countries[country], levels = ted_countries[sel12])]
pB <- ggplot(g, aes(year, green)) + geom_line(colour = pal_ted[4], linewidth = 0.9) + geom_point(colour = pal_ted[4], size = 1.6) +
  facet_wrap(~ name, ncol = 4) +
  scale_x_continuous(breaks = c(2016, 2019, 2022, 2025), labels = function(x) paste0("'", substr(x, 3, 4))) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1), limits = c(0, NA)) +
  labs(title = sprintf("The green share of public demand: %.0f%% of awarded value in 2025, %.0f%% in 2016 — a code-level lower bound",
                       100 * gg[year == 2025, green], 100 * gg[year == 2016, green]),
       subtitle = "Share of awarded value whose product carries a secondary tag in environmental protection (05) or energy (04.3), by year and buyer country.",
       caption = paste(ted_source, "Code-level tags only; conditional tags (electric, solar, energy-efficient) not applied.")) +
  theme_ted(base_size = 13) + theme(panel.spacing.x = unit(1.6, "lines"))
save_fig(pB, "07_green_share.png")
print(gg)

# C — the green keywords in calls, monthly to last month (API period, titles and descriptions)
kw <- q(sprintf("SELECT country, date_trunc('month', pub_date)::date AS m, count(*) AS calls,
                 count(*) FILTER (WHERE regexp_matches(lower(coalesce(title, '') || ' ' || coalesce(description, '')), '%s')) AS green
                 FROM 'outputs/panel/notice_api.parquet'
                 WHERE type = 'cn' AND country IN ('DE','FR','IT','ES','PL','NL','SE','AT') AND pub_date BETWEEN '2023-11-01' AND '2026-08-31'
                 GROUP BY 1, 2", green_regex))
kw[, `:=`(share = green / calls, name = factor(ted_countries[country], levels = ted_countries[c("DE","FR","IT","ES","PL","NL","SE","AT")]))]
pC <- ggplot(kw, aes(m, share)) + geom_line(colour = pal_ted[4], linewidth = 0.8) +
  facet_wrap(~ name, ncol = 4) + scale_y_continuous(labels = scales::label_percent(accuracy = 1), limits = c(0, NA)) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(title = sprintf("%.0f%% of calls for tenders mention electric, solar, heat pumps or energy efficiency — monthly, up to last month", 100 * kw[, sum(green) / sum(calls)]),
       subtitle = "Share of calls for tenders whose title or description contains a green keyword (multilingual list), by month and buyer country, November 2023 – August 2026.",
       caption = paste(ted_source, "Keyword pass on eForms notices (descriptions available for 94% of notices); an indicator of mentions, not of green purchasing.")) +
  theme_ted(base_size = 13)
save_fig(pC, "08_green_keywords.png")
print(q("SELECT year(pub_date) AS y, count(*) FILTER (WHERE regexp_matches(lower(coalesce(title, '') || ' ' || coalesce(description, '')), 'gender equality|gender mainstreaming|égalité femmes|égalité professionnelle|égalité des sexes|gleichstellung|igualdad de género|parità di genere|równość płci|równości płci|gendergelijkheid')) AS gender, count(*) AS calls FROM 'outputs/panel/notice_api.parquet' WHERE type = 'cn' GROUP BY 1 ORDER BY 1"))
