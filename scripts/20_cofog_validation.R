# scripts/20_cofog_validation.R — does the functional panel hold up? Eurostat comparison, LLM sensitivity, human labels
source("R/packages.R"); source("R/theme.R")

# A — credibility scatter: TED share of awarded value by function vs Eurostat share of procurement-type expenditure (P2 + P51G), 2022
es <- fread("reference/eurostat_gov_10a_exp.csv")
if ("TIME_PERIOD" %in% names(es)) setnames(es, "TIME_PERIOD", "time"); if ("OBS_VALUE" %in% names(es)) setnames(es, "OBS_VALUE", "values")
es <- es[na_item %in% c("P2", "P51G") & cofog99 %in% sprintf("GF%02d", 1:10) & as.character(time) == "2022",
         .(off = sum(values, na.rm = TRUE)), by = .(geo, cofog = sub("GF", "", cofog99))][, off_share := off / sum(off), by = geo]
es[, country := names(eurostat_geo)[match(geo, eurostat_geo)]]
ted <- fread("outputs/quality/cofog_shares_year.csv")[type == "can" & year == 2022 & cofog %in% sprintf("%02d", 1:10),
         .(country, cofog, ted = value_eur)][, ted_share := ted / sum(ted), by = country]
sc <- merge(ted, es[!is.na(country), .(country, cofog, off_share)], by = c("country", "cofog"))
sc <- sc[country %in% c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT", "FI", "NO", "IE", "RO") & ted_share > 0 & off_share > 0]
r_all <- sc[, cor(log(ted_share), log(off_share))]
rc <- sc[, .(r = round(cor(log(ted_share), log(off_share)), 2)), by = country]
sc[, `:=`(name = factor(ted_countries[country], levels = ted_countries[unique(country)]), fn = factor(cofog_names[cofog], levels = cofog_names))]
rc[, name := factor(ted_countries[country], levels = levels(sc$name))]
pa <- ggplot(sc, aes(off_share, ted_share, colour = fn)) +
  geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "22") +
  geom_point(size = 2.6) +
  geom_text(data = rc, aes(x = 0.006, y = 0.45, label = paste0("r = ", r)), inherit.aes = FALSE, hjust = 0, size = 3.2, colour = "grey35") +
  facet_wrap(~ name, ncol = 4) +
  scale_x_log10(limits = c(0.005, 0.6), labels = scales::label_percent(accuracy = 1)) +
  scale_y_log10(limits = c(0.005, 0.6), labels = scales::label_percent(accuracy = 1)) +
  scale_colour_manual(values = cofog_colours) + guides(colour = guide_legend(nrow = 2, byrow = TRUE)) +
  labs(title = sprintf("TED's functional structure tracks official expenditure: correlation %.2f across %d countries × 10 functions (2022)", r_all, uniqueN(sc$country)),
       subtitle = paste("Share of TED awarded value by COFOG division (vertical) against the share of general-government intermediate consumption plus investment",
                        "by function, Eurostat gov_10a_exp (horizontal), 2022, log scales. Dotted: equality."),
       caption = paste(ted_source, "Eurostat: P.2 + P.51G, S.13. TED: values €1,000–€1 billion, one per procedure and value, frameworks excluded; unresolved functions dropped.")) +
  theme_ted(base_size = 13) + theme(aspect.ratio = 1, legend.text = element_text(size = 10))
save_fig(pa, "04_cofog_vs_eurostat.png")
print(rc[order(-r)])

# B — LLM sensitivity: agreement between pairs of the 11 runs, by the factor that differs
files <- grep("consensus", list.files("reference", "^cpv_cofog_.*\\.csv$", full.names = TRUE), value = TRUE, invert = TRUE)
runs <- rbindlist(lapply(files, fread, colClasses = "character"), fill = TRUE)
runs[, div := fifelse(cofog_primary == "BD", "BD", substr(cofog_primary, 1, 2))]
w <- dcast(runs[, .(cpv, run, div)], cpv ~ run, value.var = "div"); rn <- setdiff(names(w), "cpv")
parts <- function(r) { x <- strsplit(r, "_")[[1]]; list(prov = x[1], model = x[2], prompt = x[3], variant = x[4]) }
kind <- function(a, b) {
  pa <- parts(a); pb <- parts(b); d <- names(pa)[unlist(pa) != unlist(pb)]
  if (identical(d, "variant")) { v <- setdiff(c(pa$variant, pb$variant), "en")
    if (length(v) == 1) switch(v, rep = "Exact repeat (noise floor)", shuf = "Batch order", fr = "Label language", "Several factors") else "Several factors"
  } else if (identical(d, "prompt")) "Prompt wording" else if (identical(d, "model")) "Model size (same family)"
  else if (setequal(d, c("prov", "model"))) "Model family" else "Several factors" }
pr <- as.data.table(t(combn(rn, 2)))[, .(a = V1, b = V2)]
pr[, `:=`(agreement = mapply(function(a, b) mean(w[[a]] == w[[b]], na.rm = TRUE), a, b), factor = mapply(kind, a, b))]
lv <- c("Exact repeat (noise floor)", "Label language", "Prompt wording", "Batch order", "Model size (same family)", "Model family", "Several factors")
pr[, factor := factor(factor, levels = rev(lv))]
fac <- pr[, .(pairs = .N, mean_agreement = round(mean(agreement), 3), min = round(min(agreement), 3)), by = factor][order(-as.integer(factor))]
fwrite(pr, "outputs/quality/llm_pairwise_agreement.csv"); fwrite(fac, "outputs/quality/llm_factor_table.csv"); print(fac)
cons <- fread("reference/cpv_cofog_consensus.csv", colClasses = "character")[, notices := as.numeric(notices)]
print(cons[, .(codes = .N, notices = sum(notices)), by = band][, share := round(notices / sum(notices), 3)][])
nf <- fac[factor == "Exact repeat (noise floor)", mean_agreement]; ff <- fac[factor == "Model family", mean_agreement]
pb <- ggplot(pr[factor != "Several factors"], aes(agreement, factor)) +
  geom_point(colour = pal_ted[1], size = 3, alpha = 0.7) +
  stat_summary(fun = mean, geom = "point", shape = 124, size = 8, colour = pal_ted[3]) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1), limits = c(0.75, 1)) +
  labs(title = sprintf("How stable is the LLM mapping? The same model run twice agrees on %.0f%% of codes; two model families on %.0f%%", 100 * nf, 100 * ff),
       subtitle = paste("Agreement on the COFOG division (or 'buyer-dependent') between pairs of the 11 classification runs of 8,215 CPV codes,",
                        "by the factor that differs between the two runs. Orange bar: mean."),
       caption = "Source: reference/cpv_cofog_*.csv — 11 runs (OpenAI and Gemini models, two prompts, English and French labels, shuffled batches, one exact repeat); authors' calculations.") +
  theme_ted(base_size = 14) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(pb, "05_llm_sensitivity.png")

# C — human labels, if the economists have filled outputs/validation_sample.csv
vs <- fread("outputs/validation_sample.csv", colClasses = "character"); key <- fread("outputs/validation_key.csv", colClasses = "character")
if (any(nzchar(trimws(vs$human_cofog_primary)))) {
  con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
  act <- q("SELECT pub_number, any_value(activity) AS activity FROM 'outputs/panel/notice_all.parquet' GROUP BY 1")
  amap <- c(`gen-pub` = "01", defence = "02", `pub-os` = "03", `econ-aff` = "04", `env-pro` = "05", `hc-am` = "06", health = "07", rcr = "08",
            education = "09", `soc-pro` = "10", water = "06", electricity = "04", `gas-heat` = "04", `gas-oil` = "04", `solid-fuel` = "04",
            extraction = "04", rail = "04", urttb = "04", airport = "04", port = "04", post = "04")
  v <- merge(vs[, .(sample_id, pub_number, human = substr(trimws(human_cofog_primary), 1, 2))], key[, .(sample_id, band, consensus)], by = "sample_id")
  v <- merge(v, act, by = "pub_number", all.x = TRUE)[nzchar(human)]
  v[, machine := fifelse(consensus == "BD", amap[activity], consensus)]
  print(v[, .(n = .N, agreement = round(mean(human == machine, na.rm = TRUE), 2)), by = band][order(-n)])
  print(v[, .(n = .N, agreement = round(mean(human == machine, na.rm = TRUE), 2))])
  fwrite(v, "outputs/quality/validation_result.csv")
} else cat("Human labels not filled yet (outputs/validation_sample.csv): validation skipped.\n")
