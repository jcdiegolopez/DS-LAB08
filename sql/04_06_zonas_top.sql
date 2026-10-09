-- 04_06 - Diferencias yellow vs green: zonas de origen mas frecuentes (P5)
-- Pregunta: cuales son las 10 zonas donde mas se toma cada tipo de taxi.
-- Fuente:   vistas `viajes_limpios` y `zonas`.
WITH por_zona AS (
    SELECT
        v.taxi,
        z.borough,
        z.zona,
        count(*)                                                           AS viajes,
        round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY v.taxi), 2) AS pct_del_taxi,
        row_number() OVER (PARTITION BY v.taxi ORDER BY count(*) DESC)     AS puesto
    FROM viajes_limpios v
    JOIN zonas z ON z.location_id = v.pu_location_id
    GROUP BY v.taxi, z.borough, z.zona
)
SELECT taxi, puesto, borough, zona, viajes, pct_del_taxi
FROM por_zona
WHERE puesto <= 10
ORDER BY taxi DESC, puesto;
