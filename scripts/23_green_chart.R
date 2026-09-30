# scripts/23_green_chart.R — the green share of award procedures, twelve countries on one panel, labelled at the last point
source("R/packages.R"); source("R/theme.R")
d <- fread("outputs/quality/double_tagging_year.csv")
sel12 <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT")
g <- d[country %in% sel12 & year <= 2025, .(green = sum(procedures[green == TRUE]) / sum(procedures)), by = .(country, year)]
overall <- d[year == 2025, sum(procedures[green == TRUE]) / sum(procedures)]
last <- g[year == 2025][order(green)]
gap <- 0.0011                                        # minimum vertical distance between end labels
last[, y_lab := green]; for (i in seq_len(nrow(last))[-1]) last[i, y_lab := max(green, last$y_lab[i - 1] + gap)]
last[, lab := sprintf("%s  %.1f%%", ted_countries[country], 100 * green)]
g[, country := factor(country, levels = last$country)]; last[, country := factor(country, levels = levels(g$country))]
shades <- colorRampPalette(c("#C9E3B4", "#6DB33F", "#3A8415", "#173D0C"))(nrow(last))
p <- ggplot(g, aes(year, green, colour = country, group = country)) +
  geom_line(linewidth = 1.1) + geom_point(size = 1.9) +
  geom_segment(data = last, aes(x = 2025.08, xend = 2025.42, y = green, yend = y_lab), colour = "grey70", linewidth = 0.3, inherit.aes = FALSE) +
  geom_text(data = last, aes(x = 2025.5, y = y_lab, label = lab, colour = country), hjust = 0, size = 4.2, fontface = "bold", inherit.aes = FALSE) +
  scale_colour_manual(values = shades, guide = "none") +
  scale_x_continuous(breaks = 2016:2025, limits = c(2016, 2027.4), expand = expansion(0)) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 0.1), limits = c(0, NA), expand = expansion(mult = c(0, 0.05))) +
  labs(title = sprintf("The green share of public demand: %.1f%% of award procedures carry an environmental co-purpose in 2025 — rising in Italy, Czechia and Portugal, flat in Germany", 100 * overall),
       subtitle = "Share of award procedures whose product code carries a secondary COFOG tag in environmental protection (05), by buyer country, 2016–2025; label: 2025 value.
What carries the tag differs: solar panels in Czechia and Poland, bus fleets in Italy, electric vehicles in Spain, energy-efficiency consultancy in the Netherlands, landscaping in Germany, France and Austria.",
       caption = paste(ted_source, "Code-level tags only (plurality of 11 LLM runs, at least 4 votes); conditional tags (electric, solar, energy-efficient) not applied; buses and landscaping carry the tag unconditionally.")) +
  theme_ted(base_size = 15)
save_fig(p, "07_green_share_lines.png")
