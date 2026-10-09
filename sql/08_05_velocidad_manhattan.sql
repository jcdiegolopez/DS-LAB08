-- 08_05 - Velocidad dentro de Manhattan antes y despues del cargo (8.6)
-- Pregunta: los viajes dentro de Manhattan van mas rapido desde que existe el
--           cargo por congestion (enero 2025)?
-- Fuente:   vistas `viajes_limpios` y `zonas`; yellow, origen y destino en
--           Manhattan "Yellow Zone" (sur de la calle 96), lunes a viernes de 7 a 19 h.
-- Es una comparacion descriptiva: otros factores (clima, obras) tambien influyen.
SELECT
    year(v.pickup)                                                     AS anio,
    month(v.pickup)                                                    AS mes,
    count(*)                                                           AS viajes,
    round(approx_quantile(v.trip_distance / (v.duracion_min / 60), 0.5), 2) AS velocidad_mediana_mph,
    round(approx_quantile(v.duracion_min / v.trip_distance, 0.5), 2)   AS minutos_por_milla,
    round(approx_quantile(v.duracion_min, 0.5), 1)                     AS duracion_mediana_min
FROM viajes_limpios v
JOIN zonas zo ON zo.location_id = v.pu_location_id
JOIN zonas zd ON zd.location_id = v.do_location_id
WHERE v.taxi = 'yellow'
  AND zo.borough = 'Manhattan' AND zo.service_zone = 'Yellow Zone'
  AND zd.borough = 'Manhattan' AND zd.service_zone = 'Yellow Zone'
  AND isodow(v.pickup) <= 5
  AND hour(v.pickup) BETWEEN 7 AND 18
GROUP BY anio, mes
ORDER BY anio, mes;
