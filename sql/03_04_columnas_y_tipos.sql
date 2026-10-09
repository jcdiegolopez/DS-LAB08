-- 03_04 - Columnas y tipos de datos (3.3 y 3.4)
-- Objetivo: listar las columnas de cada tipo de taxi con el tipo que asigna
--           DuckDB al leer los Parquet (union de todos los archivos).
-- Fuente:   vistas yellow_raw y green_raw.
SELECT 'yellow' AS taxi, column_name AS columna, column_type AS tipo
FROM (DESCRIBE yellow_raw)
WHERE column_name <> 'filename'
UNION ALL
SELECT 'green', column_name, column_type
FROM (DESCRIBE green_raw)
WHERE column_name <> 'filename'
ORDER BY taxi DESC, columna;
