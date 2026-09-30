# scripts/23_green_chart.R — green public demand: award procedures whose primary function is environmental protection, stacked with those carrying it as a co-purpose
source("R/packages.R"); source("R/theme.R")
d <- fread("outputs/quality/double_tagging_year.csv")
sel12 <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT")
g <- d[country %in% sel12 & year <= 2025, .(`Primary purpose: environmental protection (05)` = sum(procedures[cofog == "05"]) / sum(procedures),
                                              `Co-purpose: secondary tag 05 on another function` = sum(procedures[green == TRUE & cofog != "05"]) / sum(procedures)),
       by = .(country, year)]
gl <- melt(g, id.vars = c("country", "year"), variable.name = "layer", value.name = "share")
gl[, `:=`(name = factor(ted_countries[country], levels = ted_countries[sel12]), layer = factor(layer, levels = rev(levels(layer))))]
tot <- d[year == 2025, .(prim = sum(procedures[cofog == "05"]) / sum(procedures), sec = sum(procedures[green == TRUE & cofog != "05"]) / sum(procedures))]
p <- ggplot(gl, aes(year, share, fill = layer)) + geom_area(colour = "white", linewidth = 0.2) +
  facet_wrap(~ name, ncol = 4) +
  scale_x_continuous(breaks = c(2016, 2019, 2022, 2025), labels = function(x) paste0("'", substr(x, 3, 4))) +
  scale_y_continuous(labels = scales::label_percent(accuracy = 1), expand = expansion(mult = c(0, 0.05))) +
  scale_fill_manual(values = c(pal_ted[10], pal_ted[4])) +
  labs(title = sprintf("Green public demand: %.0f%% of award procedures have environmental protection as their purpose, %.1f%% more as a co-purpose (2025)", 100 * tot$prim, 100 * tot$sec),
       subtitle = paste("Share of award procedures by buyer country, 2016–2025: primary function environmental protection (waste, sewage, remediation, environmental services),",
                        "stacked with a secondary tag 05 on another primary function (solar panels, bus fleets, landscaping, water networks…)."),
       caption = paste(ted_source, "Functions from the CPV→COFOG consensus of 11 LLM runs (secondary: plurality, at least 4 votes); conditional tags not applied.")) +
  theme_ted(base_size = 13) + theme(panel.spacing.x = unit(1.6, "lines"))
save_fig(p, "07_green_tracker.png")
