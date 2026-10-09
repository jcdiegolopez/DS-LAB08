-- 04_11 - Valores atipicos que sobreviven a la limpieza (P10)
-- Pregunta: cuantos viajes quedan fuera de los limites de Tukey (Q3 + 1.5 IQR)
--           en distancia, duracion, total y propina, aun despues de limpiar.
-- Fuente:   vista `viajes_limpios`.
WITH limites AS (
    SELECT
        taxi,
        approx_quantile(trip_distance, 0.25) AS d_q1, approx_quantile(trip_distance, 0.75) AS d_q3,
        approx_quantile(duracion_min, 0.25)  AS m_q1, approx_quantile(duracion_min, 0.75)  AS m_q3,
        approx_quantile(total_amount, 0.25)  AS t_q1, approx_quantile(total_amount, 0.75)  AS t_q3,
        approx_quantile(tip_amount, 0.25)    AS p_q1, approx_quantile(tip_amount, 0.75)    AS p_q3
    FROM viajes_limpios
    GROUP BY taxi
)
SELECT
    v.taxi,
    count(*)                                                                      AS viajes,
    round(any_value(d_q3 + 1.5 * (d_q3 - d_q1)), 2)                               AS limite_distancia,
    round(100.0 * count(*) FILTER (WHERE trip_distance > d_q3 + 1.5 * (d_q3 - d_q1)) / count(*), 2) AS pct_atip_distancia,
    round(any_value(m_q3 + 1.5 * (m_q3 - m_q1)), 1)                               AS limite_duracion,
    round(100.0 * count(*) FILTER (WHERE duracion_min > m_q3 + 1.5 * (m_q3 - m_q1)) / count(*), 2)  AS pct_atip_duracion,
    round(any_value(t_q3 + 1.5 * (t_q3 - t_q1)), 2)                               AS limite_total,
    round(100.0 * count(*) FILTER (WHERE total_amount > t_q3 + 1.5 * (t_q3 - t_q1)) / count(*), 2)  AS pct_atip_total,
    round(100.0 * count(*) FILTER (WHERE tip_amount > fare_amount) / count(*), 3) AS pct_propina_mayor_tarifa
FROM viajes_limpios v
JOIN limites l USING (taxi)
GROUP BY v.taxi
ORDER BY v.taxi DESC;
