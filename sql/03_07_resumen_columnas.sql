-- 03_07 - Resumen estadistico de cada columna (3.6)
-- Objetivo: minimo, maximo, promedio, cuartiles y % de nulos por columna para
--           encontrar valores imposibles de un vistazo.
-- Fuente:   vista `viajes` (yellow y green juntos).
SELECT
    column_name     AS columna,
    column_type     AS tipo,
    min, max,
    approx_unique   AS distintos_aprox,
    avg, q25, q50, q75,
    null_percentage AS pct_nulos
FROM (SUMMARIZE SELECT * EXCLUDE (archivo, taxi) FROM viajes);
