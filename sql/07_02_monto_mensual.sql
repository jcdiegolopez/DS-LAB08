-- I2: monto registrado total y por dia calendario (USD nominales).
-- Fuente: viajes_limpios, total_amount. Incluye tarifa, impuestos, peajes,
-- recargos y propina registrada: NO mide utilidad ni ingreso neto del conductor.
WITH mensual AS (
    SELECT taxi, anio_archivo AS anio, mes_archivo AS mes,
           make_date(anio_archivo, mes_archivo, 1) AS mes_fecha,
           count(*) AS viajes, sum(total_amount) AS monto_total,
           avg(total_amount) AS ticket_promedio
    FROM viajes_limpios
    GROUP BY taxi, anio_archivo, mes_archivo
)
SELECT m.taxi, m.anio, m.mes, m.mes_fecha, m.viajes,
       round(m.monto_total, 2) AS monto_total_usd,
       round(m.monto_total / day(last_day(m.mes_fecha)), 2) AS monto_por_dia_usd,
       round(m.ticket_promedio, 2) AS ticket_promedio_usd,
       round(100.0 * (m.monto_total - a.monto_total) / nullif(a.monto_total, 0), 2) AS variacion_interanual_pct
FROM mensual m
LEFT JOIN mensual a ON a.taxi = m.taxi AND a.anio = m.anio - 1 AND a.mes = m.mes
ORDER BY m.mes_fecha, m.taxi;
