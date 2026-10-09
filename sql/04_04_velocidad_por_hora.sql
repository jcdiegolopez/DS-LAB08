-- 04_04 - Caracteristicas del viaje: velocidad y duracion por hora (P4)
-- Pregunta: cuanto se frena el trafico en hora pico y cuanto dura un viaje
--           comparable (mediana de minutos por milla).
-- Fuente:   vista `viajes_limpios`, solo yellow (volumen suficiente por hora).
SELECT
    hour(pickup)                                                     AS hora,
    count(*)                                                         AS viajes,
    round(approx_quantile(trip_distance / (duracion_min / 60), 0.5), 1) AS velocidad_mediana_mph,
    round(approx_quantile(duracion_min / trip_distance, 0.5), 1)     AS minutos_por_milla,
    round(approx_quantile(trip_distance, 0.5), 2)                    AS distancia_mediana
FROM viajes_limpios
WHERE taxi = 'yellow'
GROUP BY hora
ORDER BY hora;
