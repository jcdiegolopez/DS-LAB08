-- 03_10 - Calidad: nulos y codigos fuera del diccionario (3.6)
-- Objetivo: medir pasajeros nulos o cero, RatecodeID desconocido, payment_type
--           0 o nulo y zonas desconocidas, por tipo de taxi y anio.
-- Fuente:   vista `viajes`. Codigos segun el diccionario de datos de la TLC.
SELECT
    taxi,
    anio_archivo                                                     AS anio,
    count(*)                                                         AS registros,
    round(100.0 * count(*) FILTER (WHERE passenger_count IS NULL) / count(*), 2) AS pct_pasajeros_nulo,
    round(100.0 * count(*) FILTER (WHERE passenger_count = 0) / count(*), 2)     AS pct_pasajeros_cero,
    round(100.0 * count(*) FILTER (WHERE ratecode_id IS NULL) / count(*), 2)     AS pct_ratecode_nulo,
    round(100.0 * count(*) FILTER (WHERE ratecode_id = 99) / count(*), 2)        AS pct_ratecode_99,
    round(100.0 * count(*) FILTER (WHERE payment_type = 0) / count(*), 2)        AS pct_pago_0,
    round(100.0 * count(*) FILTER (WHERE payment_type IS NULL) / count(*), 2)    AS pct_pago_nulo,
    round(100.0 * count(*) FILTER (WHERE pu_location_id IN (264, 265)) / count(*), 2) AS pct_zona_desconocida,
    -- Los nulos de pasajeros, ratecode y store_and_fwd_flag van en el mismo registro:
    count(*) FILTER (WHERE passenger_count IS NULL
                       AND ratecode_id IS NULL
                       AND store_and_fwd_flag IS NULL)               AS nulos_en_bloque
FROM viajes
GROUP BY taxi, anio_archivo
ORDER BY taxi DESC, anio;
