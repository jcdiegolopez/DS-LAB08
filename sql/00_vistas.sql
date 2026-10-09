-- =============================================================================
-- 00_vistas.sql - Vistas sobre los archivos Parquet (sin importar datos)
-- =============================================================================
-- Todas las consultas de los ejercicios 3, 4 y 8 se escriben contra estas vistas.
-- Una vista de DuckDB no copia datos: cada consulta vuelve a leer los Parquet de
-- data/raw/, por lo que un archivo nuevo (otro mes u otro anio) entra solo.
--
-- Decisiones:
--   * Rutas con comodin (*/*.parquet): no se nombra ningun archivo ni anio.
--   * union_by_name = true: los esquemas cambian entre archivos. 2025 agrega
--     cbd_congestion_fee y junio-agosto 2026 agregan request_source. Sin esta
--     opcion DuckDB toma el esquema del primer archivo y esas columnas
--     desaparecen sin aviso (ver sql/03_05_esquema_por_archivo.sql).
--   * filename = true: conserva el archivo de origen para saber a que mes
--     pertenece cada registro y detectar fechas fuera de su archivo.
--   * Yellow (tpep_*) y Green (lpep_*) se unifican en `viajes` con nombres de
--     columna en minuscula y una columna `taxi`.
--   * Rutas relativas a la raiz del repositorio (/workspace en el contenedor).
--   * Filtro opcional de anios: si la sesion define la variable `anios`
--     (SET VARIABLE anios = [2026]), las vistas solo leen esos anios; si no la
--     define, leen todo lo descargado. DuckDB aplica el filtro sobre `filename`
--     antes de abrir los archivos, asi que los demas anios ni se leen.
--     scripts/run_sql.py la define con la opcion --anios.

CREATE OR REPLACE MACRO anio_de_archivo(archivo) AS
    CAST(regexp_extract(archivo, '(\d{4})-\d{2}\.parquet$', 1) AS INTEGER);

CREATE OR REPLACE MACRO mes_de_archivo(archivo) AS
    CAST(regexp_extract(archivo, '\d{4}-(\d{2})\.parquet$', 1) AS INTEGER);

CREATE OR REPLACE MACRO anio_seleccionado(archivo) AS
    getvariable('anios') IS NULL
    OR list_contains(getvariable('anios'), anio_de_archivo(archivo));

CREATE OR REPLACE VIEW yellow_raw AS
SELECT *
FROM read_parquet('data/raw/yellow/*/*.parquet', union_by_name = true, filename = true)
WHERE anio_seleccionado(filename);

CREATE OR REPLACE VIEW green_raw AS
SELECT *
FROM read_parquet('data/raw/green/*/*.parquet', union_by_name = true, filename = true)
WHERE anio_seleccionado(filename);

-- Zonas de la TLC (scripts/download_zones.py): LocationID -> borough y zona.
CREATE OR REPLACE VIEW zonas AS
SELECT
    LocationID      AS location_id,
    Borough         AS borough,
    Zone            AS zona,
    service_zone
FROM read_csv('data/raw/zones/taxi_zone_lookup.csv', header = true);

-- Vista unificada: una fila por viaje, sin filtros.
CREATE OR REPLACE VIEW viajes AS
WITH unidos AS (
    SELECT
        'yellow'                AS taxi,
        filename                AS archivo,
        VendorID                AS vendor_id,
        tpep_pickup_datetime    AS pickup,
        tpep_dropoff_datetime   AS dropoff,
        passenger_count,
        trip_distance,
        RatecodeID              AS ratecode_id,
        store_and_fwd_flag,
        PULocationID            AS pu_location_id,
        DOLocationID            AS do_location_id,
        payment_type,
        fare_amount,
        extra,
        mta_tax,
        tip_amount,
        tolls_amount,
        improvement_surcharge,
        total_amount,
        congestion_surcharge,
        Airport_fee             AS airport_fee,
        cbd_congestion_fee,
        NULL::BIGINT            AS trip_type,
        request_source
    FROM yellow_raw
    UNION ALL
    SELECT
        'green',
        filename,
        VendorID,
        lpep_pickup_datetime,
        lpep_dropoff_datetime,
        passenger_count,
        trip_distance,
        RatecodeID,
        store_and_fwd_flag,
        PULocationID,
        DOLocationID,
        payment_type,
        fare_amount,
        extra,
        mta_tax,
        tip_amount,
        tolls_amount,
        improvement_surcharge,
        total_amount,
        congestion_surcharge,
        NULL::DOUBLE,           -- los archivos green no traen airport_fee
        cbd_congestion_fee,
        trip_type,
        request_source
    FROM green_raw
)
SELECT
    *,
    -- Anio y mes del archivo que trae el registro (yellow_tripdata_2026-01.parquet).
    anio_de_archivo(archivo)                                                AS anio_archivo,
    mes_de_archivo(archivo)                                                 AS mes_archivo,
    date_diff('second', pickup, dropoff) / 60.0                             AS duracion_min
FROM unidos;

-- Vista limpia: aplica las reglas decididas en el Ejercicio 3 (docs/ej3-consultas.md).
-- Se usa en el EDA (Ej. 4) y en la evolucion (Ej. 8). Los registros descartados
-- se cuantifican en sql/03_14_impacto_limpieza.sql.
CREATE OR REPLACE VIEW viajes_limpios AS
SELECT *
FROM viajes
WHERE year(pickup) = anio_archivo            -- R1: fecha dentro del mes de su archivo
  AND month(pickup) = mes_archivo
  AND duracion_min > 0                       -- R2: duracion positiva y menor a 6 h
  AND duracion_min <= 360
  AND trip_distance > 0                      -- R3: distancia positiva y plausible
  AND trip_distance <= 200
  AND fare_amount > 0                        -- R4: tarifa y total positivos
  AND total_amount > 0
  AND total_amount <= 1000                   -- R5: total menor a 1000 USD
  AND trip_distance / (duracion_min / 60) <= 80;  -- R6: velocidad media <= 80 mph
