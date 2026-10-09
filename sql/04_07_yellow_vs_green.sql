-- 04_07 - Diferencias yellow vs green: resumen por viaje (P6)
-- Pregunta: en que se diferencia un viaje amarillo de uno verde (tarifa, total,
--           cargos, tipo de servicio) usando valores por viaje y no totales.
-- Fuente:   vista `viajes_limpios`.
SELECT
    taxi,
    count(*)                                                       AS viajes,
    round(approx_quantile(fare_amount, 0.5), 2)                    AS tarifa_mediana,
    round(avg(fare_amount), 2)                                     AS tarifa_promedio,
    round(avg(total_amount), 2)                                    AS total_promedio,
    round(avg(fare_amount / trip_distance) FILTER (WHERE trip_distance >= 1), 2)
                                                                   AS tarifa_por_milla,
    round(avg(congestion_surcharge), 2)                            AS recargo_congestion_prom,
    round(avg(cbd_congestion_fee), 2)                              AS cargo_cbd_prom,
    round(avg(tolls_amount), 2)                                    AS peajes_prom,
    round(100.0 * count(*) FILTER (WHERE ratecode_id IN (2, 3)) / count(*), 2)
                                                                   AS pct_aeropuerto_jfk_newark,
    round(100.0 * count(*) FILTER (WHERE ratecode_id = 5) / count(*), 2)
                                                                   AS pct_tarifa_negociada,
    round(100.0 * count(*) FILTER (WHERE trip_type = 2) / count(trip_type), 2)
                                                                   AS pct_despacho_green
FROM viajes_limpios
GROUP BY taxi
ORDER BY taxi DESC;
