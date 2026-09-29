# scripts/22_meip.R — public money and the multinationals: shares by buyer country, the top parents, buyer × HQ, the matching report
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
m <- fread("outputs/meip_matches.csv")
tot <- q("SELECT c.country, count(*) AS awards, sum(least(a.award_value_eur_fin1, 1e8)) AS value_capped
          FROM 'outputs/panel/award.parquet' AS a JOIN 'outputs/panel/notice_can.parquet' AS c ON a.id = c.id
          WHERE a.winner IS NOT NULL AND a.award_value_eur_fin1 > 0 GROUP BY 1")[, iso3 := ted_iso3[country]]
europe <- unname(ted_iso3)
m[, region := fifelse(hq_iso3 == iso3, "Domestic parent", fifelse(hq_iso3 %in% europe, "European parent",
             fifelse(hq_iso3 == "USA", "US parent", fifelse(hq_iso3 %in% c("JPN", "KOR", "CHN", "TWN", "HKG", "IND", "SGP"), "Asian parent", "Other parent"))))]
overall <- m[, sum(value_capped)] / tot[, sum(value_capped)]

# 1 — share of awarded value to top-500 subsidiaries, by buyer country and parent's headquarters
s <- merge(m[, .(v = sum(value_capped)), by = .(iso3, region)], tot[, .(iso3, country, value_capped)], by = "iso3")[, share := v / value_capped]
top20 <- tot[order(-value_capped)][1:20, iso3]
s1 <- s[iso3 %in% top20]
s1[, name := factor(ted_countries[country], levels = ted_countries[s1[, .(t = sum(share)), by = country][order(t), country]])]
s1[, region := factor(region, levels = c("Domestic parent", "European parent", "US parent", "Asian parent", "Other parent"))]
p1 <- ggplot(s1, aes(share, name, fill = region)) + geom_col(width = 0.72) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_manual(values = pal_ted[c(1, 2, 3, 6, 11)]) +
  labs(title = sprintf("%.0f%% of awarded value goes to subsidiaries of the world's 500 largest multinationals — a lower bound", 100 * overall),
       subtitle = paste("Share of awarded value won by subsidiaries of the 500 largest multinationals (OECD MEIP), by buyer country and the parent's headquarters;",
                        "awards with a named winner, 2016 – Sept. 2023, values capped at €100M per award."),
       caption = paste(ted_source, "Name and register matching (precision ≈ 82% where registration numbers can be checked); incomplete subsidiary lists — every share is a lower bound.")) +
  theme_ted(base_size = 14) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(p1, "09_meip_shares.png")

# 2 — the 25 parents whose subsidiaries win the most
tp <- m[, .(v = sum(value_capped), awards = sum(awards), hq = hq_iso3[1]), by = parent][order(-v)][1:25]
tp[, `:=`(parent = factor(parent, levels = rev(parent)),
          region = factor(fifelse(hq %in% europe, "European", fifelse(hq == "USA", "United States", "Other")), levels = c("European", "United States", "Other")))]
p2 <- ggplot(tp, aes(v / 1e9, parent, fill = region)) + geom_col(width = 0.72) +
  geom_text(aes(label = hq), hjust = -0.2, size = 3, colour = "grey40") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.12))) + scale_fill_manual(values = pal_ted[c(2, 3, 1)]) +
  labs(title = "Who wins the most: the 25 multinationals whose subsidiaries win the largest awarded value, 2016 – Sept. 2023",
       subtitle = "Awarded value (€ billion, capped at €100M per award) of TED awards won by matched subsidiaries of each parent; label: parent's headquarters.",
       caption = paste(ted_source, "Lower bound: matched subsidiaries only; consortia and joint ventures blur attribution.")) +
  theme_ted(base_size = 13) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(p2, "10_meip_parents.png")

# 3 — buyer country × parent headquarters (share of the buyer country's awarded value)
hm <- merge(m[, .(v = sum(value_capped)), by = .(iso3, hq_iso3)], tot[, .(iso3, country, value_capped)], by = "iso3")[, share := v / value_capped]
tophq <- hm[, .(v = sum(v)), by = hq_iso3][order(-v)][1:10, hq_iso3]
hm <- hm[iso3 %in% top20 & hq_iso3 %in% tophq]
hm[, `:=`(name = factor(ted_countries[country], levels = levels(s1$name)), hq = factor(hq_iso3, levels = tophq))]
p3 <- ggplot(hm, aes(hq, name, fill = share)) + geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = sprintf("%.1f", 100 * share)), size = 2.8, colour = "grey15") +
  scale_fill_gradient(low = "#EEF0F5", high = pal_ted[2], guide = "none") + scale_x_discrete(position = "top") +
  labs(title = "Who buys from whom: share of each buyer country's awarded value won by subsidiaries of multinationals headquartered in…",
       subtitle = "Percent of awarded value (capped), buyer country (rows) by parent headquarters (columns, the ten largest), 2016 – Sept. 2023.",
       caption = paste(ted_source, "Top-500 multinationals only (OECD MEIP); lower bound.")) +
  theme_ted(base_size = 13) + theme(panel.grid = element_blank())
save_fig(p3, "11_meip_heatmap.png")
rep <- m[, .(winner_names = .N, awards = sum(awards), value_bn = round(sum(value_capped) / 1e9, 1), min_similarity = round(min(sim), 3)), by = how]
fwrite(rep, "outputs/quality/meip_matching_report.csv"); print(rep); print(s[, .(share = round(sum(v) / sum(value_capped), 3)), by = region])
