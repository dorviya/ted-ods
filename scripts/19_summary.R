# scripts/19_summary.R — one figure introducing the data: calls per year, what is bought, who buys, how, and values
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
base <- "WITH p AS (
  SELECT type, coalesce(procedure_id, pub_number) AS proc, min(dispatch_date) AS d,
         arg_min(contract_type, dispatch_date) AS contract_type, arg_min(buyer_type, dispatch_date) AS buyer_type,
         arg_min(activity, dispatch_date) AS activity, arg_min(cpv_div, dispatch_date) AS cpv_div, arg_min(procedure, dispatch_date) AS procedure,
         sum(DISTINCT CASE WHEN value_eur BETWEEN 1e3 AND 1e9 AND NOT coalesce(framework, false) THEN value_eur END) AS value_eur
  FROM 'outputs/panel/notice_all.parquet'
  WHERE dispatch_date BETWEEN '2016-01-01' AND '2025-12-31' AND country IS NOT NULL GROUP BY 1, 2)"
dim <- function(panel, expr, where = "type = 'cn'")
  q(sprintf("%s SELECT '%s' AS panel, coalesce(%s, 'unknown') AS category, count(*) AS n FROM p WHERE %s GROUP BY 1, 2", base, panel, expr, where))
s <- rbind(dim("Calls per year", "year(d)::varchar"), dim("Contract type", "contract_type"), dim("Buyer type", "buyer_type"),
           dim("Buyer activity", "activity"), dim("Product division (CPV)", "cpv_div"), dim("Procedure", "procedure"),
           dim("Awarded value (awards)", "floor(log10(value_eur))::int::varchar", "type = 'can' AND value_eur IS NOT NULL"))
lab <- list(
  "Contract type" = c(U = "Supplies", S = "Services", W = "Works"),
  "Buyer type" = c(central = "Central government", `regional-local` = "Regional or local", `public-law-body` = "Body governed by public law",
                   utility = "Utility", `eu-international` = "EU or international", other = "Other"),
  "Buyer activity" = c(`gen-pub` = "General public services", health = "Health", education = "Education", `hc-am` = "Housing & amenities",
                       `env-pro` = "Environment", `econ-aff` = "Economic affairs", defence = "Defence", `pub-os` = "Public order",
                       `soc-pro` = "Social protection", rcr = "Recreation & culture", electricity = "Electricity", rail = "Rail",
                       urttb = "Urban transport", water = "Water", other = "Other"),
  "Product division (CPV)" = c(`45` = "45 Construction work", `33` = "33 Medical equipment & pharmaceuticals", `72` = "72 IT services",
                               `90` = "90 Sewage, refuse, environment", `71` = "71 Architecture & engineering", `79` = "79 Business services",
                               `34` = "34 Transport equipment", `50` = "50 Repair & maintenance", `80` = "80 Education & training",
                               `09` = "09 Fuels & electricity", `30` = "30 Office & computing machinery", `39` = "39 Furniture", `15` = "15 Food",
                               `60` = "60 Transport services", `85` = "85 Health & social services", `38` = "38 Laboratory equipment",
                               `48` = "48 Software", `44` = "44 Construction materials", `66` = "66 Financial services", `42` = "42 Industrial machinery"),
  "Procedure" = c(open = "Open", restricted = "Restricted", `neg-w-call` = "Negotiated with call", `neg-wo-call` = "Negotiated without call",
                  `comp-dial` = "Competitive dialogue", innovation = "Innovation partnership", other = "Other"))
for (p in names(lab)) s[panel == p, category := fifelse(category %in% names(lab[[p]]), lab[[p]][category], "Other")]
vbins <- c("3" = "€1k–10k", "4" = "€10k–100k", "5" = "€100k–1M", "6" = "€1M–10M", "7" = "€10M–100M", "8" = "€100M–1bn")
s[panel == "Awarded value (awards)", category := vbins[category]]
s <- s[!is.na(category), .(n = sum(n)), by = .(panel, category)][, share := n / sum(n), by = panel]
s[panel %in% c("Buyer activity", "Product division (CPV)"), rank := frank(-share, ties.method = "first"), by = panel]
s[!is.na(rank) & rank > 9 & category != "Other", category := "Other"]
s <- s[, .(n = sum(n), share = sum(share)), by = .(panel, category)]
s[, ord := -share]; s[category %in% c("Other", "unknown"), ord := 1]
s[panel == "Calls per year", ord := -as.numeric(category)]
s[panel == "Awarded value (awards)", ord := -match(category, vbins)]
setorder(s, panel, ord)
s[, id := factor(paste0(panel, "|", category), levels = rev(paste0(panel, "|", category)))]
s[, panel := factor(panel, levels = c("Calls per year", "Contract type", "Buyer type", "Buyer activity",
                                      "Product division (CPV)", "Procedure", "Awarded value (awards)"))]
tot_calls <- s[panel == "Calls per year", sum(n)]
p0 <- ggplot(s, aes(share, id)) +
  geom_col(fill = pal_ted[1], width = 0.75) +
  geom_text(aes(label = sprintf("%.0f%%", 100 * share)), hjust = -0.15, size = 2.8, colour = "grey30") +
  facet_wrap(~ panel, scales = "free", ncol = 4) +
  scale_y_discrete(labels = function(x) sub("^[^|]*\\|", "", x)) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.3)), labels = NULL) +
  labs(title = sprintf("%.1f million calls for tenders in ten years: what public buyers announce, who they are, how they buy", tot_calls / 1e6),
       subtitle = "Shares of procedures (calls for tenders, 2016–2025, 33 countries); awarded values from award notices, one value per procedure, framework agreements excluded.",
       caption = ted_source) +
  theme_ted(base_size = 13) + theme(panel.grid = element_blank(), axis.text.y = element_text(size = 9))
save_fig(p0, "00_summary.png")
print(s[panel %in% c("Contract type", "Buyer type"), .(panel, category, share = round(share, 3))])
