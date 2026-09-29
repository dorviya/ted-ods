# scripts/15_stories.R — the story charts, one file per story in outputs/figures/
source("R/packages.R"); source("R/theme.R")

# Story 1 — the pulse: calls for tenders per month, index 2019 monthly average = 100, 33 countries and 14 panels
m   <- fread("outputs/quality/monthly_procedures.csv")[type == "cn" & month < as.IDate("2026-09-01")]
sel <- c(DE = "Germany", FR = "France", PL = "Poland", ES = "Spain", IT = "Italy", CZ = "Czechia", SE = "Sweden",
         NL = "Netherlands", AT = "Austria", BE = "Belgium", DK = "Denmark", PT = "Portugal", NO = "Norway", FI = "Finland")
d <- rbind(m[country %in% names(sel), .(country, month, procedures)],
           m[, .(country = "ALL", procedures = sum(procedures)), by = month])
setorder(d, country, month)
d[, base := mean(procedures[year(month) == 2019]), by = country]
d[, `:=`(idx = 100 * procedures / base, idx12 = 100 * frollmean(procedures, 12) / base), by = country]
d[, panel := factor(fifelse(country == "ALL", "All 33 countries", sel[country]), levels = c("All 33 countries", unname(sel)))]
last <- d[country == "ALL" & month == max(month)]
ev <- as.IDate(c("2020-03-01", "2022-02-01", "2023-10-01"))
notes <- data.table(panel = factor(c("Italy", "Portugal", "Poland"), levels = levels(d$panel)),
                    month = as.IDate(c("2023-01-01", "2016-06-01", "2020-10-01")), y = c(335, 300, 290), hjust = c(1, 0, 1),
                    label = c("rush before the new procurement code\n(1 July 2023), standstill after",
                              "utilities and public-law bodies\nstart publishing on TED", "COVID-19 health purchases,\nDecember 2020"))
p1 <- ggplot(d, aes(month)) +
  geom_vline(xintercept = ev, colour = "grey72", linetype = "22", linewidth = 0.35) +
  geom_hline(yintercept = 100, colour = "grey45", linewidth = 0.3) +
  geom_line(aes(y = idx), colour = "grey75", linewidth = 0.3) +
  geom_line(aes(y = idx12), colour = pal_ted[1], linewidth = 0.9, na.rm = TRUE) +
  geom_text(data = notes, aes(month, y, label = label, hjust = hjust), size = 3.3, colour = "grey35", lineheight = 0.95) +
  facet_wrap(~ panel, ncol = 5) +
  scale_x_date(breaks = as.Date(sprintf("%d-01-01", seq(2016, 2026, 2))), date_labels = "%y", expand = expansion(mult = c(0.01, 0.02))) +
  labs(title = sprintf("Public buyers launched %.0f%% %s calls for tenders in the last twelve months than in 2019",
                       abs(last$idx12 - 100), fifelse(last$idx12 >= 100, "more", "fewer")),
       subtitle = paste0("Calls for tenders published on TED, monthly to August 2026, index 2019 monthly average = 100. ",
                         "Grey: monthly count; line: trailing 12-month average.\n",
                         "Dotted lines: COVID-19 (March 2020), Russia's invasion of Ukraine (February 2022), eForms notice format (October 2023)."),
       caption = paste(ted_source, "Sept. 2026 dropped (still incomplete).")) +
  theme_ted()
save_fig(p1, "01_pulse_calls.png")
