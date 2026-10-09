-- 04_08 - Variables de pago: metodo de pago (P7)
-- Pregunta: como pagan los pasajeros de cada tipo de taxi.
-- Fuente:   vista `viajes_limpios`. Codigos del diccionario de la TLC; el 0 de
--           yellow y el nulo de green son registros sin detalle (ver Ej. 3).
SELECT
    taxi,
    CASE coalesce(payment_type, 0)
        WHEN 0 THEN '0/nulo - sin detalle (Flex Fare)'
        WHEN 1 THEN '1 - tarjeta'
        WHEN 2 THEN '2 - efectivo'
        WHEN 3 THEN '3 - sin cargo'
        WHEN 4 THEN '4 - disputa'
        WHEN 5 THEN '5 - desconocido'
        WHEN 6 THEN '6 - anulado'
    END                                                            AS metodo_pago,
    count(*)                                                       AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY taxi), 2) AS pct_del_taxi,
    round(avg(total_amount), 2)                                    AS total_promedio,
    round(avg(tip_amount), 2)                                      AS propina_promedio
FROM viajes_limpios
GROUP BY taxi, metodo_pago
ORDER BY taxi DESC, viajes DESC;
