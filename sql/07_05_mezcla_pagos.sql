-- I5: distribucion mensual de pagos. Fuente: viajes_limpios.
-- NULL/0 se muestran como sin detalle; otros codigos inesperados se conservan.
-- El porcentaje usa TODOS los viajes validos del taxi/mes como denominador.
WITH pagos AS (
    SELECT taxi, anio_archivo AS anio, mes_archivo AS mes,
           make_date(anio_archivo, mes_archivo, 1) AS mes_fecha,
           CASE
               WHEN coalesce(payment_type, 0) = 0 THEN 'Sin detalle (NULL/0)'
               WHEN payment_type = 1 THEN 'Tarjeta'
               WHEN payment_type = 2 THEN 'Efectivo'
               WHEN payment_type = 3 THEN 'Sin cargo'
               WHEN payment_type = 4 THEN 'Disputa'
               WHEN payment_type = 5 THEN 'Desconocido (5)'
               WHEN payment_type = 6 THEN 'Viaje anulado (6)'
               ELSE 'Otro codigo'
           END AS metodo_pago,
           count(*) AS viajes
    FROM viajes_limpios
    GROUP BY taxi, anio_archivo, mes_archivo, metodo_pago
)
SELECT *, round(100.0 * viajes / sum(viajes) OVER (PARTITION BY taxi, anio, mes), 3) AS pct_viajes
FROM pagos
ORDER BY mes_fecha, taxi, metodo_pago;
