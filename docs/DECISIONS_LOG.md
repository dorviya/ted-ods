# Decisions log (append-only)

## 2026-09-26 — Work on SSP Cloud (Onyxia) pods rather than work laptops
Context: the brief assumed locked-down laptops and local storage.
Decision: code in a public GitHub repo; data in the personal bucket under diffusion/ (public read); packages via renv
restored by setup.sh, usable as the pod's init script.
Alternatives rejected: laptops (no admin rights, storage); a private repo (blocks the init-script URL and teammates' clones).
Consequence: nothing lives on a pod's disk; a fresh pod is rebuilt in minutes; teammates query parquet over HTTPS without credentials.

## 2026-09-26 — API count series from January 2016, not January 2024
Context: the CSV stops on 2023-12-31 and does not cover eForms (mandatory since late October 2023), so its last months are probably thin.
Decision: run the count loop from 2016 (about 7,700 requests) so the API series overlaps the CSV and the eForms break can be measured.
Consequence: one consistent count series for the headline story, and a free validation of the CSV's distinct-notice counts.
