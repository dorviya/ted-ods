# scripts/26_ict_chart.R — digital public demand with the OECD ICT procurement mapping (Annex A: 97 CPV nodes, Hardware / Software), matched by prefix
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
ict <- q("
  WITH s AS (SELECT category, stem FROM read_csv('reference/ict_cpv_oecd.csv', all_varchar = true)),
  p AS (SELECT coalesce(procedure_id, pub_number) AS proc, any_value(country) AS country, year(min(dispatch_date)) AS year, arg_min(cpv, dispatch_date) AS cpv
        FROM 'outputs/panel/notice_all.parquet' WHERE type = 'can' AND dispatch_date BETWEEN '2016-01-01' AND '2025-12-31' AND country IS NOT NULL GROUP BY 1),
  m AS (SELECT p.proc, p.country, p.year, s.category, s.stem FROM p LEFT JOIN s ON p.cpv LIKE s.stem || '%'
        QUALIFY row_number() OVER (PARTITION BY p.proc ORDER BY length(s.stem) DESC NULLS LAST) = 1)
  SELECT country, year, coalesce(category, 'not ICT') AS kind, count(*) AS procedures FROM m GROUP BY 1, 2, 3")
fwrite(ict, "outputs/quality/ict_oecd_year.csv")
sel12 <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT")
i <- ict[country %in% sel12][, share := procedures / sum(procedures), by = .(country, year)][kind != "not ICT"]
i[, `:=`(name = factor(ted_countries[country], levels = ted_countries[sel12]), kind = factor(kind, levels = c("Software", "Hardware")))]
tot <- ict[year == 2025][, share := procedures / sum(procedures)][kind != "not ICT", sum(share)]
p <- ggplot(i, aes(year, share, fill = kind)) + geom_area(colour = "white", linewidth = 0.2) +
  facet_wrap(~ name, ncol = 4) +
  scale_x_continuous(breaks = c(2016, 2019, 2022, 2025), labels = function(x) paste0("'", substr(x, 3, 4))) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_manual(values = pal_ted[c(7, 13)]) +
  labs(title = sprintf("Digital public demand: %.0f%% of award procedures are ICT purchases under the OECD definition (2025)", 100 * tot),
       subtitle = "Share of award procedures whose product falls under the OECD ICT procurement mapping (Annex A: 97 CPV nodes — hardware: computer, network and telecom equipment; software: networks, software packages, telecom and IT services), by buyer country, 2016–2025.",
       caption = paste(ted_source, "Product-based: ICT embedded in other purchases is not counted. Mapping: OECD ICT Procurement CPV Annex A.")) +
  theme_ted(base_size = 13) + theme(panel.spacing.x = unit(1.6, "lines"))
save_fig(p, "12_ict_tracker.png")
print(ict[year == 2025, .(procedures = sum(procedures)), by = kind][, share := round(procedures / sum(procedures), 3)][])
