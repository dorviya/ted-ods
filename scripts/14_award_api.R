# scripts/14_award_api.R — API-years award table, one row per (result notice, distinct winner); SQL through the duckdb CLI (json extension)
stopifnot(system2("duckdb", stdin = "scripts/14_award_api.sql") == 0)
