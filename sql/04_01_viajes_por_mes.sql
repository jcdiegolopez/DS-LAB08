-- 04_01 - Comportamiento temporal: viajes por mes (P1)
-- Pregunta: como cambia la demanda mes a mes y si yellow y green siguen el mismo ritmo.
-- Fuente:   vista `viajes_limpios`.
SELECT
    taxi,
    date_trunc('month', pickup)::DATE                                AS mes,
    count(*)                                                         AS viajes,
    round(count(*) / count(DISTINCT pickup::DATE), 0)                AS viajes_por_dia,
    round(100.0 * count(*) / first_value(count(*)) OVER (PARTITION BY taxi ORDER BY mes), 1)
                                                                     AS indice_vs_primer_mes
FROM viajes_limpios
GROUP BY taxi, mes
ORDER BY taxi DESC, mes;
