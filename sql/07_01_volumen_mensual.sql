-- I1: volumen de viajes validos y participacion de cada taxi por mes.
-- Fuente: viajes_limpios. Usa todos los meses disponibles; los meses ausentes
-- no se convierten en cero. Denominador: dias calendario, incluidos sin viajes.
WITH mensual AS (
    SELECT taxi, anio_archivo AS anio, mes_archivo AS mes,
           make_date(anio_archivo, mes_archivo, 1) AS mes_fecha,
           count(*) AS viajes
    FROM viajes_limpios
    GROUP BY taxi, anio_archivo, mes_archivo
)
SELECT m.*,
       day(last_day(m.mes_fecha)) AS dias_calendario,
       round(m.viajes / day(last_day(m.mes_fecha)), 2) AS viajes_por_dia,
       round(100.0 * m.viajes / sum(m.viajes) OVER (PARTITION BY m.anio, m.mes), 3) AS pct_del_mes,
       round(100.0 * (m.viajes - a.viajes) / nullif(a.viajes, 0), 2) AS variacion_interanual_pct
FROM mensual m
LEFT JOIN mensual a ON a.taxi = m.taxi AND a.anio = m.anio - 1 AND a.mes = m.mes
ORDER BY m.mes_fecha, m.taxi;
