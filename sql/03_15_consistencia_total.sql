-- 03_15 - Calidad: el total coincide con la suma de sus componentes? (3.6)
-- Objetivo: medir, por proveedor y tipo de registro, cuantos registros tienen un
--           total_amount distinto de la suma de tarifa, recargos, impuestos,
--           peajes y propina (tolerancia de 1 centavo), y cual es la diferencia
--           mas frecuente. Una diferencia fija revela una regla de registro, no
--           un error aleatorio.
-- Fuente:   vista `viajes`. Componentes nulos = 0. ehail_fee se ignora (siempre nulo).
WITH revisado AS (
    SELECT
        taxi,
        vendor_id,
        CASE WHEN coalesce(payment_type, 0) = 0 THEN 'sin detalle (Flex Fare)'
             ELSE 'taximetro (pago 1-6)' END                         AS tipo_registro,
        round(total_amount
              - (fare_amount + extra + mta_tax + tip_amount + tolls_amount
                 + improvement_surcharge + coalesce(congestion_surcharge, 0)
                 + coalesce(airport_fee, 0) + coalesce(cbd_congestion_fee, 0)), 2) AS diferencia
    FROM viajes
)
SELECT
    taxi,
    vendor_id,
    tipo_registro,
    count(*)                                                          AS registros,
    round(100.0 * count(*) FILTER (WHERE abs(diferencia) > 0.01) / count(*), 2) AS pct_total_no_cuadra,
    mode(diferencia) FILTER (WHERE abs(diferencia) > 0.01)            AS diferencia_mas_frecuente
FROM revisado
GROUP BY taxi, vendor_id, tipo_registro
ORDER BY taxi DESC, vendor_id, tipo_registro DESC;
