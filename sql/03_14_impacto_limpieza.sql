-- 03_14 - Impacto de las reglas de limpieza (3.8: decision tomada)
-- Objetivo: cuantos registros elimina cada regla de la vista `viajes_limpios`
--           y que porcentaje se conserva. Una fila puede violar varias reglas.
-- Fuente:   vistas `viajes` y `viajes_limpios`; reglas R1-R6 de sql/00_vistas.sql.
WITH reglas AS (
    SELECT
        taxi,
        anio_archivo                                                          AS anio,
        count(*)                                                              AS registros,
        count(*) FILTER (WHERE NOT (year(pickup) = anio_archivo
                                AND month(pickup) = mes_archivo))             AS r1_fecha_fuera_de_mes,
        count(*) FILTER (WHERE NOT (duracion_min > 0 AND duracion_min <= 360)) AS r2_duracion,
        count(*) FILTER (WHERE NOT (trip_distance > 0 AND trip_distance <= 200)) AS r3_distancia,
        count(*) FILTER (WHERE NOT (fare_amount > 0 AND total_amount > 0))    AS r4_montos_no_positivos,
        count(*) FILTER (WHERE total_amount > 1000)                           AS r5_total_extremo,
        count(*) FILTER (WHERE duracion_min > 0
                           AND trip_distance / (duracion_min / 60) > 80)      AS r6_velocidad
    FROM viajes
    GROUP BY taxi, anio_archivo
),
limpios AS (
    SELECT taxi, anio_archivo AS anio, count(*) AS conservados
    FROM viajes_limpios
    GROUP BY taxi, anio_archivo
)
SELECT
    r.*,
    l.conservados,
    r.registros - l.conservados                       AS descartados,
    round(100.0 * l.conservados / r.registros, 2)     AS pct_conservado
FROM reglas r
JOIN limpios l USING (taxi, anio)
ORDER BY taxi DESC, anio;
