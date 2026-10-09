-- 03_03 - Registros por archivo (3.2)
-- Objetivo: revisar que ningun mes venga vacio o con un volumen anomalo.
-- Fuente:   metadatos de cada Parquet (parquet_file_metadata): no lee las filas.
SELECT
    split_part(file_name, '/', 3)                 AS taxi,
    regexp_extract(file_name, '\d{4}-\d{2}')      AS mes,
    num_rows                                      AS registros,
    round(num_rows / avg(num_rows) OVER (PARTITION BY split_part(file_name, '/', 3)), 2)
                                                  AS relativo_al_promedio
FROM parquet_file_metadata('data/raw/*/*/*.parquet')
WHERE getvariable('anios') IS NULL
   OR list_contains(getvariable('anios'), split_part(file_name, '/', 4)::INTEGER)
ORDER BY taxi, mes;
