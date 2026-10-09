-- 03_02 - Cantidad de registros (3.2)
-- Objetivo: contar los viajes por tipo de taxi y anio, y su peso en el total.
-- Fuente:   vista `viajes` (todos los Parquet de yellow y green).
SELECT
    taxi,
    anio_archivo                                         AS anio,
    count(*)                                             AS registros,
    round(100.0 * count(*) / sum(count(*)) OVER (), 2)   AS pct_del_total
FROM viajes
GROUP BY taxi, anio_archivo
ORDER BY taxi, anio;
