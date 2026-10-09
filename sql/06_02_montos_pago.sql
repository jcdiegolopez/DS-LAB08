-- Agrupacion con promedios y sumas monetarias; exige leer varias columnas.
SELECT taxi, payment_type, count(*) AS viajes,
       avg(total_amount) AS total_promedio_usd,
       sum(total_amount) AS importe_registrado_usd,
       avg(tip_amount) AS propina_promedio_usd,
       avg(trip_distance) AS distancia_promedio_millas
FROM viajes_limpios
GROUP BY taxi, payment_type
ORDER BY taxi, payment_type;
