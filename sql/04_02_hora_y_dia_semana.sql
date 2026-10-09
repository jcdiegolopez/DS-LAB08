-- 04_02 - Comportamiento temporal: hora del dia y dia de la semana (P2)
-- Pregunta: en que horas y dias se concentra la demanda de cada tipo de taxi.
-- Fuente:   vista `viajes_limpios`. Se usa el % del total de cada taxi para
--           comparar yellow y green aunque sus volumenes sean muy distintos.
SELECT
    taxi,
    isodow(pickup)                                                    AS dia_semana,  -- 1 = lunes
    hour(pickup)                                                      AS hora,
    count(*)                                                          AS viajes,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY taxi), 3) AS pct_del_taxi
FROM viajes_limpios
GROUP BY taxi, dia_semana, hora
ORDER BY taxi DESC, dia_semana, hora;
