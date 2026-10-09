-- 03_06 - Muestra de registros (3.5)
-- Objetivo: ver valores reales de cada columna.
-- Fuente:   vista `viajes`. 5 filas por tipo de taxi.
-- Nota: se ordena por un hash de varias columnas en lugar de USING SAMPLE.
-- USING SAMPLE con varios hilos tiende a devolver filas de un mismo bloque del
-- archivo (en la prueba, 5 viajes del mismo dia) y no se repite entre
-- ejecuciones; el hash da una muestra dispersa y reproducible.
SELECT * EXCLUDE (archivo, orden)
FROM (
    SELECT
        *,
        row_number() OVER (PARTITION BY taxi
                           ORDER BY hash(pickup, dropoff, pu_location_id, total_amount)) AS orden
    FROM viajes
)
WHERE orden <= 5
ORDER BY taxi DESC, pickup;
