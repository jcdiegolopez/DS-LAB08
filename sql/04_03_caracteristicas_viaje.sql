-- 04_03 - Caracteristicas del viaje: distancia, duracion, velocidad y pasajeros (P3)
-- Pregunta: como es un viaje tipico y que tan dispersas son sus caracteristicas.
-- Fuente:   vista `viajes_limpios`. Se reportan percentiles porque las
--           distribuciones son muy asimetricas y el promedio engana.
SELECT
    taxi,
    count(*)                                                        AS viajes,
    round(approx_quantile(trip_distance, 0.25), 2)                  AS distancia_p25,
    round(approx_quantile(trip_distance, 0.50), 2)                  AS distancia_mediana,
    round(approx_quantile(trip_distance, 0.75), 2)                  AS distancia_p75,
    round(approx_quantile(trip_distance, 0.99), 2)                  AS distancia_p99,
    round(avg(trip_distance), 2)                                    AS distancia_promedio,
    round(approx_quantile(duracion_min, 0.50), 1)                   AS duracion_mediana_min,
    round(approx_quantile(duracion_min, 0.99), 1)                   AS duracion_p99_min,
    round(approx_quantile(trip_distance / (duracion_min / 60), 0.50), 1) AS velocidad_mediana_mph,
    round(avg(passenger_count), 2)                                  AS pasajeros_promedio,
    round(100.0 * count(*) FILTER (WHERE passenger_count = 1)
          / count(passenger_count), 1)                              AS pct_un_pasajero
FROM viajes_limpios
GROUP BY taxi
ORDER BY taxi DESC;
