-- I4: distancia, duracion y velocidad medianas por taxi/anio en periodo comun.
-- Fuente: viajes_limpios. approx_quantile evita ordenar millones de filas.
-- La mediana de velocidades individuales no equivale al cociente de medianas.
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
SELECT taxi, anio_archivo AS anio, p.meses_comunes, count(*) AS viajes,
       round(approx_quantile(trip_distance, 0.5), 2) AS distancia_mediana_mi,
       round(approx_quantile(duracion_min, 0.5), 2) AS duracion_mediana_min,
       round(approx_quantile(trip_distance / (duracion_min / 60.0), 0.5), 2) AS velocidad_mediana_mph
FROM viajes_limpios CROSS JOIN periodo p
WHERE mes_archivo IN (SELECT mes FROM meses_comunes)
GROUP BY taxi, anio_archivo, p.meses_comunes
ORDER BY anio, taxi;
