-- 03_12 - Origen de las tarifas negativas (3.6)
-- Objetivo: identificar que proveedor y tipo de pago generan tarifas negativas
--           y cuantas son la anulacion exacta de otro viaje positivo.
-- Fuente:   vista `viajes`.
WITH negativos AS (
    SELECT taxi, vendor_id, payment_type, pickup, dropoff,
           pu_location_id, do_location_id, fare_amount
    FROM viajes
    WHERE fare_amount < 0
),
positivos AS (
    SELECT taxi, vendor_id, pickup, dropoff, pu_location_id, do_location_id,
           -fare_amount AS fare_amount
    FROM viajes
    WHERE fare_amount > 0
),
con_espejo AS (
    SELECT DISTINCT n.*
    FROM negativos n
    SEMI JOIN positivos p
      USING (taxi, vendor_id, pickup, dropoff, pu_location_id, do_location_id, fare_amount)
)
SELECT
    n.taxi,
    n.vendor_id,
    n.payment_type,
    count(*)                                                       AS tarifas_negativas,
    round(100.0 * count(*) / sum(count(*)) OVER (), 2)             AS pct_de_negativas,
    (SELECT count(*) FROM con_espejo e
      WHERE e.taxi = n.taxi AND e.vendor_id = n.vendor_id
        AND e.payment_type IS NOT DISTINCT FROM n.payment_type)    AS con_viaje_espejo
FROM negativos n
GROUP BY n.taxi, n.vendor_id, n.payment_type
ORDER BY tarifas_negativas DESC;
