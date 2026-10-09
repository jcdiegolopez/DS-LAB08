-- 03_05 - Columnas que no estan en todos los archivos (3.3, 3.6)
-- Objetivo: detectar cambios de esquema entre meses y anios.
-- Fuente:   esquema interno de cada Parquet (parquet_schema), sin leer filas.
-- Una columna que solo aparece en parte de los archivos obliga a leer con
-- union_by_name = true; de lo contrario DuckDB usa el esquema del primer
-- archivo y la columna no existe para la consulta.
WITH esquema AS (
    SELECT
        split_part(file_name, '/', 3)            AS taxi,
        regexp_extract(file_name, '\d{4}-\d{2}') AS mes,
        name                                     AS columna,
        type                                     AS tipo_fisico
    FROM parquet_schema('data/raw/*/*/*.parquet')
    WHERE name <> 'schema'
      AND (getvariable('anios') IS NULL
           OR list_contains(getvariable('anios'), split_part(file_name, '/', 4)::INTEGER))
),
archivos AS (
    SELECT taxi, count(DISTINCT mes) AS total FROM esquema GROUP BY taxi
)
SELECT
    e.taxi,
    e.columna,
    string_agg(DISTINCT e.tipo_fisico, ', ')  AS tipos_fisicos,
    count(DISTINCT e.mes)                     AS archivos_con_columna,
    a.total                                   AS archivos_totales,
    min(e.mes)                                AS desde,
    max(e.mes)                                AS hasta
FROM esquema e
JOIN archivos a USING (taxi)
GROUP BY e.taxi, e.columna, a.total
HAVING count(DISTINCT e.mes) < a.total
    OR count(DISTINCT e.tipo_fisico) > 1
ORDER BY e.taxi DESC, desde;
