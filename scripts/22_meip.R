# scripts/22_meip.R — public money and the multinationals: shares by buyer country, the top parents, buyer × HQ, the matching report.
# Values: the notice's cleaned total (FIN_1) split equally across its awards, bounded €1,000 – <€1bn, frameworks excluded —
# award-level CSV values repeat the notice total across lots and must not be summed.
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
aw <- q("SELECT a.winner, c.country, count(*) AS awards,
                sum(CASE WHEN c.value_eur_fin1 BETWEEN 1e3 AND 999999999 AND NOT coalesce(c.framework, false)
                         THEN c.value_eur_fin1 / greatest(c.awards, 1) END) AS value_eur
         FROM 'outputs/panel/award.parquet' AS a JOIN 'outputs/panel/notice_can.parquet' AS c ON a.id = c.id
         WHERE a.winner IS NOT NULL GROUP BY 1, 2")
tot <- aw[, .(awards = sum(awards), value_eur = sum(value_eur, na.rm = TRUE)), by = country][, iso3 := ted_iso3[country]]
m0 <- fread("outputs/meip_matches.csv")[order(match(how, c("exact", "id", "fuzzy")), -sim)][!duplicated(paste(winner, iso3))]
hqfix <- c("Compagnie de Saint Gobain SA" = "FRA", "GSK plc" = "GBR", "Compass Group PLC" = "GBR", "GE Vernova Inc" = "USA", "Canon Inc" = "JPN", "AbbVie Inc" = "USA")
m0[is.na(hq_iso3) | hq_iso3 == "", hq_iso3 := hqfix[parent]]
m0[, country := names(ted_iso3)[match(iso3, ted_iso3)]]
m <- merge(m0[, .(winner, country, iso3, parent, sub_name, how, sim, hq_iso3)], aw, by = c("winner", "country"))
cat(sprintf("matched winner names: %d in file, %d joined to awards\n", nrow(m0), nrow(m)))
europe <- unname(ted_iso3)
m[, region := fifelse(is.na(hq_iso3), "Unknown HQ", fifelse(hq_iso3 == iso3, "Domestic parent", fifelse(hq_iso3 %in% europe, "European parent",
             fifelse(hq_iso3 == "USA", "US parent", fifelse(hq_iso3 %in% c("JPN", "KOR", "CHN", "TWN", "HKG", "IND", "SGP"), "Asian parent", "Other parent")))))]
overall_v <- m[, sum(value_eur, na.rm = TRUE)] / tot[, sum(value_eur)]; overall_n <- m[, sum(awards)] / tot[, sum(awards)]
regions <- c("Domestic parent", "European parent", "US parent", "Asian parent", "Other parent", "Unknown HQ")

# 1 — share of awarded value to top-500 subsidiaries, by buyer country and parent's headquarters
s <- merge(m[, .(v = sum(value_eur, na.rm = TRUE), n = sum(awards)), by = .(iso3, region)], tot[, .(iso3, country, value_eur, awards)], by = "iso3")
s[, `:=`(share = v / value_eur, share_n = n / awards)]
top20 <- tot[order(-value_eur)][1:20, iso3]
s1 <- s[iso3 %in% top20]
s1[, name := factor(ted_countries[country], levels = ted_countries[s1[, .(t = sum(share)), by = country][order(t), country]])]
s1[, region := factor(region, levels = regions)]
p1 <- ggplot(s1, aes(share, name, fill = region)) + geom_col(width = 0.72) +
  scale_x_continuous(labels = scales::label_percent(accuracy = 1), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_manual(values = c(pal_ted[c(1, 2, 3, 6, 11)], "grey80")) +
  labs(title = sprintf("%.0f%% of awarded value (%.0f%% of awards) goes to subsidiaries of the world's 500 largest multinationals — a lower bound", 100 * overall_v, 100 * overall_n),
       subtitle = paste("Share of awarded value won by subsidiaries of the 500 largest multinationals (OECD MEIP), by buyer country and the parent's headquarters;",
                        "awards with a named winner, 2016 – Sept. 2023; notice values split across awards, bounded, frameworks excluded."),
       caption = paste(ted_source, "Name and register matching (precision ≈ 82% where registration numbers can be checked); incomplete subsidiary lists — every share is a lower bound.")) +
  theme_ted(base_size = 14) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(p1, "09_meip_shares.png"); fwrite(s1, "outputs/quality/meip_shares_country.csv")

# 2 — the 25 parents whose subsidiaries win the most
tp <- m[, .(v = sum(value_eur, na.rm = TRUE), awards = sum(awards), hq = hq_iso3[1]), by = parent][order(-v)][1:25]
tp[, `:=`(parent = factor(parent, levels = rev(parent)), hq = fifelse(is.na(hq), "?", hq),
          region = factor(fifelse(hq %in% europe, "European", fifelse(hq == "USA", "United States", "Other")), levels = c("European", "United States", "Other")))]
p2 <- ggplot(tp, aes(v / 1e9, parent, fill = region)) + geom_col(width = 0.72) +
  geom_text(aes(label = sprintf("%s · %s awards", hq, format(awards, big.mark = ","))), hjust = -0.1, size = 3, colour = "grey40") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.2))) + scale_fill_manual(values = pal_ted[c(2, 3, 1)]) +
  labs(title = "Who wins the most: the 25 multinationals whose subsidiaries win the largest awarded value, 2016 – Sept. 2023",
       subtitle = "Awarded value (€ billion; notice totals split across awards, bounded, frameworks excluded) won by matched subsidiaries; label: headquarters and number of awards.",
       caption = paste(ted_source, "Lower bound: matched subsidiaries only; consortia and joint ventures blur attribution.")) +
  theme_ted(base_size = 13) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(p2, "10_meip_parents.png"); fwrite(tp, "outputs/quality/meip_parents.csv")

# 3 — buyer country × parent headquarters
hm <- merge(m[!is.na(hq_iso3), .(v = sum(value_eur, na.rm = TRUE)), by = .(iso3, hq_iso3)], tot[, .(iso3, country, value_eur)], by = "iso3")[, share := v / value_eur]
tophq <- hm[, .(v = sum(v)), by = hq_iso3][order(-v)][1:10, hq_iso3]
hm <- hm[iso3 %in% top20 & hq_iso3 %in% tophq]
hm[, `:=`(name = factor(ted_countries[country], levels = levels(s1$name)), hq = factor(hq_iso3, levels = tophq))]
p3 <- ggplot(hm, aes(hq, name, fill = share)) + geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = sprintf("%.1f", 100 * share)), size = 2.8, colour = "grey15") +
  scale_fill_gradient(low = "#EEF0F5", high = pal_ted[2], guide = "none") + scale_x_discrete(position = "top") +
  labs(title = "Who buys from whom: share of each buyer country's awarded value won by subsidiaries of multinationals headquartered in…",
       subtitle = "Percent of awarded value, buyer country (rows) by parent headquarters (columns, the ten largest), 2016 – Sept. 2023.",
       caption = paste(ted_source, "Top-500 multinationals only (OECD MEIP); lower bound.")) +
  theme_ted(base_size = 13) + theme(panel.grid = element_blank())
save_fig(p3, "11_meip_heatmap.png")
rep <- m[, .(winner_names = .N, awards = sum(awards), value_bn = round(sum(value_eur, na.rm = TRUE) / 1e9, 1), min_similarity = round(min(sim), 3)), by = how]
fwrite(rep, "outputs/quality/meip_matching_report.csv"); print(rep)
print(s[, .(share_value = round(sum(v) / sum(value_eur), 3), share_awards = round(sum(n) / sum(awards), 3)), by = region])
print(s1[, .(share_value = round(sum(share), 3), share_awards = round(sum(share_n), 3)), by = country][order(-share_value)][1:8])
print(tp[1:8, .(parent, value_bn = round(v / 1e9, 1), awards, hq)])
