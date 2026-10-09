-- 08_04 - Entrada en vigor del cargo por congestion de Manhattan (8.6)
-- Pregunta: desde cuando se cobra cbd_congestion_fee, a que proporcion de
--           viajes y cuanto. La columna no existe en los archivos de 2024:
--           con union_by_name queda nula y aqui se cuenta como 0.
-- Fuente:   vista `viajes_limpios`.
SELECT
    taxi,
    date_trunc('month', pickup)::DATE                                   AS mes,
    count(*)                                                            AS viajes,
    round(100.0 * count(*) FILTER (WHERE cbd_congestion_fee > 0) / count(*), 1) AS pct_con_cargo_cbd,
    round(avg(cbd_congestion_fee) FILTER (WHERE cbd_congestion_fee > 0), 2)     AS cargo_cbd_cuando_aplica,
    round(avg(coalesce(cbd_congestion_fee, 0)), 3)                      AS cargo_cbd_promedio
FROM viajes_limpios
GROUP BY taxi, mes
ORDER BY taxi DESC, mes;
