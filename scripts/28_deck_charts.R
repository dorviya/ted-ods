# scripts/28_deck_charts.R — the deck versions of the selected charts: 16:9 with titles (outputs/figures/deck/) and 12.4 × 5.3 in
# without title, subtitle or caption for the slides (outputs/figures/deck/slides/), text sized for an auditorium.
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
dir.create("outputs/figures/deck/slides", recursive = TRUE, showWarnings = FALSE)
save_deck <- function(p, name, base_slide = 21) {
  ggsave(file.path("outputs/figures/deck", name), p, width = 16, height = 9, dpi = 200, bg = "white")
  ggsave(file.path("outputs/figures/deck/slides", name), p + labs(title = NULL, subtitle = NULL, caption = NULL) + theme(text = element_text(size = base_slide)),
         width = 12.4, height = 5.3, dpi = 300, bg = "white")
}
dots <- guides(fill = guide_legend(override.aes = list(shape = 21, size = 5.5, colour = NA)))       # round legend keys for fills
yrs  <- scale_x_continuous(breaks = c(2016, 2020, 2024), expand = expansion(mult = 0.03))
pct  <- function(acc = 1) scales::label_percent(accuracy = acc)
hgrid <- theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
sel12 <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT")
nm <- function(x) factor(ted_countries[x], levels = ted_countries[sel12])
LS <- 4.8   # in-chart text size (≈ 14 pt)

# 00 — the data at a glimpse: four panels, six categories each
base <- "WITH p AS (SELECT coalesce(procedure_id, pub_number) AS proc, arg_min(contract_type, dispatch_date) AS contract_type,
  arg_min(buyer_type, dispatch_date) AS buyer_type, arg_min(activity, dispatch_date) AS activity, arg_min(cpv_div, dispatch_date) AS cpv_div
  FROM 'outputs/panel/notice_all.parquet' WHERE type = 'cn' AND dispatch_date BETWEEN '2016-01-01' AND '2025-12-31' AND country IS NOT NULL GROUP BY 1)"
dim <- function(panel, col) q(sprintf("%s SELECT '%s' AS panel, coalesce(%s, 'unknown') AS category, count(*) AS n FROM p GROUP BY 1, 2", base, panel, col))
s <- rbind(dim("What is bought", "cpv_div"), dim("Contract type", "contract_type"), dim("Who buys", "buyer_type"), dim("Buyer activity", "activity"))
lab <- list("Contract type" = c(U = "Supplies", S = "Services", W = "Works"),
  "Who buys" = c(central = "Central government", `regional-local` = "Regional or local", `public-law-body` = "Public-law body", utility = "Utility", `eu-international` = "EU / international", other = "Other"),
  "Buyer activity" = c(`gen-pub` = "General public services", health = "Health", education = "Education", `hc-am` = "Housing & amenities", `env-pro` = "Environment",
                         `econ-aff` = "Economic affairs", defence = "Defence", `pub-os` = "Public order", `soc-pro` = "Social protection", rcr = "Culture & recreation",
                         electricity = "Electricity", rail = "Rail", urttb = "Urban transport", water = "Water", other = "Other"),
  "What is bought" = c(`45` = "Construction", `71` = "Engineering & architecture", `33` = "Medical & pharma", `90` = "Waste, sewage, environment", `79` = "Business services",
                       `34` = "Vehicles & transport equipment", `50` = "Repair & maintenance", `72` = "IT services", `80` = "Education & training", `09` = "Fuels & electricity"))
for (p in names(lab)) s[panel == p, category := fifelse(category %in% names(lab[[p]]), lab[[p]][category], "Other")]
s <- s[, .(n = sum(n)), by = .(panel, category)][, share := n / sum(n), by = panel]
s[, rank := frank(-share, ties.method = "first"), by = panel][rank > 6 & category != "Other", category := "Other"]
s <- s[, .(share = sum(share)), by = .(panel, category)][, ord := fifelse(category == "Other", 1, -share)]
setorder(s, panel, ord); s[, id := factor(paste0(panel, "|", category), levels = rev(paste0(panel, "|", category)))]
s[, panel := factor(panel, levels = c("What is bought", "Contract type", "Who buys", "Buyer activity"))]
p00 <- ggplot(s, aes(share, id)) + geom_col(fill = pal_ted[1], width = 0.7) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * share)), hjust = -0.15, size = LS, colour = "grey30") +
  facet_wrap(~ panel, scales = "free", nrow = 1) + scale_y_discrete(labels = function(x) sub("^[^|]*\\|", "", x)) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.35)), labels = NULL) +
  labs(title = "2.6 million calls for tenders in ten years: what public buyers announce, who they are",
       subtitle = "Shares of procedures (calls for tenders), 2016–2025, 33 countries. Not shown: 86% of procedures are open; the median award lies between €100,000 and €1 million.",
       caption = ted_source) + theme_ted() + theme(panel.grid = element_blank(), panel.spacing.x = unit(2.2, "lines"))
save_deck(p00, "00_glimpse.png")

# 01 — the pulse (14 panels in two rows)
m <- fread("outputs/quality/monthly_procedures.csv")[type == "cn" & month < as.IDate("2026-09-01")]
sel14 <- c(DE = "Germany", FR = "France", PL = "Poland", ES = "Spain", IT = "Italy", CZ = "Czechia", SE = "Sweden", NL = "Netherlands", AT = "Austria", BE = "Belgium", DK = "Denmark", PT = "Portugal", NO = "Norway", FI = "Finland")
d <- rbind(m[country %in% names(sel14), .(country, month, procedures)], m[, .(country = "ALL", procedures = sum(procedures)), by = month]); setorder(d, country, month)
d[, base := mean(procedures[year(month) == 2019]), by = country][, `:=`(idx = 100 * procedures / base, idx12 = 100 * frollmean(procedures, 12) / base), by = country]
d[, panel := factor(fifelse(country == "ALL", "All 33 countries", sel14[country]), levels = c("All 33 countries", unname(sel14)))]
last <- d[country == "ALL" & month == max(month)]
p01 <- ggplot(d[country != "ALL"], aes(month)) +
  geom_vline(xintercept = as.IDate(c("2020-03-01", "2022-02-01", "2023-10-01")), colour = "grey72", linetype = "22", linewidth = 0.35) +
  geom_hline(yintercept = 100, colour = "grey45", linewidth = 0.3) + geom_line(aes(y = idx), colour = "grey75", linewidth = 0.3) +
  geom_line(aes(y = idx12), colour = pal_ted[1], linewidth = 1) + facet_wrap(~ panel, ncol = 7) +
  scale_x_date(breaks = as.Date(c("2016-01-01", "2021-01-01", "2026-01-01")), date_labels = "%Y", expand = expansion(mult = 0.02)) +
  labs(title = sprintf("Public buyers launched %.0f%% more calls for tenders in the last twelve months than in 2019", last$idx12 - 100),
       subtitle = "Calls for tenders per month, index 2019 monthly average = 100, to August 2026. Grey: monthly count; line: trailing 12-month average. Dotted: COVID-19, February 2022, eForms.",
       caption = paste(ted_source, "Sept. 2026 dropped (still incomplete).")) + theme_ted() + theme(panel.spacing.x = unit(1.2, "lines"))
save_deck(p01, "01_pulse.png")

# 02 — who wins: contract awards by winner size, 2024 (no diamonds); 02b — who buys: by buyer type, 2024
sz <- q("SELECT country, coalesce(winner_size, 'unknown') AS size, count(*) AS n FROM 'outputs/panel/award_api.parquet' WHERE year(dispatch_date) = 2024 GROUP BY 1, 2")
sz[, `:=`(total = sum(n), known = sum(n[size != "unknown"])), by = country]
keep <- sz[total >= 5000 & known >= 500, unique(country)]
d2 <- sz[country %in% keep & size != "unknown"][, share := n / known]
d2[, size := factor(size, levels = c("micro", "small", "medium", "sme", "large"), labels = c("Micro", "Small", "Medium", "SME (size not specified)", "Large"))]
ord <- d2[size != "Large", .(sme = sum(share)), by = country][order(sme)]
d2[, name := factor(ted_countries[country], levels = ted_countries[ord$country])]
cov <- unique(d2[, .(name, known, total)])[, label := sprintf("declared on %.0f%%", 100 * known / total)]
p02 <- ggplot(d2, aes(share, name, fill = size)) + geom_col(width = 0.72, position = position_stack(reverse = TRUE), key_glyph = "point") +
  geom_text(data = cov, aes(x = 1.02, y = name, label = label), inherit.aes = FALSE, hjust = 0, size = LS - 0.8, colour = "grey45") +
  scale_x_continuous(labels = pct(), breaks = seq(0, 1, 0.25), expand = expansion(mult = c(0, 0.28))) +
  scale_fill_manual(values = c(pal_ted[c(2, 7, 13, 1)], "grey80")) + dots +
  labs(title = sprintf("Who wins: small and medium-sized firms win most public contracts by number — from %.0f%% in %s to %.0f%% in %s", 100 * ord$sme[1], ted_countries[ord$country[1]], 100 * ord$sme[.N], ted_countries[ord$country[.N]]),
       subtitle = "Share of contract awards by declared winner size, 2024, buyer countries with at least 5,000 awarded winners; awards without a declared size excluded (coverage at right).",
       caption = paste(ted_source, "'SME' is the generic eForms code some platforms send.")) + theme_ted() + hgrid
save_deck(p02, "02_winner_size.png")
bt <- q("SELECT country, coalesce(buyer_type, 'unknown') AS bt, count(DISTINCT coalesce(procedure_id, pub_number)) AS n FROM 'outputs/panel/notice_all.parquet'
         WHERE type = 'can' AND year(dispatch_date) = 2024 AND country IS NOT NULL GROUP BY 1, 2")[country %in% keep][, share := n / sum(n), by = country]
btl <- c(`regional-local` = "Regional or local", `public-law-body` = "Public-law body", central = "Central government", utility = "Utility", `eu-international` = "EU / international")
bt[, bt := factor(fifelse(bt %in% names(btl), btl[bt], "Other"), levels = c(unname(btl), "Other"))]
bt <- bt[, .(share = sum(share)), by = .(country, bt)]
ordb <- bt[bt == "Regional or local"][order(share)]
bt[, name := factor(ted_countries[country], levels = ted_countries[ordb$country])]
p02b <- ggplot(bt, aes(share, name, fill = bt)) + geom_col(width = 0.72, position = position_stack(reverse = TRUE), key_glyph = "point") +
  scale_x_continuous(labels = pct(), breaks = seq(0, 1, 0.25), expand = expansion(mult = c(0, 0.02))) +
  scale_fill_manual(values = c(pal_ted[c(1, 2, 7, 6, 8)], "grey80")) + dots +
  labs(title = sprintf("Who buys: regional and local buyers award from %.0f%% of contracts in %s to %.0f%% in %s", 100 * ordb$share[1], ted_countries[ordb$country[1]], 100 * ordb$share[.N], ted_countries[ordb$country[.N]]),
       subtitle = "Share of award procedures by buyer type, 2024, same countries as the winner chart.", caption = ted_source) + theme_ted() + hgrid
save_deck(p02b, "02b_buyer_type.png")

# 03 — public demand by function (6 × 2)
yr <- fread("outputs/quality/cofog_shares_year.csv")
cof <- c(cofog_names, unresolved = "Unresolved (buyer activity unknown)")
d3 <- yr[type == "can" & country %in% sel12 & year <= 2025 & cofog %in% names(cof), .(country, year, cofog, share = share_value)]
d3 <- d3[CJ(country = sel12, year = 2016:2025, cofog = names(cof)), on = .(country, year, cofog)][is.na(share), share := 0]
d3[, `:=`(name = nm(country), fn = factor(cof[cofog], levels = cof))]
tot3 <- yr[type == "can" & year == 2025 & cofog %in% names(cofog_names), .(v = sum(value_eur)), by = cofog][, share := v / sum(v)][order(-share)]
p03 <- ggplot(d3, aes(year, share, fill = fn)) + geom_area(position = position_stack(reverse = TRUE), colour = "white", linewidth = 0.15, key_glyph = "point") +
  facet_wrap(~ name, ncol = 6) + yrs + scale_y_continuous(labels = pct(), expand = expansion(0)) +
  scale_fill_manual(values = c(unname(cofog_colours), "grey85")) + dots + guides(fill = guide_legend(nrow = 2, byrow = TRUE, override.aes = list(shape = 21, size = 5.5, colour = NA))) +
  labs(title = sprintf("Public demand by government function: %s takes %.0f%% of awarded value in 2025, %s %.0f%%", sub("^\\d+ ", "", cof[tot3$cofog[1]]), 100 * tot3$share[1], tolower(sub("^\\d+ ", "", cof[tot3$cofog[2]])), 100 * tot3$share[2]),
       subtitle = "Share of awarded value by COFOG division, award notices, 2016–2025; function from the product bought, or from the buyer's activity for generic products.",
       caption = paste(ted_source, "Values €1,000–<€1bn, one per procedure and value, frameworks excluded. Municipal buyers are coded 'general public services'.")) +
  theme_ted() + theme(panel.grid.major.y = element_blank())
save_deck(p03, "03_cofog_shares.png")

# 04 — Eurostat scatter (12 countries, 6 × 2)
es <- fread("reference/eurostat_gov_10a_exp.csv"); if ("TIME_PERIOD" %in% names(es)) setnames(es, "TIME_PERIOD", "time"); if ("OBS_VALUE" %in% names(es)) setnames(es, "OBS_VALUE", "values")
es <- es[na_item %in% c("P2", "P51G") & cofog99 %in% sprintf("GF%02d", 1:10) & as.character(time) == "2022", .(off = sum(values, na.rm = TRUE)), by = .(geo, cofog = sub("GF", "", cofog99))][, off_share := off / sum(off), by = geo]
es[, country := names(eurostat_geo)[match(geo, eurostat_geo)]]
ted <- yr[type == "can" & year == 2022 & cofog %in% names(cofog_names), .(country, cofog, ted = value_eur)][, ted_share := ted / sum(ted), by = country]
sc <- merge(ted, es[!is.na(country), .(country, cofog, off_share)], by = c("country", "cofog"))[country %in% sel12 & ted_share > 0 & off_share > 0]
r_all <- sc[, cor(log(ted_share), log(off_share))]; rc <- sc[, .(r = round(cor(log(ted_share), log(off_share)), 2)), by = country]
sc[, `:=`(name = nm(country), fn = factor(cofog_names[cofog], levels = cofog_names))]; rc[, name := nm(country)]
p04 <- ggplot(sc, aes(off_share, ted_share, colour = fn)) + geom_abline(slope = 1, intercept = 0, colour = "grey60", linetype = "22") + geom_point(size = 3) +
  geom_text(data = rc, aes(x = 0.006, y = 0.45, label = paste0("r = ", r)), inherit.aes = FALSE, hjust = 0, size = LS - 0.6, colour = "grey35") +
  facet_wrap(~ name, ncol = 6) + scale_x_log10(limits = c(0.005, 0.6), breaks = c(0.01, 0.1), labels = pct()) + scale_y_log10(limits = c(0.005, 0.6), breaks = c(0.01, 0.1), labels = pct()) +
  scale_colour_manual(values = cofog_colours) + guides(colour = guide_legend(nrow = 2, byrow = TRUE, override.aes = list(size = 5))) +
  labs(title = sprintf("The large functions line up with official expenditure; defence, social protection and housing do not (r = %.2f, 2022)", r_all),
       subtitle = "TED share of awarded value by COFOG division (vertical) against Eurostat's share of intermediate consumption plus investment by function (horizontal), 2022, log scales.",
       caption = paste(ted_source, "Eurostat gov_10a_exp: P.2 + P.51G, S.13.")) + theme_ted() + theme(aspect.ratio = 1)
save_deck(p04, "04_cofog_vs_eurostat.png")

# 05 — LLM sensitivity; 05b — human agreement, as measured and with the catch-all resolved (upper bound)
pr <- fread("outputs/quality/llm_pairwise_agreement.csv")
lv <- c("Exact repeat (noise floor)", "Label language", "Prompt wording", "Batch order", "Model size (same family)", "Model family")
pr <- pr[factor %in% lv][, factor := factor(factor, levels = rev(lv))]
p05 <- ggplot(pr, aes(agreement, factor)) + geom_point(colour = pal_ted[1], size = 4, alpha = 0.7) + stat_summary(fun = mean, geom = "point", shape = 124, size = 10, colour = pal_ted[3]) +
  scale_x_continuous(labels = pct(), limits = c(0.75, 1)) +
  labs(title = "How stable is the LLM mapping? The same model twice: 89% of codes; two model families: 84%",
       subtitle = "Agreement on the COFOG division between pairs of the 11 classification runs of 8,215 CPV codes, by the factor that differs between the two runs. Orange bar: mean.",
       caption = "Source: 11 runs (OpenAI and Gemini models, two prompts, English and French labels, shuffled batches, one exact repeat); authors' calculations.") + theme_ted() + hgrid
save_deck(p05, "05_llm_sensitivity.png")
v <- fread("outputs/quality/validation_result.csv", colClasses = "character")[, agree := human_div == machine]
v[, fixed := agree | (machine == "01" & human_div != "01")]
w <- c(unanimous = 0.656, `strong (75-99%)` = 0.186, `majority (50-75%)` = 0.136, `contested (<=50%)` = 0.023)
bb <- melt(v[, .(n = .N, `As measured` = mean(agree), `If the general-services catch-all were resolved (upper bound)` = mean(fixed)), by = band], id.vars = c("band", "n"), variable.name = "what", value.name = "agreement")
bb[, `:=`(band = factor(band, levels = rev(names(w))), weight = w[as.character(band)])]
wt <- bb[, .(w = sum(agreement * weight) / sum(weight)), by = what]
p05b <- ggplot(bb, aes(agreement, band, fill = what)) + geom_col(position = position_dodge(width = 0.75), width = 0.7, key_glyph = "point") +
  geom_text(aes(label = sprintf("%.0f%%", 100 * agreement)), position = position_dodge(width = 0.75), hjust = -0.15, size = LS, colour = "grey30") +
  scale_x_continuous(labels = pct(), limits = c(0, 1.05), expand = expansion(0)) + scale_fill_manual(values = pal_ted[c(1, 2)]) + dots +
  labs(title = sprintf("An economist agrees with the machine on %.0f%% of notices as measured, %.0f%% if the municipal catch-all were resolved", 100 * wt$w[1], 100 * wt$w[2]),
       subtitle = "Agreement on the COFOG division, 170 notices labelled blind, by agreement band of the 11 LLM runs (n: 52, 42, 45, 31). Headline weighted by the bands' shares of notices.",
       caption = "Upper bound: every case where the machine says 'general public services' and the human a specific function is counted as fixable by a text pass.") + theme_ted() + hgrid
save_deck(p05b, "05b_human_agreement.png")

# 06 — double tagging, secondary tags in a different division only
dd <- fread("outputs/quality/double_tagging_year.csv")[cofog %in% names(cofog_names)]
cross <- dd[, sum(value_eur[sec_div != "none" & sec_div != cofog], na.rm = TRUE) / sum(value_eur, na.rm = TRUE)]
dt <- dd[, .(v = sum(value_eur, na.rm = TRUE)), by = .(cofog, sec_div)][, share := v / sum(v), by = cofog][sec_div != "none" & sec_div != cofog]
top <- dt[, .(v = sum(v)), by = sec_div][order(-v)][1:min(5, .N), sec_div]
dt <- dt[, sec_lab := fifelse(sec_div %in% top, cofog_names[sec_div], "Other")][, .(share = sum(share)), by = .(cofog, sec_lab)]
dt[, `:=`(fn = factor(cofog_names[cofog], levels = rev(cofog_names)), sec_lab = factor(sec_lab, levels = c(cofog_names[top], "Other")))]
p06 <- ggplot(dt, aes(share, fn, fill = sec_lab)) + geom_col(width = 0.72, key_glyph = "point") +
  scale_x_continuous(labels = pct(), expand = expansion(mult = c(0, 0.05))) + scale_fill_manual(values = c(unname(cofog_colours[cofog_names[top]]), "grey80")) + dots +
  labs(title = sprintf("One purchase, two purposes: %.0f%% of awarded value serves a second government function", 100 * cross),
       subtitle = "Share of awarded value whose product carries a secondary COFOG tag in another division, by primary division, 2016–2025, 33 countries; colour: the secondary division.",
       caption = paste(ted_source, "Tags: plurality of 11 LLM runs, at least 4 votes; same-division tags (sub-functions) excluded; conditional tags not applied.")) + theme_ted() + hgrid
save_deck(p06, "06_double_tagging.png")

# 07 — green tracker: purpose + co-purpose, one line per country (6 × 2)
g <- dd[, .(green = (sum(procedures[cofog == "05"]) + sum(procedures[green == TRUE & cofog != "05"])) / sum(procedures)), by = .(country, year)]
gt <- dd[year == 2025, (sum(procedures[cofog == "05"]) + sum(procedures[green == TRUE & cofog != "05"])) / sum(procedures)]
g <- g[country %in% sel12 & year <= 2025][, name := nm(country)]
p07 <- ggplot(g, aes(year, green)) + geom_line(colour = pal_ted[4], linewidth = 1.1) + geom_point(colour = pal_ted[4], size = 2) +
  geom_text(data = g[year == 2025], aes(label = sprintf("%.0f%%", 100 * green)), hjust = -0.25, size = LS - 0.6, colour = pal_ted[4], fontface = "bold") +
  facet_wrap(~ name, ncol = 6) + scale_x_continuous(breaks = c(2016, 2020, 2024), expand = expansion(mult = c(0.03, 0.2))) +
  scale_y_continuous(labels = pct(), limits = c(0, NA)) +
  labs(title = sprintf("Green public demand: %.0f%% of award procedures serve environmental protection, as purpose or co-purpose (2025)", 100 * gt),
       subtitle = "Share of award procedures whose primary function is environmental protection or whose product carries it as a secondary tag, by buyer country, 2016–2025.",
       caption = paste(ted_source, "Code-level tags (plurality of 11 LLM runs); conditional tags not applied; buses and landscaping carry the co-purpose unconditionally.")) + theme_ted()
save_deck(p07, "07_green_tracker.png")

# 09 / 10 — multinationals
s1 <- fread("outputs/quality/meip_shares_country.csv"); regions <- c("Domestic parent", "European parent", "US parent", "Asian parent", "Other parent", "Unknown HQ")
s1[, `:=`(name = factor(ted_countries[country], levels = ted_countries[s1[, .(t = sum(share)), by = country][order(t), country]]), region = factor(region, levels = regions))]
p09 <- ggplot(s1, aes(share, name, fill = region)) + geom_col(width = 0.72, key_glyph = "point") +
  scale_x_continuous(labels = pct(), expand = expansion(mult = c(0, 0.05))) + scale_fill_manual(values = c(pal_ted[c(1, 2, 3, 6, 11)], "grey80")) + dots +
  labs(title = "Share of awarded value won by subsidiaries of the world's 500 largest multinationals, by buyer country — a lower bound",
       subtitle = "Awards with a named winner, 2016 – Sept. 2023; notice values split across awards, bounded, frameworks excluded; colour: the parent's headquarters.",
       caption = paste(ted_source, "OECD MEIP; name and register matching (precision ≈ 82% where checkable); incomplete subsidiary lists.")) + theme_ted() + hgrid
save_deck(p09, "09_meip_shares.png")
tp <- fread("outputs/quality/meip_parents.csv")[1:20][, `:=`(parent = factor(parent, levels = rev(parent)), region = factor(region, levels = c("European", "United States", "Other")))]
p10 <- ggplot(tp, aes(v / 1e9, parent, fill = region)) + geom_col(width = 0.72, key_glyph = "point") +
  geom_text(aes(label = sprintf("%s · %s awards", hq, format(awards, big.mark = ","))), hjust = -0.1, size = LS - 0.8, colour = "grey40") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.25))) + scale_fill_manual(values = pal_ted[c(2, 3, 1)]) + dots +
  labs(title = "Who wins the most: the 20 multinationals whose subsidiaries win the largest awarded value, 2016 – Sept. 2023",
       subtitle = "€ billion (notice totals split across awards, bounded, frameworks excluded); label: headquarters and number of awards.",
       caption = paste(ted_source, "Lower bound: matched subsidiaries only.")) + theme_ted() + hgrid
save_deck(p10, "10_meip_parents.png")

# 12 — ICT tracker (OECD mapping, 6 × 2)
ict <- fread("outputs/quality/ict_oecd_year.csv")
i <- ict[country %in% sel12][, share := procedures / sum(procedures), by = .(country, year)][kind != "not ICT"]
i[, `:=`(name = nm(country), kind = factor(kind, levels = c("Software", "Hardware")))]
toti <- ict[year == 2025][, share := procedures / sum(procedures)][kind != "not ICT", sum(share)]
p12 <- ggplot(i, aes(year, share, fill = kind)) + geom_area(colour = "white", linewidth = 0.2, key_glyph = "point") + facet_wrap(~ name, ncol = 6) + yrs +
  scale_y_continuous(labels = pct(), expand = expansion(mult = c(0, 0.05))) + scale_fill_manual(values = pal_ted[c(7, 13)]) + dots +
  labs(title = sprintf("Digital public demand: %.0f%% of award procedures are ICT purchases under the OECD definition (2025)", 100 * toti),
       subtitle = "Share of award procedures whose product falls under the OECD ICT procurement mapping (Annex A), by buyer country, 2016–2025.",
       caption = paste(ted_source, "Product-based: embedded ICT not counted.")) + theme_ted()
save_deck(p12, "12_ict_tracker.png")

# q2 — field coverage, 14 focus countries, 2025
cv <- fread("outputs/quality/coverage_country_year.csv"); wa <- fread("outputs/quality/winners_api_years.csv")
f <- rbind(melt(cv[year == 2025 & country %in% names(sel14), .(type, country, Value = value_raw, `NUTS-2` = nuts2, Activity = activity, `Buyer type` = buyer_type)],
                id.vars = c("type", "country"), variable.name = "field", value.name = "share"),
           wa[year == 2025 & country %in% names(sel14), .(type = "can", country, field = "Winner country", share = winner_country)])
f[, `:=`(name = factor(sel14[country], levels = rev(unname(sel14))), typelab = factor(fifelse(type == "cn", "Calls for tenders", "Award notices"), levels = c("Calls for tenders", "Award notices")))]
pq2 <- ggplot(f, aes(field, name, fill = share)) + geom_tile(colour = "white", linewidth = 0.8) + geom_text(aes(label = round(100 * share)), size = LS - 0.4, colour = "grey15") +
  facet_grid(cols = vars(typelab), scales = "free_x", space = "free_x") + scale_x_discrete(position = "top") +
  scale_fill_gradient2(low = pal_ted[3], mid = "#FBF6EC", high = pal_ted[2], midpoint = 0.5, limits = c(0, 1), guide = "none") +
  labs(title = "Which field can be trusted where: share of 2025 notices with the field filled (%)",
       subtitle = "Value: estimated value on calls, awarded value on awards. Fourteen focus countries; the full table (33 countries, 2022 and 2025) is in the data note.",
       caption = ted_source) + theme_ted() + theme(panel.grid = element_blank())
save_deck(pq2, "q2_field_coverage.png")
cat("deck charts written:", length(list.files("outputs/figures/deck/slides")), "\n")
