-- Join de dimension, agrupacion y ordenamiento de zonas de origen.
SELECT v.taxi, z.borough, z.zona, count(*) AS viajes,
       avg(v.total_amount) AS total_promedio_usd,
       avg(v.duracion_min) AS duracion_promedio_min
FROM viajes_limpios v
LEFT JOIN zonas z ON v.pu_location_id = z.location_id
GROUP BY v.taxi, z.borough, z.zona
ORDER BY viajes DESC, v.taxi, z.borough, z.zona;
