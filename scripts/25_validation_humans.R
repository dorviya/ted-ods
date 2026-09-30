# scripts/25_validation_humans.R — the mapping's COFOG division against an economist's blind labels (170 notices, stratified by band)
source("R/packages.R"); source("R/theme.R")
con <- dbConnect(duckdb()); q <- function(sql) as.data.table(dbGetQuery(con, sql))
h <- fread("outputs/validation_labels_VB.csv", colClasses = "character")[nzchar(human_div)]
key <- fread("outputs/validation_key.csv", colClasses = "character")
act <- q("SELECT pub_number, any_value(activity) AS activity FROM 'outputs/panel/notice_all.parquet' GROUP BY 1")
amap <- c(`gen-pub` = "01", defence = "02", `pub-os` = "03", `econ-aff` = "04", `env-pro` = "05", `hc-am` = "06", health = "07", rcr = "08",
          education = "09", `soc-pro` = "10", water = "06", electricity = "04", `gas-heat` = "04", `gas-oil` = "04", `solid-fuel` = "04",
          extraction = "04", rail = "04", urttb = "04", airport = "04", port = "04", post = "04")
v <- merge(merge(h, key[, .(sample_id, band, consensus)], by = "sample_id"), act, by = "pub_number", all.x = TRUE)
v[, machine := fifelse(consensus == "BD", fifelse(activity %in% names(amap), amap[activity], "unresolved"), consensus)]
v[, `:=`(source = fifelse(consensus == "BD", "buyer activity", "product code"), agree = human_div == machine)]
w <- c(unanimous = 0.656, `strong (75-99%)` = 0.186, `majority (50-75%)` = 0.136, `contested (<=50%)` = 0.023)   # bands' shares of notices
byband <- v[, .(n = .N, agreement = mean(agree)), by = band][, weight := w[band]]
weighted <- byband[, sum(agreement * weight) / sum(weight)]
print(byband[order(-weight)]); print(v[, .(n = .N, agreement = round(mean(agree), 3)), by = source])
cat(sprintf("raw agreement %.1f%% (n = %d); weighted by the bands' notice shares %.1f%%\n", 100 * mean(v$agree), nrow(v), 100 * weighted))
print(v[agree == FALSE, .N, by = .(human = human_div, machine)][order(-N)][1:10])
fwrite(v, "outputs/quality/validation_result.csv")
pb <- ggplot(byband, aes(agreement, factor(band, levels = rev(names(w))))) + geom_col(fill = pal_ted[1], width = 0.65) +
  geom_text(aes(label = sprintf("%.0f%%   (n = %d)", 100 * agreement, n)), hjust = -0.1, size = 4.4, colour = "grey30") +
  scale_x_continuous(labels = scales::label_percent(), limits = c(0, 1.2), expand = expansion(0)) +
  labs(title = sprintf("An economist agrees with the machine's function on %.0f%% of notices — %.0f%% where the 11 runs were unanimous, less where they disagreed",
                       100 * weighted, 100 * byband[band == "unanimous", agreement]),
       subtitle = paste("Share of notices where the human's COFOG division equals the mapping's (product code, or buyer activity for generic products),",
                        "by agreement band of the 11 LLM runs; 170 notices labelled blind, stratified by band; headline weighted by the bands' shares of notices."),
       caption = "Source: outputs/validation_labels_VB.csv (blind labels by an economist), reference/cpv_cofog_consensus.csv; authors' calculations.") +
  theme_ted(base_size = 15) + theme(panel.grid.major.y = element_blank(), panel.grid.major.x = element_line(colour = "grey88", linewidth = 0.3))
save_fig(pb, "05b_human_agreement.png")
