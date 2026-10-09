-- 03_08 - Calidad: fechas y duraciones (3.6)
-- Objetivo: medir registros con fechas fuera del mes de su archivo y
--           duraciones imposibles (negativas, cero o de casi un dia).
-- Fuente:   vista `viajes`.
SELECT
    taxi,
    count(*)                                                        AS registros,
    min(pickup)                                                     AS pickup_minimo,
    max(pickup)                                                     AS pickup_maximo,
    count(*) FILTER (WHERE year(pickup) <> anio_archivo
                        OR month(pickup) <> mes_archivo)            AS fuera_de_su_mes,
    count(*) FILTER (WHERE duracion_min < 0)                        AS duracion_negativa,
    count(*) FILTER (WHERE duracion_min = 0)                        AS duracion_cero,
    count(*) FILTER (WHERE duracion_min > 360)                      AS duracion_mayor_6h,
    count(*) FILTER (WHERE duracion_min BETWEEN 1380 AND 1500)      AS duracion_cerca_24h,
    round(100.0 * count(*) FILTER (WHERE duracion_min <= 0 OR duracion_min > 360)
          / count(*), 3)                                            AS pct_duracion_invalida
FROM viajes
GROUP BY taxi
ORDER BY taxi DESC;
