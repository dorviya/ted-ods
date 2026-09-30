# R/theme.R — one look for every figure: 16:9, large type, the SDD palette, the message as title
pal_ted <- c("#464E70", "#46AEA7", "#ED672D", "#3A8415", "#C63963", "#F2AE00", "#1162D4", "#9D2EBD",
             "#BA1212", "#97D926", "#7A473E", "#FF667A", "#0A4095", "#BF7B15")   # SDD palette
scale_colour_ted <- function(...) scale_colour_manual(values = pal_ted, ...)
scale_fill_ted   <- function(...) scale_fill_manual(values = pal_ted, ...)
ted_source <- paste("Source: TED CSV open data (DG GROW) to Sept. 2023, TED Search API from Oct. 2023; authors' calculations.",
                    "Above-threshold notices only; procedures counted once, at their first notice.")
ted_countries <- c(AT = "Austria", BE = "Belgium", BG = "Bulgaria", CH = "Switzerland", CY = "Cyprus", CZ = "Czechia",
                   DE = "Germany", DK = "Denmark", EE = "Estonia", ES = "Spain", FI = "Finland", FR = "France", GR = "Greece",
                   HR = "Croatia", HU = "Hungary", IE = "Ireland", IS = "Iceland", IT = "Italy", LI = "Liechtenstein",
                   LT = "Lithuania", LU = "Luxembourg", LV = "Latvia", MK = "North Macedonia", MT = "Malta",
                   NL = "Netherlands", NO = "Norway", PL = "Poland", PT = "Portugal", RO = "Romania", SE = "Sweden",
                   SI = "Slovenia", SK = "Slovakia", UK = "United Kingdom")
ted_iso3 <- c(AT = "AUT", BE = "BEL", BG = "BGR", CH = "CHE", CY = "CYP", CZ = "CZE", DE = "DEU", DK = "DNK", EE = "EST",
              ES = "ESP", FI = "FIN", FR = "FRA", GR = "GRC", HR = "HRV", HU = "HUN", IE = "IRL", IS = "ISL", IT = "ITA",
              LI = "LIE", LT = "LTU", LU = "LUX", LV = "LVA", MK = "MKD", MT = "MLT", NL = "NLD", NO = "NOR", PL = "POL",
              PT = "PRT", RO = "ROU", SE = "SWE", SI = "SVN", SK = "SVK", UK = "GBR")
eurostat_geo <- setNames(names(ted_iso3), names(ted_iso3)); eurostat_geo["GR"] <- "EL"   # our ISO-2 -> Eurostat geo
cofog_names <- c("01" = "01 General public services", "02" = "02 Defence", "03" = "03 Public order & safety",
                 "04" = "04 Economic affairs", "05" = "05 Environmental protection", "06" = "06 Housing & community amenities",
                 "07" = "07 Health", "08" = "08 Recreation, culture & religion", "09" = "09 Education", "10" = "10 Social protection")
cofog_colours <- setNames(pal_ted[c(1, 11, 9, 7, 4, 14, 2, 8, 6, 3)], cofog_names)
activity_cofog_sql <- "CASE a.activity WHEN 'gen-pub' THEN '01' WHEN 'defence' THEN '02' WHEN 'pub-os' THEN '03' WHEN 'econ-aff' THEN '04'
  WHEN 'env-pro' THEN '05' WHEN 'hc-am' THEN '06' WHEN 'health' THEN '07' WHEN 'rcr' THEN '08' WHEN 'education' THEN '09'
  WHEN 'soc-pro' THEN '10' WHEN 'water' THEN '06' WHEN 'electricity' THEN '04' WHEN 'gas-heat' THEN '04' WHEN 'gas-oil' THEN '04'
  WHEN 'solid-fuel' THEN '04' WHEN 'extraction' THEN '04' WHEN 'rail' THEN '04' WHEN 'urttb' THEN '04' WHEN 'airport' THEN '04'
  WHEN 'port' THEN '04' WHEN 'post' THEN '04' ELSE 'unresolved' END"
green_regex <- "électrique|electric|elektro|eléctric|elettric|elektryczn|photovolta|fotovolta|solar|solaire|wärmepumpe|heat pump|pompe à chaleur|isolation thermique|energy efficien|efficacité énergétique|energieeffizien|eficiencia energética|efficienza energetica"
save_fig <- function(p, name, w = 16, h = 9, slide = TRUE, zoom = 1.4) {   # slide version: no titles, no legend, all text 1.4x
  ggsave(file.path("outputs/figures", name), p, width = w, height = h, dpi = 200, bg = "white")
  if (slide) { dir.create("outputs/figures/slides", showWarnings = FALSE)
    ggsave(file.path("outputs/figures/slides", name), p + labs(title = NULL, subtitle = NULL, caption = NULL),
           width = w / zoom, height = h / zoom, dpi = 200 * zoom, bg = "white") }
}
theme_ted <- function(base_size = 16, font = "sans") {   # all sizes relative to `text`, so one override rescales a plot
  theme_minimal(base_size = base_size, base_family = font) +
    theme(plot.title = element_text(face = "bold", size = rel(1.35), hjust = 0, margin = margin(b = 4)),
          plot.subtitle = element_text(colour = "grey35", size = rel(0.95), margin = margin(b = 14), lineheight = 1.1),
          plot.caption = element_text(colour = "grey45", size = rel(0.65), hjust = 0, margin = margin(t = 12)),
          plot.title.position = "plot", plot.caption.position = "plot",
          strip.text = element_text(face = "bold", hjust = 0, size = rel(0.9), margin = margin(b = 4)),
          panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.3), panel.spacing = unit(1.4, "lines"),
          axis.title = element_blank(), axis.text = element_text(colour = "grey40", size = rel(0.75)),
          legend.position = "top", legend.title = element_blank(), legend.text = element_text(size = rel(0.85)),
          legend.key = element_blank(), legend.key.size = unit(1.1, "lines"),
          plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(14, 20, 10, 14))
}
