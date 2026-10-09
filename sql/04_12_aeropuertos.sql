-- 04_12 - Atipicos explicables: viajes de aeropuerto (P10)
-- Pregunta: los viajes largos y caros son errores o son viajes de aeropuerto?
-- Fuente:   vistas `viajes_limpios` y `zonas`. Solo yellow (green casi no
--           opera en aeropuertos). Zonas 1 (EWR), 132 (JFK) y 138 (LaGuardia).
SELECT
    CASE
        WHEN pu_location_id IN (1, 132, 138) OR do_location_id IN (1, 132, 138)
        THEN 'aeropuerto'
        ELSE 'urbano'
    END                                                             AS tipo_viaje,
    count(*)                                                        AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (), 2)              AS pct_viajes,
    round(100.0 * sum(total_amount) / sum(sum(total_amount)) OVER (), 2) AS pct_ingresos,
    round(approx_quantile(trip_distance, 0.5), 2)                   AS distancia_mediana,
    round(approx_quantile(total_amount, 0.5), 2)                    AS total_mediano,
    round(100.0 * count(*) FILTER (WHERE total_amount > 100) / count(*), 2) AS pct_total_mayor_100
FROM viajes_limpios
WHERE taxi = 'yellow'
GROUP BY tipo_viaje
ORDER BY viajes DESC;
