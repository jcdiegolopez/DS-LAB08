-- I3: ticket promedio por taxi/anio en meses disponibles en TODAS las
-- combinaciones taxi-anio. Fuente: viajes (cobertura) y viajes_limpios (metricas).
-- No compara el total de un anio completo con un anio parcial.
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
),
dias AS (
    SELECT a.anio, sum(day(last_day(make_date(a.anio, m.mes, 1)))) AS dias_calendario
    FROM (SELECT DISTINCT anio FROM cobertura) a CROSS JOIN meses_comunes m
    GROUP BY a.anio
),
resumen AS (
    SELECT taxi, anio_archivo AS anio, count(*) AS viajes,
           sum(total_amount) AS monto_total, avg(total_amount) AS ticket_promedio,
           avg(fare_amount) AS tarifa_promedio
    FROM viajes_limpios WHERE mes_archivo IN (SELECT mes FROM meses_comunes)
    GROUP BY taxi, anio_archivo
)
SELECT r.taxi, r.anio, p.meses_comunes, d.dias_calendario, r.viajes,
       round(r.viajes / d.dias_calendario, 2) AS viajes_por_dia,
       round(r.monto_total, 2) AS monto_total_usd,
       round(r.ticket_promedio, 2) AS ticket_promedio_usd,
       round(r.tarifa_promedio, 2) AS tarifa_promedio_usd,
       round(100.0 * (r.ticket_promedio - a.ticket_promedio) / nullif(a.ticket_promedio, 0), 2) AS variacion_ticket_pct,
       round(100.0 * (r.viajes - a.viajes) / nullif(a.viajes, 0), 2) AS variacion_viajes_pct
FROM resumen r CROSS JOIN periodo p JOIN dias d USING (anio)
LEFT JOIN resumen a ON a.taxi = r.taxi AND a.anio = r.anio - 1
ORDER BY r.anio, r.taxi;
