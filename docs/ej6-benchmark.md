# Ejercicio 6 — Parquet directo y tablas materializadas DuckDB

El experimento compara las mismas cuatro consultas SQL sobre dos fuentes: las
vistas de `sql/00_vistas.sql`, que leen los Parquet originales, y las vistas del
archivo persistente `data/processed/taxi.duckdb`, respaldadas por tablas. Ambas
rutas aplican literalmente las reglas R1–R6 de limpieza del Ejercicio 3.

## 6.1–6.2 Materialización y contrato de la base

`scripts/materialize.py` ejecuta `CREATE OR REPLACE TABLE viajes_materializados
AS SELECT * FROM viajes`. Conserva todos los registros del origen unificado,
incluidos los que las reglas de limpieza descartan; la limpieza permanece en una
vista para que su definición sea la misma que en Parquet. `zonas_materializadas`
guarda las 265 zonas de la tabla TLC. No se crean índices explícitos ni tablas agregadas.

La tabla de viajes conserva las 27 columnas de la vista original:

```text
taxi, archivo, vendor_id, pickup, dropoff, passenger_count, trip_distance,
ratecode_id, store_and_fwd_flag, pu_location_id, do_location_id, payment_type,
fare_amount, extra, mta_tax, tip_amount, tolls_amount, improvement_surcharge,
total_amount, congestion_surcharge, airport_fee, cbd_congestion_fee, trip_type,
request_source, anio_archivo, mes_archivo, duracion_min
```

Los tipos exactos, la huella SHA-256 de cada archivo y el SQL persistido se
conservan en `docs/resultados/benchmark/materialization.json`. El contrato de
consumo para el tablero es:

| Objeto | Contrato |
|---|---|
| `viajes_materializados` | Tabla con todos los viajes unificados del momento de la materialización. |
| `viajes` | Vista sobre esa tabla; todos los años por defecto. `SET VARIABLE anios = [2026]` permite limitar una sesión. |
| `viajes_limpios` | Vista sobre `viajes` con R1–R6, idénticas a `sql/00_vistas.sql`. |
| `zonas_materializadas` | Tabla con `location_id`, `borough`, `zona` y `service_zone`. |
| `zonas` | Vista sobre `zonas_materializadas`. |

Después de copiar los datos se eliminan `yellow_raw` y `green_raw`; se reemplazan
`viajes` y `zonas` por vistas sobre tablas. El script comprueba que ninguna vista
persistente contiene `read_parquet` o `read_csv`. Por eso Metabase consulta la
base sin necesitar el directorio `data/raw`. Los valores de `archivo` son
proveniencia histórica y no se vuelven a abrir al consultar.

La creación de tablas y sustitución de vistas es transaccional. Luego se hace
`CHECKPOINT` y se cierra la conexión. Para repetir la materialización hay que
desconectar Metabase del archivo o detenerlo temporalmente; DuckDB coordina la
escritura de un archivo desde un solo proceso. El benchmark abre el archivo con
`read_only=True` y no modifica la base.

`scripts/validate_materialization.py` verifica la atomicidad en una base temporal
con dos Parquet sintéticos pequeños. Crea un snapshot, cambia el origen e
inyecta una falla después de sustituir las vistas por las del origen nuevo.
Comprueba que el rollback conserva tablas, definiciones de vistas, resultados
limpios y zonas anteriores; después verifica que un rebuild exitoso incorpora
los registros nuevos. No consulta ni modifica la base real. Se ejecuta con:

```bash
docker compose exec -T lab python scripts/validate_materialization.py -v
```

La materialización observada tomó **106.604 s** incluyendo configuración y
`CHECKPOINT`; la instrucción que creó la tabla de viajes tomó **100.726 s**.
Durante la construcción se ejecutaba también la exportación de indicadores en
otro proceso, por lo que este costo se informa como una observación con carga
concurrente y no como un tiempo aislado mínimo. Los benchmarks de consultas se
ejecutan después de terminar esa exportación y antes de consultar con Metabase.
La base tiene **4,422,381,568 bytes (4.422 GB decimales)** frente a
**2,073,081,961 bytes (2.073 GB)** de Parquet: **2.133 veces** el tamaño original.
No se compara el tamaño de una tabla limpia: esta base conserva el origen crudo,
las columnas unificadas/derivadas y el catálogo de zonas.

| Año del archivo | Meses por tipo | Filas crudas Yellow + Green | Filas tras R1–R6 |
|---|---:|---:|---:|
| 2024 | 12 | 41,829,938 | 40,288,838 |
| 2025 | 12 | 49,313,977 | 44,699,905 |
| 2026 | 8 | 30,040,469 | 28,532,098 |
| Total | 32 | 121,184,384 | 113,520,841 |

## 6.3 Consultas representativas

Cada SQL usa `viajes_limpios`, por lo que cambia la fuente de la conexión y no la
consulta. Los cuatro archivos son ejecutables también con `scripts/run_sql.py`.

| Consulta | Objetivo | Trabajo representado |
|---|---|---|
| `sql/06_01_volumen_mensual.sql` | Contar los viajes por taxi, año y mes. | Filtros de limpieza y agregación temporal. |
| `sql/06_02_montos_pago.sql` | Comparar importes, propinas y distancias por método de pago. | Lectura de varias columnas, sumas y promedios. |
| `sql/06_03_zonas_origen.sql` | Resumir demanda, importe y duración por zona de origen. | Join con una dimensión, agregación y ordenamiento. |
| `sql/06_04_distribucion.sql` | Obtener percentiles 25, 50, 75 y 95 de importe y distancia por taxi y año. | Cuantiles exactos, con mayor trabajo de selección y memoria. |

## 6.4–6.6 Metodología reproducible

Desde la raíz del repositorio:

```bash
docker compose stop metabase
docker compose exec -T lab python scripts/materialize.py --threads 4 --memory-limit 4GB
docker compose exec -T lab python scripts/benchmark.py --threads 4 --memory-limit 4GB --repetitions 5
docker compose start metabase
```

El script usa tres conjuntos: un año `[2026]`, dos años `[2024, 2026]` y tres años
`[2024, 2025, 2026]`. La selección corresponde al año del archivo de origen.
2024 y 2025 tienen doce meses por tipo; 2026 tiene enero–agosto, ocho meses por
tipo. Por tanto “un año” significa los meses disponibles de 2026, no doce meses;
la cantidad real de filas y bytes se informa para comparar tamaños.

Para cada consulta y conjunto se registra una primera ejecución por fuente y
cinco repeticiones posteriores por fuente. Se alterna el orden Parquet/tabla en
cada repetición y también el orden inicial según conjunto y consulta. Las
medianas se calculan exclusivamente con las cinco repeticiones posteriores. Hay
144 mediciones en total: 3 conjuntos × 4 consultas × 2 fuentes × 6 ejecuciones.

El tiempo medido por `time.perf_counter()` abarca `execute()` y `fetchall()`:
incluye obtener todos los resultados, y excluye configurar conexiones, validar
equivalencia y escribir CSV. Ambas conexiones tienen cuatro hilos, límite de
memoria de 4 GB y `preserve_insertion_order=false`. La tabla se construye antes
del benchmark, sin ordenar explícitamente sus filas. La materialización y el
`CHECKPOINT` se cronometran por separado, sin sumarlos a cada consulta.

Entorno observado: DuckDB **1.5.5**, Python **3.11.14**, Linux sobre WSL2,
12 CPU lógicas y aproximadamente 16.66 GB de RAM del entorno Linux. El
contenedor no impone otro límite cgroup de CPU o memoria; DuckDB sí usa los
límites indicados. Durante las mediciones finales no se ejecutan consultas de
indicadores ni de Metabase contra los datos. No se controla toda la actividad
del anfitrión Windows.

**La primera ejecución registrada no equivale a una caché fría.** La
materialización, las consultas anteriores y la inspección de esquemas pueden
haber calentado cachés. No se vacía la caché del sistema operativo ni se reinicia
el servidor entre mediciones. La conexión en memoria de Parquet y la conexión
de tabla se reutilizan; las consultas posteriores reflejan condiciones
calientes. Se conserva la primera medida para hacer visible la diferencia y se
usan las medianas para reducir el peso de una ejecución atípica. Los resultados
son de esta máquina y esta carga, no una garantía universal de rendimiento.

El script compara el resultado completo de las 144 ejecuciones con la primera
salida de cada consulta/conjunto. Conteos, texto, nulos y dimensiones de filas
se comparan exactamente. Las sumas y medias de coma flotante pueden variar
mínimamente por la agregación paralela; se usa `math.isclose` con tolerancia
relativa `1e-10` y absoluta `1e-8`. Los cuantiles son exactos, no aproximados.
`equivalence.json` registra el máximo error observado por corrida, y los CSV de
cada fuente conservan los resultados de la primera ejecución.

## Evidencia del experimento

| Archivo en `docs/resultados/benchmark/` | Contenido |
|---|---|
| `materialization.json` | Entorno, tiempo de construcción, tamaño de base, filas por taxi/año, columnas, vistas persistentes y manifiesto SHA-256. |
| `environment.json` | Python/DuckDB/SO, CPU, memoria del contenedor, ajustes y protocolo del benchmark. |
| `measurements.csv` | Cada corrida individual: segundos, fase, repetición, orden, filas de resultado y tamaño de origen. |
| `summary.csv` | Primera corrida, mediana, mínimo/máximo de cinco corridas calientes y razón Parquet/tabla. |
| `equivalence.json` | Comparación del resultado completo de cada ejecución. |
| `*_06_*_parquet.csv`, `*_06_*_tabla.csv` | Resultado completo de cada consulta y conjunto, por ambas fuentes. |

## 6.7–6.8 Resultados observados

El benchmark final terminó con **144 mediciones y 144 validaciones correctas**.
La comprobación posterior del CSV confirmó doce combinaciones de
consulta/conjunto, doce ejecuciones por combinación y cinco mediciones calientes
por fuente; las medianas del resumen coinciden con las corridas individuales.

| Conjunto lógico | Años | Filas crudas | Archivos Parquet | Bytes Parquet seleccionados |
|---|---|---:|---:|---:|
| 1 año | 2026 | 30,040,469 | 16 | 519,727,000 |
| 2 años | 2024 + 2026 | 71,870,407 | 40 | 1,228,648,745 |
| 3 años | 2024 + 2025 + 2026 | 121,184,384 | 64 | 2,073,081,961 |

Todos los tiempos siguientes son segundos. `P/T` divide la mediana Parquet entre
la mediana tabla: un valor mayor que uno indica menor tiempo de la tabla. La
base física es la misma en las doce comparaciones: 4.422 GB con tres años; el
conjunto lógico se limita con la variable de sesión `anios`.

| Años | Consulta | Primera P | Primera T | Mediana P | Mediana T | P/T |
|---|---|---:|---:|---:|---:|---:|
| 2026 | Volumen mensual | 1.530 | 2.794 | 1.395 | 1.107 | 1.26× |
| 2026 | Montos por pago | 1.695 | 1.165 | 1.793 | 1.246 | 1.44× |
| 2026 | Zonas de origen | 2.102 | 1.445 | 1.937 | 1.264 | 1.53× |
| 2026 | Distribución exacta | 4.966 | 4.637 | 5.101 | 4.561 | 1.12× |
| 2024 + 2026 | Volumen mensual | 3.258 | 1.632 | 3.083 | 1.294 | 2.38× |
| 2024 + 2026 | Montos por pago | 3.567 | 1.729 | 3.548 | 1.597 | 2.22× |
| 2024 + 2026 | Zonas de origen | 4.374 | 2.148 | 4.274 | 2.100 | 2.03× |
| 2024 + 2026 | Distribución exacta | 8.343 | 5.893 | 8.276 | 6.339 | 1.31× |
| 2024 + 2025 + 2026 | Volumen mensual | 5.370 | 2.218 | 5.113 | 1.891 | 2.70× |
| 2024 + 2025 + 2026 | Montos por pago | 6.196 | 2.349 | 6.120 | 2.284 | 2.68× |
| 2024 + 2025 + 2026 | Zonas de origen | 6.967 | 3.539 | 6.825 | 3.250 | 2.10× |
| 2024 + 2025 + 2026 | Distribución exacta | 14.370 | 8.229 | 14.545 | 8.065 | 1.80× |

La tabla fue más rápida en las medianas de las doce combinaciones: la razón
medida varía entre **1.12× y 2.70×**. Al ampliar el conjunto de 30.0 a 121.2
millones de filas crudas, aumenta el tiempo de ambas fuentes y también la
ventaja relativa de la tabla en estas cuatro consultas. Esto describe los
conjuntos y la distribución física medidos; no prueba una regla universal de
escalamiento.

Las distribuciones exactas son la consulta más lenta por ambas rutas. Con tres
años requieren 14.545 s sobre Parquet y 8.065 s sobre tabla, frente a 5.113 y
1.891 s para el volumen. Su menor ventaja relativa frente al conteo sugiere que
el trabajo de cuantiles sigue siendo relevante después de materializar.

En el primer volumen de 2026, la tabla tardó 2.794 s y Parquet 1.530 s; en las
medianas calientes la relación cambia a 1.107 s y 1.395 s. La diferencia ilustra
por qué una sola ejecución puede llevar a una conclusión distinta. La corrida
inicial ya podía usar caché del SO, por lo que este contraste no demuestra un
costo de arranque totalmente frío.

No hubo diferencias de conteos, categorías ni filas. La mayor diferencia de
coma flotante ocurrió en la consulta de sumas por pago con tres años:
**0.007581234 USD** en una suma monetaria, menos de un centavo, con error relativo
máximo **8.762e-12**. Está dentro de la tolerancia declarada y es consistente con
el distinto orden de suma paralela de valores `DOUBLE`; no se redondearon los
datos ni se usaron cuantiles aproximados para forzar equivalencia.

La suma de las cuatro medianas con tres años es **32.603 s** para Parquet y
**15.491 s** para tabla: ahorro orientativo de **17.112 s** al ejecutar una vez
cada consulta. Con la materialización observada de 106.604 s,
`106.604 / 17.112 = 6.23` ciclos, aproximadamente **7 ciclos de las cuatro
consultas** amortizarían la preparación. Es una estimación a partir de sumas de
medianas, no una medición del ciclo completo; supone la misma mezcla y
condiciones calientes. El costo de construcción se obtuvo con carga concurrente
y esta cuenta no incluye almacenamiento ni actualización del snapshot.

## 6.9–6.10 Interpretación y elección de estrategia

Parquet directo evita una copia previa y permite consultar nuevos archivos con
las mismas vistas y rutas con comodines. Es útil para exploración, consultas
esporádicas y datos que cambian con frecuencia. La materialización requiere
tiempo, espacio adicional y reconstrucción o una política de incorporación
incremental para reflejar archivos nuevos. A cambio ofrece un archivo estable
para Metabase, tipos unificados, metadatos de la tabla y lecturas repetidas que
pueden amortizar esa preparación.

Los dos formatos son columnares; no hay que asumir que materializar siempre
acelera cualquier consulta. La complejidad del SQL, los filtros, el tamaño de
datos, la distribución física y las cachés afectan la diferencia. Aquí ambas
rutas todavía evalúan R1–R6 en cada consulta. Las columnas derivadas
`anio_archivo`, `mes_archivo` y `duracion_min` se calculan al importar la tabla,
mientras que las vistas Parquet las calculan durante la consulta: esa diferencia
es parte del costo que este experimento busca medir.

Para decidir si conviene materializar, se debe comparar el costo de construcción
con el ahorro por ejecución. Para una mezcla concreta de consultas, si el ahorro
total caliente es positivo, el número orientativo de ciclos para amortizar la
construcción es `tiempo_materializacion / suma(tiempo_parquet - tiempo_tabla)`.
Esa estimación supone que las condiciones medidas se mantienen y excluye el
almacenamiento y el mantenimiento de nuevas particiones. El benchmark compara
consultas sobre una única tabla de tres años filtrada por sesión, sin crear una
base distinta para cada tamaño.
