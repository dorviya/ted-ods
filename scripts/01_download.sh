#!/usr/bin/env bash
# Step 1: fetch the TED CSV open data (one zip per year and notice type) from data.europa.eu,
# test each zip's integrity, keep a copy in the public bucket. Idempotent: reruns skip what is done.
set -uo pipefail
cd "$(dirname "$0")/.."
BUCKET=s3/dorviya/diffusion/ted-ods/raw
STORE=https://data.europa.eu/api/hub/store/data
mkdir -p data/raw/zip

files=()
for y in $(seq 2006 2023); do files+=("ted-contract-notices-$y.zip" "ted-contract-award-notices-$y.zip"); done
files+=("ted-contract-notices-2018-2023.zip" "ted-contract-award-notices-2018-2023.zip")

for f in "${files[@]}"; do
  if mc stat "$BUCKET/$f" >/dev/null 2>&1; then echo "skip    $f (already in bucket)"; continue; fi
  echo "get     $f  $(date +%H:%M:%S)"
  curl -sSL --fail --retry 5 --retry-delay 15 -C - -o "data/raw/zip/$f" "$STORE/$f" || { echo "FAILED  $f"; continue; }
  python3 -c 'import sys, zipfile; sys.exit(zipfile.ZipFile(sys.argv[1]).testzip() is not None)' "data/raw/zip/$f" \
    || { echo "CORRUPT $f (deleted, rerun to retry)"; rm -f "data/raw/zip/$f"; continue; }
  mc --quiet cp "data/raw/zip/$f" "$BUCKET/$f" && echo "ok      $f  $(du -h "data/raw/zip/$f" | cut -f1)"
done
echo "done $(date)"
