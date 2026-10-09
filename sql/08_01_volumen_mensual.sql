-- 08_01 - Evolucion del volumen mensual y variacion interanual (8.5)
-- Pregunta: como evoluciona la demanda de cada taxi mes a mes en todos los
--           anios descargados y cuanto cambia frente al mismo mes del anio anterior.
-- Fuente:   vista `viajes_limpios`. No nombra anios: funciona con los que haya.
WITH mensual AS (
    SELECT
        taxi,
        year(pickup)                                  AS anio,
        month(pickup)                                 AS mes,
        count(*)                                      AS viajes,
        count(*) / count(DISTINCT pickup::DATE)       AS viajes_por_dia
    FROM viajes_limpios
    GROUP BY taxi, anio, mes
)
SELECT
    m.taxi,
    m.anio,
    m.mes,
    m.viajes,
    round(m.viajes_por_dia, 0)                                         AS viajes_por_dia,
    round(100.0 * (m.viajes - a.viajes) / a.viajes, 1)                 AS var_vs_anio_anterior_pct,
    round(100.0 * m.viajes / sum(m.viajes) OVER (PARTITION BY m.anio, m.mes), 2)
                                                                       AS pct_del_mes
FROM mensual m
LEFT JOIN mensual a
       ON a.taxi = m.taxi AND a.anio = m.anio - 1 AND a.mes = m.mes
ORDER BY m.taxi DESC, m.anio, m.mes;
