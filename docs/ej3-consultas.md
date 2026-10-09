# Ejercicio 3 - Consultas directas sobre archivos Parquet

Todas las consultas leen los archivos Parquet de `data/raw/` **sin importarlos a
una tabla**. Estan en `sql/03_*.sql`, una consulta por archivo, y se ejecutan con:

```bash
docker compose exec lab python scripts/run_sql.py sql/03_*.sql --anios 2026 --csv docs/resultados/2026
```

El ejercicio se resolvio sobre **2026** (enero-agosto, el conjunto inicial del
laboratorio). Los resultados completos de cada consulta estan en
`docs/resultados/2026/<consulta>.csv`, y los mismos archivos ejecutados sobre
2024-2026 en `docs/resultados/2024-2026/` (ver Ejercicio 8.3). El notebook
`notebooks/analisis_exploratorio.ipynb` ejecuta los mismos `.sql`.

## Punto de partida: las vistas (`sql/00_vistas.sql`)

Antes de cada consulta se cargan unas vistas. Una vista de DuckDB no copia datos:
guarda la consulta, y cada vez que se usa vuelve a leer los Parquet.

| Vista | Que es |
|---|---|
| `yellow_raw`, `green_raw` | `read_parquet('data/raw/<tipo>/*/*.parquet', union_by_name = true, filename = true)` |
| `viajes` | yellow y green unidos con nombres de columna comunes (`pickup`, `dropoff`, `pu_location_id`...), mas `taxi`, `anio_archivo`, `mes_archivo` y `duracion_min` |
| `viajes_limpios` | `viajes` con las reglas de limpieza R1-R6 decididas en este ejercicio |
| `zonas` | `taxi_zone_lookup.csv` de la TLC (`scripts/download_zones.py`) |

Decisiones de diseno y por que:

- **Comodines en la ruta** (`*/*.parquet`): ninguna consulta nombra un archivo ni
  un anio. Un mes o un anio nuevo entra solo.
- **`union_by_name = true`**: el esquema cambia entre archivos (ver 3.3). Sin
  esta opcion DuckDB usa el esquema del primer archivo que lee y las columnas
  nuevas *desaparecen sin error*: `SELECT count(request_source) FROM
  read_parquet('data/raw/yellow/2026/*.parquet')` falla con `Binder Error:
  Referenced column "request_source" not found`, aunque la columna existe en
  junio-agosto.
- **`filename = true`**: cada fila sabe de que archivo viene. Asi se detectan
  fechas que no corresponden a su mes y se puede filtrar por anio.
- **Variable `anios`**: si la sesion hace `SET VARIABLE anios = [2026]` (el
  script lo hace con `--anios 2026`), las vistas leen solo esos anios. DuckDB
  aplica el filtro sobre `filename` **antes de abrir los archivos**: con
  `EXPLAIN ANALYZE` se ve `Scanning Files: 8/32`. Sin la variable se lee todo.
- Yellow (`tpep_*`, `Airport_fee`) y green (`lpep_*`, `trip_type`, `ehail_fee`)
  tienen columnas distintas; `viajes` las unifica con `UNION ALL` y deja nulas
  las que un tipo no tiene.

---

## 3.1 Cantidad de archivos - `03_01_archivos.sql`

- **Objetivo:** contar los Parquet descargados por tipo y anio.
- **Fuente:** listado de `data/raw/*/*/*.parquet` con `glob()`; no lee datos.
- **Resultado:** 16 archivos: 8 yellow y 8 green, de `2026-01` a `2026-08`.
  Septiembre a diciembre aun no estan publicados por la TLC.
- **Decision:** el conjunto 2026 esta completo hasta lo publicado; los analisis
  de 2026 cubren enero-agosto y no deben compararse contra anios de 12 meses
  sin igualar el periodo (se aplica en el Ejercicio 8).

## 3.2 Cantidad de registros - `03_02_registros.sql`, `03_03_registros_por_archivo.sql`

- **Objetivo:** contar viajes por tipo, y por archivo para detectar meses vacios
  o anomalos.
- **Fuente:** vista `viajes`; `03_03` lee solo los metadatos del Parquet
  (`parquet_file_metadata`), sin recorrer filas.
- **Resultado:**

  | taxi | registros 2026 | % del total |
  |---|---:|---:|
  | yellow | 29,703,355 | 98.88 |
  | green | 337,114 | 1.12 |

  Por archivo, yellow va de 3.34 M (agosto) a 4.09 M (mayo) y green de 37 mil
  a 45 mil; ningun mes se aleja mas de 11 % del promedio de su tipo.
- **Decision:** ningun archivo esta truncado. Como green es ~1 % del volumen,
  **toda comparacion yellow vs green se hace con porcentajes o valores por
  viaje**, nunca con totales.

## 3.3 y 3.4 Columnas y tipos - `03_04_columnas_y_tipos.sql`, `03_05_esquema_por_archivo.sql`

- **Objetivo:** listar las columnas y sus tipos, y detectar si cambian entre archivos.
- **Fuente:** `DESCRIBE` de `yellow_raw` / `green_raw`; `parquet_schema()` lee el
  esquema interno de cada archivo.
- **Resultado:** yellow tiene 21 columnas y green 22.

  | Grupo | Columnas (tipo DuckDB) |
  |---|---|
  | Identificacion | `VendorID` INTEGER, `RatecodeID` BIGINT, `store_and_fwd_flag` VARCHAR, `payment_type` BIGINT |
  | Tiempo | `tpep_/lpep_pickup_datetime`, `tpep_/lpep_dropoff_datetime` TIMESTAMP |
  | Viaje | `passenger_count` BIGINT, `trip_distance` DOUBLE, `PULocationID`, `DOLocationID` INTEGER |
  | Montos (DOUBLE) | `fare_amount`, `extra`, `mta_tax`, `tip_amount`, `tolls_amount`, `improvement_surcharge`, `total_amount`, `congestion_surcharge`, `cbd_congestion_fee`, `Airport_fee` (solo yellow), `ehail_fee` (solo green) |
  | Solo green | `trip_type` BIGINT (1 = calle, 2 = despacho) |
  | Nueva | `request_source` VARCHAR |

  `03_05` muestra que **`request_source` solo existe en junio-agosto 2026** (3 de
  8 archivos, en ambos tipos de taxi). No aparece en el diccionario de datos de
  la TLC (version de marzo 2025). Sus valores incluyen `HV0003` y `HV0005`, que
  son los numeros de licencia de base de Uber y Lyft: viajes de taxi amarillo
  pedidos desde esas apps. Con 2024-2026, `cbd_congestion_fee` tambien aparece
  solo desde 2025-01 (20 de 32 archivos). Los tipos fisicos no cambian.
- **Decision:** leer siempre con `union_by_name = true`. `passenger_count` y
  `RatecodeID` vienen como BIGINT pero son categorias; se tratan como codigos.

## 3.5 Muestra - `03_06_muestra.sql`

- **Objetivo:** ver valores reales.
- **Fuente:** vista `viajes`, 5 filas por tipo.
- **Resultado:** 10 filas en `docs/resultados/2026/03_06_muestra.csv`. Se ve, por
  ejemplo, un viaje green de 0.01 millas y 31 segundos que cobra 4.50 USD, y un
  registro green del proveedor 6 sin pasajeros, sin ratecode y sin forma de pago.
- **Decision:** la muestra se ordena por un `hash()` de varias columnas en lugar
  de `USING SAMPLE`. La primera version usaba `USING SAMPLE 5 ROWS`, que con
  varios hilos devolvio 5 viajes del mismo par de dias y ademas aplicaba el
  muestreo *antes* del `WHERE taxi = 'green'` (green salia vacio). El hash da
  una muestra dispersa y reproducible.

## 3.6 Problemas de calidad de datos

Consultas: `03_07` (resumen con `SUMMARIZE`), `03_08` a `03_15`. Cifras de 2026.

| # | Problema | Evidencia (2026) | Consulta |
|---|---|---|---|
| 1 | Fechas fuera del mes de su archivo | pickups desde **2001-01-01** (yellow) y **2008-12-31** (green); 146 + 98 registros fuera de su mes | 03_08 |
| 2 | Duraciones imposibles | 371,673 viajes yellow de 0 segundos, 10 con duracion negativa, 7,315 de mas de 6 h y un pico de 3,784 cerca de **24 h** (taximetro que no se apago) | 03_08 |
| 3 | Distancias cero o absurdas | 952,231 viajes yellow (3.2 %) con distancia 0; maximo de **328,522 millas** | 03_09 |
| 4 | Montos negativos | 157,364 tarifas negativas en yellow; minimo de -2,560 USD | 03_09, 03_12 |
| 5 | Montos extremos | total maximo de 7,053 USD; 49 viajes de mas de 1,000 USD | 03_09 |
| 6 | Velocidades imposibles | 7,987 viajes yellow a mas de 80 mph de promedio | 03_09 |
| 7 | **Registros sin detalle ("Flex Fare")** | **26 % de yellow** con `payment_type = 0` y sin pasajeros, ratecode ni `store_and_fwd_flag`; en green son el 14.5 % pero con `payment_type` **nulo**: el mismo caso se codifica distinto en cada tipo | 03_10, 03_11 |
| 8 | Propinas que no se registran | la propina promedio mensual es de 0.31-0.48 USD en los registros sin detalle frente a 4.14-4.55 USD con tarjeta; en efectivo es 0.00 porque el diccionario indica que no se registra | 03_11 |
| 9 | `RatecodeID = 99` (desconocido) | 2.59 % de yellow | 03_10 |
| 10 | Zonas desconocidas (264, 265) | 0.17 % yellow, 0.34 % green | 03_10 |
| 11 | El total no cuadra con sus componentes | el **proveedor 1 (CMT)** suma el recargo de congestion (2.50) y el cargo CBD (0.75) tambien dentro de `extra`: 83 % de sus registros tienen una diferencia fija de -3.25 USD. El proveedor 2 cuadra en 99.9 %. Los registros sin detalle no reportan `congestion_surcharge` pero lo cobran (+2.50). El proveedor 6 (Myle) siempre difiere en ~12.20 USD | 03_15 |
| 12 | Duplicados exactos | solo 7 pares en yellow: irrelevante | 03_13 |

**Origen de las tarifas negativas (`03_12`).** El 100 % viene del proveedor 2
(Curb). En yellow 2026 el 64 % son disputas (`payment_type = 4`), el 22 % efectivo y
el 11 % sin cargo. **El 89 % tiene un "viaje espejo"**: otro registro con el
mismo vehiculo, horas y zonas y la tarifa positiva. Son anulaciones o
correcciones de un cobro, no viajes.

Con 2024-2026 aparece un caso mas grave: de enero a noviembre de 2025, entre
15 % y 34 % de los registros sin detalle de yellow traen la tarifa negativa con
un total positivo (2.05 M de registros en 2025, sin espejo). Desaparece en diciembre
de 2025. Es un cambio en como un proveedor reportaba esos registros, no un
comportamiento de los pasajeros.

## 3.8 Decision tomada: la vista `viajes_limpios`

A partir de los problemas anteriores se definio una vista limpia, que usan el
EDA (Ejercicio 4) y la evolucion (Ejercicio 8). Los umbrales salen de los
percentiles de 2024-2026: el percentil 99.9 de la distancia de yellow es 38 millas y el 99.99
ya pasa de 13,000; el 99.9 de la duracion es 159 minutos, con una acumulacion
artificial cerca de los 1,440 minutos (24 h).

| Regla | Condicion | Por que |
|---|---|---|
| R1 | el pickup cae en el mes y anio de su archivo | fechas de 2001 o 2008 son errores de reloj |
| R2 | 0 < duracion <= 360 min | duraciones negativas, cero o de un dia completo |
| R3 | 0 < distancia <= 200 mi | 0 no es un viaje; 200 mi sale de la ciudad varias veces |
| R4 | `fare_amount > 0` y `total_amount > 0` | elimina anulaciones, disputas y los registros espejo |
| R5 | `total_amount <= 1000` | montos de miles de USD con distancias normales |
| R6 | velocidad media <= 80 mph | fisicamente imposible en la ciudad |

`03_14_impacto_limpieza.sql` cuantifica cada regla:

| taxi | registros | descartados | % conservado | regla que mas descarta |
|---|---:|---:|---:|---|
| yellow 2026 | 29,703,355 | 1,488,215 | 94.99 | R3 distancia (952,935) |
| green 2026 | 337,114 | 20,156 | 94.02 | R3 distancia (12,281) |

**Lo que no se elimina, a proposito:**

- Los **registros sin detalle** (26 % de yellow). Borrarlos sesgaria el
  analisis: son viajes reales con distancia, horas, zonas y total validos. Se
  marcan como categoria propia en los analisis de pago y propina.
- `passenger_count` nulo o 0: los promedios de pasajeros se calculan solo con
  los registros que lo informan.
- Las **propinas** se analizan solo con pagos con tarjeta (`payment_type = 1`).
- Montos: se usa `total_amount` como lo cobrado, no la suma de componentes, por
  la diferencia de definicion de `extra` entre proveedores.

## 3.9 Que significa consultar Parquet directamente

Consultar un Parquet directamente es ejecutar SQL sobre el archivo tal como se
descargo, sin un paso previo de carga a una base de datos: `SELECT ... FROM
read_parquet('data/raw/yellow/*/*.parquet')`. DuckDB lee el archivo en el
momento de la consulta.

Sirve con volumenes grandes por como esta hecho Parquet y por como lo lee DuckDB:

1. **Formato columnar.** Cada columna se guarda por separado y comprimida. Una
   consulta que usa 3 de 20 columnas lee solo esas 3. Los 30 M de viajes de 2026
   ocupan 496 MB en Parquet; un CSV equivalente ocuparia varias veces mas.
2. **Metadatos y estadisticas.** Cada archivo trae el numero de filas y el
   minimo/maximo de cada columna por bloque (row group). `03_03` cuenta los
   registros de 16 archivos en 0.01 s leyendo solo metadatos, y DuckDB salta
   bloques cuyo rango no cumple un filtro.
3. **Filtro por archivo.** Con `filename` y la variable `anios`, DuckDB descarta
   archivos completos antes de abrirlos (8 de 32 al pedir 2026).
4. **Sin copia ni espera.** No hay que importar antes de preguntar, ni mantener
   una copia sincronizada: un archivo nuevo en `data/raw/` aparece en la
   siguiente consulta.
5. **Ejecucion en paralelo y por bloques.** DuckDB procesa los archivos con
   varios hilos y no necesita cargar todo en memoria. El resumen completo de 25
   columnas (`03_07`, `SUMMARIZE`) sobre 30 M de filas tardo 4 s; casi todas las
   demas consultas, menos de 1 s.

La contraparte es que cada consulta vuelve a leer y descomprimir los archivos;
cuando las mismas consultas se repiten muchas veces conviene materializar una
tabla (Ejercicio 6).
