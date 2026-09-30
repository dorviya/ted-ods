# scripts/26_ict_chart.R — digital public demand: award procedures whose main product is ICT, by kind, buyer country and year
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
ict <- q("
  WITH p AS (SELECT coalesce(procedure_id, pub_number) AS proc, any_value(country) AS country, year(min(dispatch_date)) AS year, arg_min(cpv, dispatch_date) AS cpv
             FROM 'outputs/panel/notice_all.parquet'
             WHERE type = 'can' AND dispatch_date BETWEEN '2016-01-01' AND '2025-12-31' AND country IS NOT NULL GROUP BY 1)
  SELECT country, year,
         CASE WHEN cpv LIKE '48%' THEN 'Software' WHEN cpv LIKE '72%' THEN 'IT services'
              WHEN cpv LIKE '302%' OR cpv LIKE '32%' OR cpv LIKE '642%' THEN 'Computers, networks, telecoms' ELSE 'not ICT' END AS kind,
         count(*) AS procedures FROM p GROUP BY 1, 2, 3")
fwrite(ict, "outputs/quality/ict_year.csv")
sel12 <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT")
i <- ict[country %in% sel12][, share := procedures / sum(procedures), by = .(country, year)][kind != "not ICT"]
i[, `:=`(name = factor(ted_countries[country], levels = ted_countries[sel12]), kind = factor(kind, levels = c("IT services", "Software", "Computers, networks, telecoms")))]
tot <- ict[year == 2025][, share := procedures / sum(procedures)][kind != "not ICT", sum(share)]
p <- ggplot(i, aes(year, share, fill = kind)) + geom_area(colour = "white", linewidth = 0.2) +
  facet_wrap(~ name, ncol = 4) +
  scale_x_continuous(breaks = c(2016, 2019, 2022, 2025), labels = function(x) paste0("'", substr(x, 3, 4))) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_manual(values = pal_ted[c(2, 7, 13)]) +
  labs(title = sprintf("Digital public demand: %.0f%% of award procedures buy ICT — computers and networks, software, IT services (2025)", 100 * tot),
       subtitle = "Share of award procedures whose main product is ICT (CPV 302 computer equipment, 32 communications equipment, 48 software, 72 IT services, 642 telecom services), by buyer country, 2016–2025.",
       caption = paste(ted_source, "Product-based: ICT embedded in other purchases (an information system inside a hospital works contract) is not counted.")) +
  theme_ted(base_size = 13) + theme(panel.spacing.x = unit(1.6, "lines"))
save_fig(p, "12_ict_tracker.png")
