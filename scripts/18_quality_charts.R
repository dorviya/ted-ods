# scripts/18_quality_charts.R — the data-quality slides, from outputs/quality/ (script 13)
source("R/packages.R"); source("R/theme.R")
cov <- fread("outputs/quality/coverage_country_year.csv"); win <- fread("outputs/quality/winners_csv_years.csv")
wapi <- fread("outputs/quality/winners_api_years.csv"); lag <- fread("outputs/quality/call_to_award_lag.csv")
pub <- fread("outputs/quality/publication_lag.csv")

# Q1 — coverage heatmap: calls (procedures) per country and year
h <- cov[type == "cn", .(procedures = sum(procedures)), by = .(country, year)]
lev <- ted_countries[h[, sum(procedures), by = country][order(V1), country]]
h[, name := factor(ted_countries[country], levels = lev)]
h[, lab := fifelse(procedures >= 1e4, sprintf("%.0fk", procedures / 1e3),
                   fifelse(procedures >= 1e3, sprintf("%.1fk", procedures / 1e3), as.character(procedures)))]
tot <- h[year <= 2025, sum(procedures)] / 1e6
pq1 <- ggplot(h, aes(factor(year), name, fill = procedures)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = lab, colour = procedures > 6000), size = 2.8) +
  scale_fill_gradient(low = "#EEF0F5", high = pal_ted[1], trans = "log10", guide = "none") +
  scale_colour_manual(values = c(`FALSE` = "grey25", `TRUE` = "white"), guide = "none") +
  scale_x_discrete(labels = function(x) fifelse(x == "2026", "2026*", x), position = "top") +
  labs(title = sprintf("%.1f million calls for tenders from 33 countries in ten years: every country, every year, up to last month", tot),
       subtitle = paste("Calls for tenders (procedures) by buyer country and dispatch year. 2016 – Sept. 2023 from the CSV export, since Oct. 2023 from the API;",
                        "*2026 to August. The United Kingdom stops publishing in 2021."),
       caption = ted_source) +
  theme_ted(base_size = 13) + theme(panel.grid = element_blank(), axis.text.y = element_text(size = 9))
save_fig(pq1, "q1_coverage_heatmap.png")

# Q2 — field coverage by country, 2022 (CSV) and 2025 (API)
f <- rbind(
  melt(cov[year %in% c(2022, 2025), .(type, country, period = fifelse(year == 2022, "2022 (CSV export)", "2025 (API, eForms)"),
                                      Value = value_raw, `NUTS-2` = nuts2, Activity = activity, `Buyer type` = buyer_type)],
       id.vars = c("type", "country", "period"), variable.name = "field", value.name = "share"),
  win[year == 2022, .(type = "can", country, period = "2022 (CSV export)", field = "Winner country", share = winner_country)],
  win[year == 2022, .(type = "can", country, period = "2022 (CSV export)", field = "Offers", share = offers)],
  wapi[year == 2025, .(type = "can", country, period = "2025 (API, eForms)", field = "Winner country", share = winner_country)])
f <- f[country != "UK"][, `:=`(name = factor(ted_countries[country], levels = lev),
                                typelab = factor(fifelse(type == "cn", "Calls", "Awards"), levels = c("Calls", "Awards")))]
pq2 <- ggplot(f, aes(field, name, fill = share)) +
  geom_tile(colour = "white", linewidth = 0.6) +
  geom_text(aes(label = round(100 * share)), size = 2.6, colour = "grey15") +
  facet_grid(cols = vars(period, typelab), scales = "free_x", space = "free_x") +
  scale_fill_gradient2(low = pal_ted[3], mid = "#FBF6EC", high = pal_ted[2], midpoint = 0.5, limits = c(0, 1), guide = "none") +
  scale_x_discrete(position = "top") +
  labs(title = "Which field can be trusted where: coverage of the key fields by country, before and after eForms",
       subtitle = "Share of notices with the field filled (%), calls and awards, 2022 (CSV export) and 2025 (API, eForms). Value: estimated value on calls, awarded value on awards.",
       caption = paste(ted_source, "Offers: number of tenders received, not in the API table (eForms field not fetched).")) +
  theme_ted(base_size = 13) + theme(panel.grid = element_blank(), axis.text.y = element_text(size = 9), axis.text.x.top = element_text(size = 9, angle = 35, hjust = 0))
save_fig(pq2, "q2_field_coverage.png")

# Q3 — call-to-award lag, CSV link (2022) vs eForms procedure identifier (2024)
l <- dcast(lag[((source == "csv" & year == 2022) | (source == "api" & year == 2024)) & country != "UK"],
           country ~ source, value.var = c("lag_med_days", "linked"))
l <- l[!is.na(lag_med_days_csv) & !is.na(lag_med_days_api)]
l[, name := factor(ted_countries[country], levels = ted_countries[l[order(lag_med_days_api), country]])]
lo <- l[which.min(lag_med_days_api)]; hi <- l[which.max(lag_med_days_api)]
pq3 <- ggplot(l, aes(y = name)) +
  geom_segment(aes(x = lag_med_days_csv, xend = lag_med_days_api, yend = name), colour = "grey78", linewidth = 0.9) +
  geom_point(aes(x = lag_med_days_csv, colour = "2022 calls, CSV link"), size = 2.8) +
  geom_point(aes(x = lag_med_days_api, colour = "2024 calls, eForms procedure identifier"), size = 2.8) +
  geom_text(aes(x = pmax(lag_med_days_csv, lag_med_days_api) + 6, label = sprintf("%.0f%% linked", 100 * linked_api)),
            hjust = 0, size = 2.9, colour = "grey45") +
  scale_colour_manual(values = pal_ted[c(2, 1)]) +
  scale_x_continuous(breaks = seq(0, 400, 60), expand = expansion(mult = c(0.02, 0.15))) +
  labs(title = sprintf("From call to award: a median of %.0f months in %s, %.0f in %s — the same ranking from two different links",
                       lo$lag_med_days_api / 30, ted_countries[lo$country], hi$lag_med_days_api / 30, ted_countries[hi$country]),
       subtitle = "Median days between a call for tenders and its award notice, by buyer country. Text: share of 2024 calls linked to an award by September 2026.",
       caption = paste(ted_source, "Days between dispatch dates; unlinked calls (no award published, or no identifier) excluded.")) +
  theme_ted(base_size = 14) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(pq3, "q3_call_to_award.png")
print(pub[type == "cn" & year == 2025, .(countries = .N, median_of_medians_days = median(lag_med), typical_p90_days = median(lag_p90))])
