-- 04_05 - Diferencias yellow vs green: donde empiezan y terminan los viajes (P5)
-- Pregunta: los taxis verdes cumplen su funcion de servir fuera de Manhattan?
-- Fuente:   vistas `viajes_limpios` y `zonas` (taxi_zone_lookup.csv).
SELECT
    v.taxi,
    zo.borough                                                       AS borough_origen,
    count(*)                                                         AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY v.taxi), 2) AS pct_del_taxi,
    round(100.0 * count(*) FILTER (WHERE zd.borough = zo.borough) / count(*), 1)
                                                                     AS pct_termina_mismo_borough
FROM viajes_limpios v
JOIN zonas zo ON zo.location_id = v.pu_location_id
JOIN zonas zd ON zd.location_id = v.do_location_id
GROUP BY v.taxi, zo.borough
ORDER BY v.taxi DESC, viajes DESC;
