# ted-ods — entry point: attach packages, load the functions in R/, run the numbered scripts in order.
source("R/packages.R")
invisible(lapply(setdiff(list.files("R", full.names = TRUE), "R/packages.R"), source))
for (s in list.files("scripts", pattern = "^[0-9]{2}_.*\\.R$", full.names = TRUE)) {
  message("== ", s); source(s, local = new.env())
}
