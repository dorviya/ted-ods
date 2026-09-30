# scripts/24_eurostat_robustness.R — the functional comparison under two timings: single year 2022, and 2016–2022 averages on both sides
source("R/packages.R"); source("R/theme.R")
es <- fread("reference/eurostat_gov_10a_exp.csv")
if ("TIME_PERIOD" %in% names(es)) setnames(es, "TIME_PERIOD", "time"); if ("OBS_VALUE" %in% names(es)) setnames(es, "OBS_VALUE", "values")
es <- es[na_item %in% c("P2", "P51G") & cofog99 %in% sprintf("GF%02d", 1:10)]
es[, `:=`(year = as.integer(substr(as.character(time), 1, 4)), cofog = sub("GF", "", cofog99), country = names(eurostat_geo)[match(geo, eurostat_geo)])]
ted <- fread("outputs/quality/cofog_shares_year.csv")[type == "can" & cofog %in% sprintf("%02d", 1:10)]
sel <- c("DE", "FR", "IT", "ES", "PL", "NL", "BE", "AT", "CZ", "SE", "DK", "PT", "FI", "NO", "IE", "RO")
comp <- function(y1, y2) {
  e <- es[year %between% c(y1, y2) & !is.na(country), .(off = sum(values, na.rm = TRUE)), by = .(country, cofog)][, off_share := off / sum(off), by = country]
  t <- ted[year %between% c(y1, y2), .(ted = sum(value_eur)), by = .(country, cofog)][, ted_share := ted / sum(ted), by = country]
  sc <- merge(t, e, by = c("country", "cofog"))[country %in% sel & ted_share > 0 & off_share > 0]
  data.table(window = sprintf("%d-%d", y1, y2), countries = uniqueN(sc$country),
             r_pooled = round(sc[, cor(log(ted_share), log(off_share))], 2),
             r_country_median = round(sc[, cor(log(ted_share), log(off_share)), by = country][, median(V1)], 2))
}
print(rbind(comp(2022, 2022), comp(2019, 2022), comp(2016, 2022)))
