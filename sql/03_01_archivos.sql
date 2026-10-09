-- 03_01 - Cantidad de archivos disponibles (3.1)
-- Objetivo: contar los Parquet descargados por tipo de taxi y anio.
-- Fuente:   data/raw/*/*/*.parquet (listado con glob, sin leer los datos).
SELECT
    split_part(file, '/', 3)                AS taxi,
    split_part(file, '/', 4)::INTEGER       AS anio,
    count(*)                                AS archivos,
    min(regexp_extract(file, '\d{4}-\d{2}')) AS primer_mes,
    max(regexp_extract(file, '\d{4}-\d{2}')) AS ultimo_mes
FROM glob('data/raw/*/*/*.parquet')
WHERE getvariable('anios') IS NULL
   OR list_contains(getvariable('anios'), split_part(file, '/', 4)::INTEGER)
GROUP BY ALL
ORDER BY taxi, anio;
