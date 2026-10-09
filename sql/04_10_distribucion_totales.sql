-- 04_10 - Distribucion de valores relevantes: total cobrado (P9)
-- Pregunta: como se distribuye el total pagado por viaje en cada tipo de taxi.
-- Fuente:   vista `viajes_limpios`. Intervalos de 5 USD hasta 150 USD.
SELECT
    taxi,
    least(floor(total_amount / 5) * 5, 150)                         AS desde_usd,
    count(*)                                                        AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY taxi), 2) AS pct_del_taxi
FROM viajes_limpios
GROUP BY taxi, desde_usd
ORDER BY taxi DESC, desde_usd;
