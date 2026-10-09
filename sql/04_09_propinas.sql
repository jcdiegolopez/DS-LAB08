-- 04_09 - Variables de pago: propina como % de la tarifa (P8)
-- Pregunta: cuanto se deja de propina y como cambia con la distancia del viaje.
-- Fuente:   vista `viajes_limpios`, solo pagos con tarjeta (payment_type = 1):
--           el diccionario indica que las propinas en efectivo no se registran.
SELECT
    taxi,
    CASE
        WHEN trip_distance < 1  THEN '1. < 1 mi'
        WHEN trip_distance < 3  THEN '2. 1-3 mi'
        WHEN trip_distance < 7  THEN '3. 3-7 mi'
        WHEN trip_distance < 15 THEN '4. 7-15 mi'
        ELSE                         '5. 15+ mi'
    END                                                             AS distancia,
    count(*)                                                        AS viajes_tarjeta,
    round(100.0 * count(*) FILTER (WHERE tip_amount = 0) / count(*), 1) AS pct_sin_propina,
    round(approx_quantile(100.0 * tip_amount / fare_amount, 0.5), 1) AS propina_pct_mediana,
    round(avg(tip_amount), 2)                                       AS propina_promedio
FROM viajes_limpios
WHERE payment_type = 1
GROUP BY taxi, distancia
ORDER BY taxi DESC, distancia;
