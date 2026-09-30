# scripts/27_orbis_laptop.R — run on the OECD laptop only (Orbis is licensed data). Joins TED winners to Orbis IP Companies_Headers.txt
# by the national register number embedded in the BvD ID (country prefix + number); writes aggregates only, which may leave the laptop.
library(data.table)
orb <- fread("//main.oecd.org/em_sources/ORBIS/ORBIS_IP/Companies_Headers.txt", sep = "\t", quote = "", encoding = "UTF-8",
             select = c("BvDID", "NAME", "Country ISO code", "BvD major sector", "Status", "Operating revenue (Turnover)", "Number of employees", "GUO - Name", "GUO - BvD ID Number"))
setnames(orb, c("bvdid", "name", "iso2", "sector", "status", "revenue", "employees", "guo_name", "guo_bvdid"))
orb[, `:=`(prefix = substr(bvdid, 1, 2), natid = toupper(gsub("[^A-Za-z0-9]", "", substr(bvdid, 3, 100))))]
ted <- fread("https://minio.lab.sspcloud.fr/dorviya/diffusion/ted-ods/quality/ted_winner_ids.csv")
ted[, `:=`(prefix = fifelse(country == "UK", "GB", country), natid = winner_id_norm)]
ted[prefix == "FR" & nchar(natid) == 14 & grepl("^[0-9]+$", natid), natid := substr(natid, 1, 9)]      # SIRET -> SIREN
ted[prefix == "FR" & grepl("^FR[0-9]{11}$", natid), natid := substr(natid, 5, 13)]                   # VAT -> SIREN
ted[grepl(paste0("^", prefix, "[0-9]"), natid), natid := sub(paste0("^", prefix), "", natid)]         # ids carrying the country prefix
m <- merge(ted, orb, by = c("prefix", "natid"))
cat("TED winner ids:", nrow(ted), " matched to Orbis IP:", nrow(m), " awards covered:", sum(m$awards), "of", sum(ted$awards), "\n")
print(merge(ted[, .(ids = .N, awards = sum(awards)), by = prefix], m[, .(matched = .N, awards_matched = sum(awards)), by = prefix], by = "prefix", all.x = TRUE)[order(-ids)][1:22])
fwrite(m[, .(winners = .N, awards = sum(awards)), by = .(prefix, sector)], "orbis_match_sector.csv")
fwrite(m[, .(winners = .N, awards = sum(awards)), by = .(prefix, guo_country = substr(guo_bvdid, 1, 2))], "orbis_match_guo.csv")
fwrite(m[, .(winners = .N, awards = sum(awards)), by = .(prefix, size = cut(suppressWarnings(as.numeric(employees)), c(-Inf, 9, 49, 249, Inf), c("micro", "small", "medium", "large")))], "orbis_match_size.csv")
