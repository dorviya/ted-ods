-- scripts/14_award_api.sql — one row per (result notice, distinct winner), API years (Oct 2023 → today).
-- Names come one per tender in a language-keyed object; countries, ids and sizes one per organisation; the notice's
-- euro value comes from notice_all. Country: the single distinct country when there is one, else positional when the
-- list aligns with the names; ids and sizes positional when aligned. Value per winner = value_eur_notice / n_winners.
COPY (
  WITH n AS (
    SELECT pub_number, procedure_id, dispatch_date, country, country_iso3,
           list_distinct(from_json(json_extract(winner_names, '$.' || json_keys(winner_names)[1]), '["VARCHAR"]')) AS names,
           CASE WHEN json_valid(winner_countries) THEN from_json(winner_countries, '["VARCHAR"]') END AS ctry,
           CASE WHEN json_valid(winner_ids)       THEN from_json(winner_ids,       '["VARCHAR"]') END AS ids,
           CASE WHEN json_valid(winner_sizes)     THEN from_json(winner_sizes,     '["VARCHAR"]') END AS sizes
    FROM 'outputs/panel/notice_api.parquet'
    WHERE type = 'can' AND country IS NOT NULL AND json_valid(winner_names)),
  w AS (
    SELECT pub_number, procedure_id, dispatch_date, country, country_iso3, ctry, ids, sizes,
           len(names) AS n_winners, unnest(names) AS winner, unnest(range(1, len(names) + 1)) AS i
    FROM n WHERE len(names) > 0)
  SELECT w.pub_number, w.procedure_id, w.dispatch_date, w.country, w.country_iso3, w.winner, w.n_winners,
         CASE WHEN len(list_distinct(ctry)) = 1 THEN ctry[1] WHEN len(ctry) = n_winners THEN ctry[i] END AS winner_country,
         CASE WHEN len(ids)   = n_winners THEN ids[i]   END AS winner_id,
         CASE WHEN len(sizes) = n_winners THEN sizes[i] END AS winner_size,
         a.value_eur AS value_eur_notice
  FROM w LEFT JOIN (SELECT pub_number, value_eur FROM 'outputs/panel/notice_all.parquet'
                    WHERE source = 'api' AND type = 'can') AS a USING (pub_number)
  WHERE w.winner IS NOT NULL
) TO 'outputs/panel/award_api.parquet' (FORMAT parquet);
