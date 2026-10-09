-- Volumen por mes y servicio; agrega filas tras aplicar R1-R6.
SELECT taxi, anio_archivo, mes_archivo, count(*) AS viajes
FROM viajes_limpios
GROUP BY taxi, anio_archivo, mes_archivo
ORDER BY taxi, anio_archivo, mes_archivo;
