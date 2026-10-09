-- Cuantiles exactos, mas exigentes en memoria que una cuenta o un promedio.
SELECT taxi, anio_archivo, count(*) AS viajes,
       quantile_cont(total_amount, [0.25, 0.5, 0.75, 0.95]) AS cuantiles_total_usd,
       quantile_cont(trip_distance, [0.25, 0.5, 0.75, 0.95]) AS cuantiles_distancia_millas
FROM viajes_limpios
GROUP BY taxi, anio_archivo
ORDER BY taxi, anio_archivo;
