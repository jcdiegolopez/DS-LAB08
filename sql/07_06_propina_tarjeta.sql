-- I6: propina registrada con tarjeta, como porcentaje de fare_amount.
-- Fuente: viajes_limpios. Solo payment_type=1; las propinas en efectivo no
-- aparecen en los datos TLC. Mantiene ceros, excluye nulos/negativos del calculo
-- de propina y reporta su numero. Usa periodo comun y medianas aproximadas.
WITH cobertura AS (
    SELECT DISTINCT taxi, anio_archivo AS anio, mes_archivo AS mes FROM viajes
),
meses_comunes AS (
    SELECT mes FROM cobertura GROUP BY mes
    HAVING count(*) = (SELECT count(*) FROM (SELECT DISTINCT taxi, anio FROM cobertura))
),
periodo AS (
    SELECT string_agg(lpad(mes::VARCHAR, 2, '0'), ', ' ORDER BY mes) AS meses_comunes
    FROM meses_comunes
)
SELECT taxi, anio_archivo AS anio, p.meses_comunes,
       count(*) AS viajes_tarjeta,
       count(*) FILTER (WHERE tip_amount >= 0) AS viajes_propina_valida,
       count(*) FILTER (WHERE tip_amount IS NULL OR tip_amount < 0) AS propinas_excluidas,
       round(avg(tip_amount) FILTER (WHERE tip_amount >= 0), 2) AS propina_promedio_usd,
       round(approx_quantile(100.0 * tip_amount / fare_amount, 0.5)
             FILTER (WHERE tip_amount >= 0), 2) AS propina_pct_mediana,
       round(100.0 * count(*) FILTER (WHERE tip_amount = 0)
             / nullif(count(*) FILTER (WHERE tip_amount >= 0), 0), 2) AS pct_sin_propina
FROM viajes_limpios CROSS JOIN periodo p
WHERE mes_archivo IN (SELECT mes FROM meses_comunes) AND payment_type = 1
GROUP BY taxi, anio_archivo, p.meses_comunes
ORDER BY anio, taxi;
