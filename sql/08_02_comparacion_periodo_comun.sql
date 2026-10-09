-- 08_02 - Comparacion entre anios en el periodo comun (8.5, 8.6)
-- Pregunta: como cambio el viaje tipico entre anios (volumen, distancia,
--           duracion, velocidad, tarifa, total y forma de pago).
-- Fuente:   vista `viajes_limpios`.
-- El ultimo anio esta incompleto (la TLC publica con atraso). Para no comparar
-- 12 meses contra 8, solo se usan los meses presentes en todos los anios; el
-- periodo comun se calcula a partir de los datos, no se escribe a mano.
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
    year(pickup)                                                        AS anio,
    min(month(pickup)) || '-' || max(month(pickup))                     AS meses,
    count(*)                                                            AS viajes,
    round(count(*) / count(DISTINCT pickup::DATE), 0)                   AS viajes_por_dia,
    round(approx_quantile(trip_distance, 0.5), 2)                       AS distancia_mediana,
    round(approx_quantile(duracion_min, 0.5), 1)                        AS duracion_mediana_min,
    round(approx_quantile(trip_distance / (duracion_min / 60), 0.5), 1) AS velocidad_mediana_mph,
    round(avg(fare_amount), 2)                                          AS tarifa_promedio,
    round(avg(total_amount), 2)                                         AS total_promedio,
    round(avg(fare_amount / trip_distance) FILTER (WHERE trip_distance >= 1), 2) AS tarifa_por_milla,
    round(100.0 * count(*) FILTER (WHERE payment_type = 1) / count(*), 1)  AS pct_tarjeta,
    round(100.0 * count(*) FILTER (WHERE payment_type = 2) / count(*), 1)  AS pct_efectivo,
    round(100.0 * count(*) FILTER (WHERE coalesce(payment_type, 0) = 0) / count(*), 1) AS pct_sin_detalle,
    round(approx_quantile(100.0 * tip_amount / fare_amount, 0.5)
          FILTER (WHERE payment_type = 1), 1)                           AS propina_pct_mediana_tarjeta
FROM viajes_limpios
WHERE month(pickup) IN (SELECT mes FROM periodo_comun)
GROUP BY taxi, anio
ORDER BY taxi DESC, anio;
