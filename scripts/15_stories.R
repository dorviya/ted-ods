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

# Story 2 — who wins: contract awards by winner size, buyer countries, 2024 (eForms size codes) with the 2022 CSV flag
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
sz <- q("SELECT country, coalesce(winner_size, 'unknown') AS size, count(*) AS n
         FROM 'outputs/panel/award_api.parquet' WHERE year(dispatch_date) = 2024 GROUP BY 1, 2")
flag <- q("SELECT c.country, avg((a.sme = 'Y')::int) AS sme_2022
           FROM 'outputs/panel/award.parquet' AS a JOIN 'outputs/panel/notice_can.parquet' AS c ON a.id = c.id
           WHERE year(c.dispatch_date) = 2022 AND a.sme IN ('Y', 'N') GROUP BY 1")
sz[, `:=`(total = sum(n), known = sum(n[size != "unknown"])), by = country]
keep <- sz[total >= 5000 & known >= 500, unique(country)]
d2 <- sz[country %in% keep & size != "unknown"][, `:=`(share = n / known, alpha = fifelse(known / total < 0.3, 0.45, 1))]
d2[, size := factor(size, levels = c("micro", "small", "medium", "sme", "large"),
                    labels = c("Micro", "Small", "Medium", "SME (size not specified)", "Large"))]
ord <- d2[size != "Large", .(sme = sum(share)), by = country][order(sme)]
d2[, name := factor(ted_countries[country], levels = ted_countries[ord$country])]
cov <- unique(d2[, .(name, known, total)])[, label := sprintf("size declared on %.0f%% of %sk awards", 100 * known / total, round(total / 1e3))]
flag <- flag[country %in% keep][, name := factor(ted_countries[country], levels = levels(d2$name))]
lo <- ord[1]; hi <- ord[.N]
p2 <- ggplot(d2, aes(y = name)) +
  geom_col(aes(x = share, fill = size, alpha = alpha), width = 0.72, position = position_stack(reverse = TRUE)) +
  geom_point(data = flag, aes(x = sme_2022), shape = 18, size = 3.4, colour = "black") +
  geom_text(data = cov, aes(x = 1.02, label = label), hjust = 0, size = 3.2, colour = "grey45") +
  scale_x_continuous(labels = scales::label_percent(), breaks = seq(0, 1, 0.25), expand = expansion(mult = c(0, 0.34))) +
  scale_fill_manual(values = c(pal_ted[c(2, 7, 13, 1)], "grey80")) + scale_alpha_identity() +
  labs(title = sprintf("Small and medium-sized firms win most public contracts by number: from %.0f%% in %s to %.0f%% in %s",
                       100 * lo$sme, ted_countries[lo$country], 100 * hi$sme, ted_countries[hi$country]),
       subtitle = paste("Share of contract awards by declared winner size, 2024, buyer countries with at least 5,000 awarded winners.",
                        "Black diamond: SME share of awards in 2022 from the CSV's SME flag.", sep = "\n"),
       caption = paste0(ted_source, "\nSizes as declared on result notices; 'SME' is the generic code some platforms send; ",
                        "awards without a declared size excluded (coverage at right); faded bars: size declared on fewer than 30% of awards.")) +
  theme_ted() + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(p2, "02_winner_size.png")
