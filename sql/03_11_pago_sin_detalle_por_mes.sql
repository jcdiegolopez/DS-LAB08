-- 03_11 - Registros "Flex Fare" / sin detalle por mes (3.6)
-- Objetivo: ver si los registros con payment_type 0 (yellow) o nulo (green) y
--           sin pasajeros ni ratecode son un problema puntual o creciente.
-- Fuente:   vista `viajes`.
SELECT
    taxi,
    anio_archivo                                                    AS anio,
    mes_archivo                                                     AS mes,
    count(*)                                                        AS registros,
    count(*) FILTER (WHERE coalesce(payment_type, 0) = 0)           AS sin_detalle,
    round(100.0 * count(*) FILTER (WHERE coalesce(payment_type, 0) = 0) / count(*), 1)
                                                                    AS pct_sin_detalle,
    round(avg(tip_amount) FILTER (WHERE coalesce(payment_type, 0) = 0), 2)
                                                                    AS propina_prom_sin_detalle,
    round(avg(tip_amount) FILTER (WHERE payment_type = 1), 2)       AS propina_prom_tarjeta
FROM viajes
GROUP BY taxi, anio_archivo, mes_archivo
ORDER BY taxi DESC, anio, mes;
