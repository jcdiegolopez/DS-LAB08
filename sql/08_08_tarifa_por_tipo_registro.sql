-- 08_08 - El aumento de la tarifa promedio: precio o mezcla? (8.6)
-- Pregunta: la tarifa promedio sube porque el taximetro cobra mas o porque
--           crecen los registros Flex Fare (payment_type 0 / nulo), que tienen
--           otra forma de calcular la tarifa?
-- Fuente:   vista `viajes_limpios`, periodo comun de todos los anios.
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
    year(pickup)                                                       AS anio,
    CASE WHEN coalesce(payment_type, 0) = 0 THEN 'sin detalle (Flex Fare)'
         ELSE 'taximetro (pago 1-5)' END                               AS tipo_registro,
    count(*)                                                           AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY taxi, year(pickup)), 1) AS pct_del_anio,
    round(avg(fare_amount), 2)                                         AS tarifa_promedio,
    round(approx_quantile(fare_amount, 0.5), 2)                        AS tarifa_mediana,
    round(approx_quantile(trip_distance, 0.5), 2)                      AS distancia_mediana,
    round(avg(fare_amount / trip_distance) FILTER (WHERE trip_distance >= 1), 2) AS tarifa_por_milla
FROM viajes_limpios
WHERE month(pickup) IN (SELECT mes FROM periodo_comun)
GROUP BY taxi, anio, tipo_registro
ORDER BY taxi DESC, anio, tipo_registro DESC;
