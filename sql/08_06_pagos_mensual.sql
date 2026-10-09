-- 08_06 - Evolucion de la forma de pago (8.6)
-- Pregunta: como cambia la proporcion de tarjeta, efectivo y registros sin
--           detalle (Flex Fare) a lo largo de los anios.
-- Fuente:   vista `viajes_limpios`.
SELECT
    taxi,
    date_trunc('month', pickup)::DATE                                   AS mes,
    count(*)                                                            AS viajes,
    round(100.0 * count(*) FILTER (WHERE payment_type = 1) / count(*), 1) AS pct_tarjeta,
    round(100.0 * count(*) FILTER (WHERE payment_type = 2) / count(*), 1) AS pct_efectivo,
    round(100.0 * count(*) FILTER (WHERE coalesce(payment_type, 0) = 0) / count(*), 1) AS pct_sin_detalle,
    round(100.0 * count(*) FILTER (WHERE payment_type IN (3, 4)) / count(*), 2) AS pct_sin_cargo_o_disputa
FROM viajes_limpios
GROUP BY taxi, mes
ORDER BY taxi DESC, mes;
