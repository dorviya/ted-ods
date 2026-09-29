# R/theme.R — one look for every figure: 16:9, large type, the SDD palette, the message as title
pal_ted <- c("#464E70", "#46AEA7", "#ED672D", "#3A8415", "#C63963", "#F2AE00", "#1162D4", "#9D2EBD",
             "#BA1212", "#97D926", "#7A473E", "#FF667A", "#0A4095", "#BF7B15")   # SDD palette
scale_colour_ted <- function(...) scale_colour_manual(values = pal_ted, ...)
scale_fill_ted   <- function(...) scale_fill_manual(values = pal_ted, ...)
theme_ted <- function(base_size = 16, font = "sans") {
  theme_minimal(base_size = base_size, base_family = font) +
    theme(plot.title = element_text(face = "bold", size = base_size * 1.35, hjust = 0, margin = margin(b = 4)),
          plot.subtitle = element_text(colour = "grey35", size = base_size * 0.95, margin = margin(b = 14), lineheight = 1.1),
          plot.caption = element_text(colour = "grey45", size = base_size * 0.65, hjust = 0, margin = margin(t = 12)),
          plot.title.position = "plot", plot.caption.position = "plot",
          strip.text = element_text(face = "bold", hjust = 0, size = base_size * 0.85, margin = margin(b = 3)),
          panel.grid.minor = element_blank(), panel.grid.major.x = element_blank(),
          panel.grid.major.y = element_line(colour = "grey88", linewidth = 0.3),
          panel.spacing = unit(1.2, "lines"),
          axis.title = element_blank(), axis.text = element_text(colour = "grey40", size = base_size * 0.7),
          legend.position = "top", legend.title = element_blank(),
          plot.background = element_rect(fill = "white", colour = NA), plot.margin = margin(18, 24, 14, 24))
}
ted_source <- paste("Source: TED CSV open data (DG GROW) to Sept. 2023, TED Search API from Oct. 2023; authors' calculations.",
                    "Above-threshold notices only; procedures counted once, at their first notice.")
save_fig <- function(p, name, w = 16, h = 9) ggsave(file.path("outputs/figures", name), p, width = w, height = h, dpi = 200, bg = "white")
