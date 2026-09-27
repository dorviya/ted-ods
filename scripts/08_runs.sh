#!/usr/bin/env bash
# The classification runs behind the agreement measure. Baselines (prompt v1, English labels, sorted batches) were
# launched first as run ids "openai" (gpt-5.4-mini) and "gemini" (gemini-3.8-flash); each run below varies one thing.
cd "$(dirname "$0")/.."
run() { nohup Rscript scripts/08_classify_cpv.R "$@" > "data/cls_$3.log" 2>&1 & }
run openai gpt-5.4-mini      oa_mini_v1_rep   docs/prompts/cpv_cofog_v1.md en 0   # exact repeat: sampling-noise floor
run openai gpt-5.4-mini      oa_mini_v1_shuf  docs/prompts/cpv_cofog_v1.md en 1   # shuffled batches: context effect
run openai gpt-5.4-mini      oa_mini_v2_en    docs/prompts/cpv_cofog_v2.md en 0   # reworded prompt
run openai gpt-5.4-mini      oa_mini_v1_fr    docs/prompts/cpv_cofog_v1.md fr 0   # French labels
run openai gpt-5.5           oa_large_v1_en   docs/prompts/cpv_cofog_v1.md en 0   # larger model
run gemini gemini-3.8-flash  gm_flash_v1_shuf docs/prompts/cpv_cofog_v1.md en 1
run gemini gemini-3.8-flash  gm_flash_v2_en   docs/prompts/cpv_cofog_v2.md en 0
run gemini gemini-3.8-flash  gm_flash_v1_fr   docs/prompts/cpv_cofog_v1.md fr 0
run gemini gemini-pro-latest gm_pro_v1_en     docs/prompts/cpv_cofog_v1.md en 0   # larger model
