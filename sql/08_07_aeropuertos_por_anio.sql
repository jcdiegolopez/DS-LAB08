-- 08_07 - Peso de los viajes de aeropuerto por anio (8.6)
-- Pregunta: cambia la mezcla de viajes urbanos y de aeropuerto entre anios?
-- Fuente:   vista `viajes_limpios`, yellow, periodo comun de todos los anios.
--           Zonas 1 (EWR), 132 (JFK) y 138 (LaGuardia).
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
    year(pickup)                                                         AS anio,
    count(*)                                                             AS viajes,
    round(100.0 * count(*) FILTER (WHERE pu_location_id IN (1, 132, 138)
                                      OR do_location_id IN (1, 132, 138)) / count(*), 2) AS pct_aeropuerto,
    round(100.0 * sum(total_amount) FILTER (WHERE pu_location_id IN (1, 132, 138)
                                              OR do_location_id IN (1, 132, 138))
          / sum(total_amount), 2)                                        AS pct_ingresos_aeropuerto,
    round(approx_quantile(total_amount, 0.5) FILTER (WHERE pu_location_id = 132 OR do_location_id = 132), 2)
                                                                         AS total_mediano_jfk
FROM viajes_limpios
WHERE taxi = 'yellow'
  AND month(pickup) IN (SELECT mes FROM periodo_comun)
GROUP BY anio
ORDER BY anio;
