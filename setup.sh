#!/usr/bin/env bash
# Rebuild the working environment on a fresh Onyxia pod.
#  - as the pod's init script: paste this file's raw GitHub URL in the launch form ("Init script"), or
#  - by hand:  cd ~/work && git clone https://github.com/dorviya/ted-ods.git && bash ted-ods/setup.sh
# Data is not restored here: it lives in the bucket (see README).
set -euo pipefail
REPO="https://github.com/dorviya/ted-ods.git"
DIR="$HOME/work/ted-ods"
[ -d "$DIR/.git" ] || git clone "$REPO" "$DIR"
cd "$DIR"
Rscript -e 'if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv"); renv::restore(prompt = FALSE)'
echo "ted-ods ready in $DIR"
