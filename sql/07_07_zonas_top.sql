-- I7: cinco zonas de recogida con mas viajes por taxi/anio en periodo comun.
-- Fuente: viajes_limpios + zonas; LEFT JOIN conserva IDs sin catalogo.
-- Ranking y porcentaje incluyen zonas desconocidas, que permanecen visibles.
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
),
conteo AS (
    SELECT v.taxi, v.anio_archivo AS anio, v.pu_location_id AS location_id,
           coalesce(z.borough, 'Sin catalogo') AS borough,
           coalesce(z.zona, 'Sin catalogo') AS zona, count(*) AS viajes
    FROM viajes_limpios v LEFT JOIN zonas z ON v.pu_location_id = z.location_id
    WHERE v.mes_archivo IN (SELECT mes FROM meses_comunes)
    GROUP BY v.taxi, v.anio_archivo, v.pu_location_id, z.borough, z.zona
),
ranking AS (
    SELECT *, row_number() OVER (PARTITION BY taxi, anio ORDER BY viajes DESC, location_id NULLS LAST) AS rango,
           round(100.0 * viajes / sum(viajes) OVER (PARTITION BY taxi, anio), 3) AS pct_viajes
    FROM conteo
)
SELECT r.*, p.meses_comunes
FROM ranking r CROSS JOIN periodo p WHERE rango <= 5
ORDER BY anio, taxi, rango;
