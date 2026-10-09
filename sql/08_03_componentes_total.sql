-- 08_03 - Que explica el cambio en el total cobrado (8.5, 8.6)
-- Pregunta: el total por viaje sube por la tarifa o por cargos nuevos?
-- Fuente:   vista `viajes_limpios`, periodo comun de todos los anios.
--           Promedio por viaje de cada componente del total_amount.
WITH meses_por_anio AS (
    SELECT DISTINCT year(pickup) AS anio, month(pickup) AS mes FROM viajes_limpios
),
periodo_comun AS (
    SELECT mes
    FROM meses_por_anio
    GROUP BY mes
    HAVING count(*) = (SELECT count(DISTINCT anio) FROM meses_por_anio)
)
SELECT
    taxi,
    year(pickup)                                 AS anio,
    round(avg(fare_amount), 2)                   AS tarifa,
    round(avg(extra), 2)                         AS extra,
    round(avg(mta_tax), 2)                       AS mta_tax,
    round(avg(improvement_surcharge), 2)         AS improvement,
    round(avg(coalesce(congestion_surcharge, 0)), 2) AS congestion_surcharge,
    round(avg(coalesce(airport_fee, 0)), 2)      AS airport_fee,
    round(avg(coalesce(cbd_congestion_fee, 0)), 2) AS cbd_congestion_fee,
    round(avg(tolls_amount), 2)                  AS peajes,
    round(avg(tip_amount), 2)                    AS propina,
    round(avg(total_amount), 2)                  AS total,
    round(100.0 * avg(total_amount - tip_amount - fare_amount) / avg(total_amount), 1)
                                                 AS pct_cargos_en_total
FROM viajes_limpios
WHERE month(pickup) IN (SELECT mes FROM periodo_comun)
GROUP BY taxi, anio
ORDER BY taxi DESC, anio;
