-- I8: porcentaje mensual conservado tras R1-R6 (sql/00_vistas.sql).
-- Fuente: viajes y viajes_limpios. Mide cobertura de los indicadores respecto
-- al archivo original; los descartes no son necesariamente viajes inexistentes.
WITH crudos AS (
    SELECT taxi, anio_archivo AS anio, mes_archivo AS mes, count(*) AS registros_originales
    FROM viajes GROUP BY taxi, anio_archivo, mes_archivo
),
limpios AS (
    SELECT taxi, anio_archivo AS anio, mes_archivo AS mes, count(*) AS viajes_conservados
    FROM viajes_limpios GROUP BY taxi, anio_archivo, mes_archivo
)
SELECT c.taxi, c.anio, c.mes, make_date(c.anio, c.mes, 1) AS mes_fecha,
       c.registros_originales, coalesce(l.viajes_conservados, 0) AS viajes_conservados,
       c.registros_originales - coalesce(l.viajes_conservados, 0) AS registros_descartados,
       round(100.0 * coalesce(l.viajes_conservados, 0) / c.registros_originales, 3) AS pct_conservado
FROM crudos c LEFT JOIN limpios l USING (taxi, anio, mes)
ORDER BY mes_fecha, taxi;
