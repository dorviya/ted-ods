# scripts/16_cofog_panel.R — the functional panel: a COFOG division per procedure (product code → COFOG consensus of
# 11 LLM runs; buyer-dependent codes resolved from the buyer's activity), monthly by type × country; one chart.
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))

panel <- q("
  WITH map AS (SELECT cpv, consensus, band FROM read_csv('reference/cpv_cofog_consensus.csv', all_varchar = true)),
  n AS (
    SELECT a.type, coalesce(a.procedure_id, a.pub_number) AS proc, a.country, a.dispatch_date, m.band,
           CASE WHEN a.value_eur BETWEEN 1e3 AND 1e9 AND NOT coalesce(a.framework, false) THEN a.value_eur END AS v,
           CASE WHEN m.consensus IS NULL THEN 'unmapped' WHEN m.consensus <> 'BD' THEN 'product' ELSE 'buyer' END AS cofog_source,
           CASE WHEN m.consensus IS NULL THEN 'unmapped' WHEN m.consensus <> 'BD' THEN m.consensus
                ELSE CASE a.activity
                     WHEN 'gen-pub' THEN '01' WHEN 'defence' THEN '02' WHEN 'pub-os' THEN '03' WHEN 'econ-aff' THEN '04'
                     WHEN 'env-pro' THEN '05' WHEN 'hc-am' THEN '06' WHEN 'health' THEN '07' WHEN 'rcr' THEN '08'
                     WHEN 'education' THEN '09' WHEN 'soc-pro' THEN '10' WHEN 'water' THEN '06'
                     WHEN 'electricity' THEN '04' WHEN 'gas-heat' THEN '04' WHEN 'gas-oil' THEN '04' WHEN 'solid-fuel' THEN '04'
                     WHEN 'extraction' THEN '04' WHEN 'rail' THEN '04' WHEN 'urttb' THEN '04' WHEN 'airport' THEN '04'
                     WHEN 'port' THEN '04' WHEN 'post' THEN '04' ELSE 'unresolved' END END AS cofog
    FROM 'outputs/panel/notice_all.parquet' AS a LEFT JOIN map AS m ON a.cpv = m.cpv
    WHERE a.dispatch_date >= '2016-01-01' AND a.country IS NOT NULL),
  p AS (
    SELECT type, proc, any_value(country) AS country, min(dispatch_date) AS first_date,
           arg_min(cofog, dispatch_date) AS cofog, arg_min(cofog_source, dispatch_date) AS cofog_source,
           arg_min(band, dispatch_date) AS band, sum(DISTINCT v) AS value_eur
    FROM n GROUP BY 1, 2)
  SELECT type, country, date_trunc('month', first_date)::date AS ym, cofog, cofog_source,
         count(*) AS procedures, count(value_eur) AS procedures_with_value, round(sum(value_eur)) AS value_eur,
         count(*) FILTER (WHERE band = 'contested (<=50%)') AS procedures_contested
  FROM p GROUP BY 1, 2, 3, 4, 5 ORDER BY 1, 2, 3, 4, 5")
setnames(panel, "ym", "month")
fwrite(panel, "outputs/panel/cofog_monthly.csv")
yr <- panel[, .(procedures = sum(procedures), value_eur = sum(value_eur, na.rm = TRUE)), by = .(type, country, year = year(month), cofog)]
yr[, `:=`(share_procedures = procedures / sum(procedures), share_value = value_eur / sum(value_eur)), by = .(type, country, year)]
fwrite(yr, "outputs/quality/cofog_shares_year.csv")
print(panel[, .(procedures = sum(procedures)), by = cofog_source][, share := round(procedures / sum(procedures), 3)][])
print(dcast(yr[type == "can" & year == 2025 & country %in% c("DE", "FR", "IT", "ES", "PL", "NL", "SE")][, s := round(100 * share_value)],
            cofog ~ country, value.var = "s"))

# Story 3 — the functional structure of awarded value, 12 countries, 2016–2025
cof <- c("01" = "01 General public services", "02" = "02 Defence", "03" = "03 Public order & safety",
         "04" = "04 Economic affairs", "05" = "05 Environmental protection", "06" = "06 Housing & community amenities",
         "07" = "07 Health", "08" = "08 Recreation, culture & religion", "09" = "09 Education",
         "10" = "10 Social protection", unresolved = "Unresolved (buyer activity unknown)")
sel3 <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT")
d3 <- yr[type == "can" & country %in% sel3 & year <= 2025 & cofog %in% names(cof), .(country, year, cofog, share = share_value)]
d3 <- d3[CJ(country = sel3, year = 2016:2025, cofog = names(cof)), on = .(country, year, cofog)][is.na(share), share := 0]
d3[, `:=`(name = factor(ted_countries[country], levels = ted_countries[sel3]), fn = factor(cof[cofog], levels = cof))]
tot <- yr[type == "can" & year == 2025 & cofog %in% names(cof), .(v = sum(value_eur)), by = cofog][, share := v / sum(v)][order(-share)]
p3 <- ggplot(d3, aes(year, share, fill = fn)) +
  geom_area(position = position_stack(reverse = TRUE), colour = "white", linewidth = 0.15) +
  facet_wrap(~ name, ncol = 4) +
  scale_x_continuous(breaks = c(2016, 2019, 2022, 2025), labels = function(x) paste0("'", substr(x, 3, 4)), expand = expansion(0)) +
  scale_y_continuous(labels = scales::label_percent(), expand = expansion(0)) +
  scale_fill_manual(values = c(pal_ted[c(1, 11, 9, 7, 4, 14, 2, 8, 6, 3)], "grey85")) +
  guides(fill = guide_legend(nrow = 2, byrow = TRUE)) +
  labs(title = sprintf("Public demand by government function, country by country\n%s takes %.0f%% of awarded value across 33 countries in 2025, %s %.0f%%",
                       sub("^\\d+ ", "", cof[tot$cofog[1]]), 100 * tot$share[1], tolower(sub("^\\d+ ", "", cof[tot$cofog[2]])), 100 * tot$share[2]),
       subtitle = paste("Share of awarded value by COFOG division, contract award notices, 2016–2025.
Function from the product bought",
                        "(CPV code → COFOG, consensus of 11 LLM runs); for generic products (office supplies, IT, cleaning…) from the buyer's activity."),
       caption = paste0(ted_source, "\nValues €1,000–€1 billion, one per procedure and value, framework agreements excluded. ",
                        "Municipal buyers are coded 'general public services'; 'unresolved' = generic product and buyer activity unknown.")) +
  theme_ted() + theme(panel.grid.major.y = element_blank(), legend.text = element_text(size = 10.5), panel.spacing.x = unit(1.8, "lines"))
save_fig(p3, "03_cofog_shares.png")
