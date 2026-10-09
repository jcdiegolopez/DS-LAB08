-- 03_13 - Registros duplicados (3.6)
-- Objetivo: contar viajes repetidos exactamente (mismo taxi, proveedor, horas,
--           zonas, distancia y montos).
-- Fuente:   vista `viajes`.
WITH grupos AS (
    SELECT taxi, count(*) AS veces
    FROM viajes
    GROUP BY taxi, vendor_id, pickup, dropoff, pu_location_id, do_location_id,
             trip_distance, fare_amount, total_amount, payment_type
    HAVING count(*) > 1
)
SELECT
    taxi,
    count(*)              AS grupos_duplicados,
    sum(veces - 1)        AS registros_sobrantes,
    max(veces)            AS max_repeticiones
FROM grupos
GROUP BY taxi
ORDER BY taxi DESC;
