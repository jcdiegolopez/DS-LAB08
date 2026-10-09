-- 03_09 - Calidad: distancias y montos (3.6)
-- Objetivo: cuantificar distancias cero o absurdas y montos negativos, cero o
--           extremos, por tipo de taxi y anio.
-- Fuente:   vista `viajes`.
SELECT
    taxi,
    anio_archivo                                                 AS anio,
    count(*)                                                     AS registros,
    count(*) FILTER (WHERE trip_distance = 0)                    AS distancia_cero,
    count(*) FILTER (WHERE trip_distance > 200)                  AS distancia_mayor_200mi,
    max(trip_distance)                                           AS distancia_maxima,
    count(*) FILTER (WHERE fare_amount < 0)                      AS tarifa_negativa,
    count(*) FILTER (WHERE fare_amount = 0)                      AS tarifa_cero,
    count(*) FILTER (WHERE total_amount < 0)                     AS total_negativo,
    count(*) FILTER (WHERE total_amount > 1000)                  AS total_mayor_1000,
    max(total_amount)                                            AS total_maximo,
    count(*) FILTER (WHERE duracion_min > 0 AND trip_distance > 0
                       AND trip_distance / (duracion_min / 60) > 80) AS velocidad_mayor_80mph
FROM viajes
GROUP BY taxi, anio_archivo
ORDER BY taxi DESC, anio;
