# Ejercicio 9 - Discusion

Cada respuesta se apoya en lo que se hizo en el laboratorio; las cifras vienen
de las consultas de `sql/` y de los documentos de cada ejercicio.

## 9.1 Que caracteristicas de DuckDB resultaron mas utiles

1. **Leer Parquet directamente con comodines.** `read_parquet('data/raw/yellow/*/*.parquet')`
   convierte una carpeta de 32 archivos en una sola tabla consultable, sin paso
   de carga. Agregar 2024 y 2025 no requirio tocar ninguna consulta (Ej. 8.3).
2. **`union_by_name`.** Los archivos cambian de esquema (`cbd_congestion_fee`
   desde 2025, `request_source` desde junio 2026). Con esta opcion las columnas
   se alinean por nombre; sin ella DuckDB usa el esquema del primer archivo y la
   columna nueva no existe para la consulta.
3. **`filename = true` y el filtro por archivo.** Saber de que archivo viene cada
   fila permitio detectar fechas fuera de su mes y limitar las consultas a un
   anio con una variable (`SET VARIABLE anios = [2026]`). DuckDB descarta los
   archivos que no cumplen antes de abrirlos (`Scanning Files: 8/32`).
4. **Funciones de exploracion.** `SUMMARIZE` da minimo, maximo, cuartiles, nulos
   y distintos de 25 columnas en una sola linea; `DESCRIBE`, `parquet_schema()` y
   `parquet_file_metadata()` responden "que columnas hay" y "cuantas filas" sin
   leer los datos.
5. **SQL analitico completo.** `approx_quantile` (medianas y percentiles sobre
   millones de filas en menos de un segundo), `FILTER` dentro de agregaciones,
   funciones de ventana, `QUALIFY`, `GROUP BY ALL`, `SEMI JOIN`, macros y vistas.
   Las vistas permitieron definir la limpieza una sola vez (`viajes_limpios`) y
   reutilizarla en todos los ejercicios.
6. **Rendimiento sin servidor.** Corre dentro del proceso de Python, sin
   configurar nada. Casi todas las consultas sobre 30 M de filas tardan menos de
   1 s, y sobre 121 M casi todas tardan entre 1 y 3 s.

## 9.2 Ventajas y limitaciones de consultar directamente archivos Parquet

**Ventajas observadas**

- **Cero tiempo de preparacion.** Se puede consultar en cuanto termina la
  descarga, y un archivo nuevo aparece en la siguiente consulta sin recargar nada.
- **Una sola copia de los datos.** No hay una base que mantener sincronizada con
  los archivos originales; `data/raw/` es la unica fuente de verdad.
- **Lee solo lo necesario.** Por ser columnar, una consulta de 3 columnas no
  lee las otras 18. Las consultas de metadatos (`03_01`, `03_03`, `03_05`) cuentan
  archivos, filas y columnas en milisegundos aunque haya 121 M de filas.
- **Poco espacio.** 30 M de viajes de 2026 ocupan 496 MB comprimidos.

**Limitaciones observadas**

- **Cada consulta paga la lectura completa.** Descomprimir y recorrer los
  archivos se repite cada vez. El `SUMMARIZE` de 25 columnas tarda 4 s con 2026 y
  15.5 s con los tres anios; si se repite muchas veces, una tabla materializada
  lo evita (ver 9.3 y Ej. 6).
- **El esquema lo decide el archivo, no quien consulta.** No hay un esquema
  fijo: cada archivo trae el suyo. Hay que acordarse de `union_by_name`, y aun
  asi una columna que desaparece o cambia de tipo solo se descubre al consultar.
  Sin esa opcion, el error es silencioso hasta que se usa la columna.
- **No hay restricciones ni limpieza.** Parquet guarda lo que la TLC publico:
  fechas de 2001, tarifas negativas, distancias de 300,000 millas. La validacion
  y la limpieza quedan en las consultas (vista `viajes_limpios`) y hay que
  repetirlas, o encapsularlas, en cada uso.
- **Los archivos son inmutables.** No se puede corregir un registro ni agregar
  una columna derivada sin reescribir el archivo; las columnas calculadas
  (`duracion_min`, `anio_archivo`) se recalculan en cada consulta.
- **El muestreo no es tan simple como parece.** `USING SAMPLE` sobre los Parquet
  devolvio filas de un mismo bloque y no se aplica despues del `WHERE`; hubo que
  muestrear de otra forma (Ej. 3.5).

## 9.3 Ventajas y limitaciones de las tablas materializadas en DuckDB

Materializar dio una fuente estable para Metabase: `taxi.duckdb` conserva los
121,184,384 viajes unificados y el catalogo de zonas, con vistas que no vuelven a
abrir Parquet ni CSV. El esquema y las columnas derivadas (`anio_archivo`,
`mes_archivo`, `duracion_min`) quedan guardados. Esto facilita reutilizar el
mismo archivo para consultas repetidas y mantener un corte identificable de
los datos mediante el manifiesto SHA-256.

El benchmark midio cuatro consultas sobre uno, dos y tres anios, con una primera
corrida separada y cinco repeticiones calientes por fuente. Las tablas fueron
mas rapidas en las doce medianas, entre **1.12 y 2.70 veces**. Con los tres anios,
el volumen mensual paso de **5.113 s** sobre Parquet a **1.891 s** sobre tabla;
los cuantiles exactos, de **14.545 s** a **8.065 s**. Se validaron los resultados
completos de las 144 ejecuciones: conteos y categorias iguales, con pequenas
diferencias de suma `DOUBLE` dentro de la tolerancia declarada. Materializar no
elimina el recorrido de columnas ni las agregaciones; ambas rutas siguen
evaluando R1-R6 en `viajes_limpios`, y la limpieza no se copio a una segunda tabla.

El costo inicial fue **106.604 s** incluyendo configuracion y `CHECKPOINT`
(100.726 s para crear la tabla de viajes). Esa construccion coincidio con la
exportacion de indicadores en otro proceso, por lo que es un costo observado
con carga concurrente. Las mediciones finales de consultas se hicieron despues,
sin consultas de indicadores o Metabase contra los datos.

Tambien hay un costo de almacenamiento: la base ocupa **4.422 GB decimales**,
frente a **2.073 GB** de Parquet, **2.133 veces** el tamano original. Si se
conservan ambas fuentes se necesitan aproximadamente **6.495 GB**. La tabla
contiene el origen unificado crudo, las columnas derivadas y las zonas; estos
tamanos no representan una copia fisica de solo los viajes limpios.

La suma de las cuatro medianas con tres anios fue **32.603 s** para Parquet y
**15.491 s** para tabla, un ahorro orientativo de **17.112 s** por una ejecucion
de cada consulta. `106.604 / 17.112 = 6.23`: aproximadamente **7 ciclos de las
cuatro consultas** amortizarian la preparacion observada. Es una estimacion con
sumas de medianas y condiciones calientes, no una medicion del ciclo completo;
no incluye el espacio adicional ni el costo de incorporar archivos nuevos.

La principal limitacion de mantenimiento es que la tabla es un snapshot: un
Parquet nuevo aparece automaticamente en las vistas del origen, pero no en la
tabla ya creada. `scripts/materialize.py` hace una reconstruccion completa;
una actualizacion incremental requeriria registrar los archivos incorporados y
validar duplicados y cambios de esquema. La escritura tambien exige coordinar
el cierre de lectores del archivo, por ejemplo detener Metabase antes de
reconstruir la base.

Los resultados no demuestran que una tabla siempre sera mas rapida. No se vacio
la cache del sistema operativo y la primera corrida tampoco garantiza cache
fria: para volumen de 2026 la tabla tomo **2.794 s** inicialmente frente a
**1.530 s** de Parquet, aunque su mediana caliente fue menor. Se alterno el orden
de ambas fuentes para reducir el sesgo. Ademas, los tres tamanos logicos se
filtraron sobre **la misma base fisica de tres anios**, sin construir una base
distinta para cada conjunto. Los tiempos corresponden a DuckDB 1.5.5, cuatro
hilos, limite de 4 GB por conexion y la distribucion de datos de esta maquina.

Para este tablero con consultas repetidas conviene la materializacion, porque
el ahorro observado puede amortizar su preparacion y el archivo es independiente
del origen. Para exploracion esporadica o llegada frecuente de meses nuevos,
Parquet directo evita la copia y su mantenimiento. Las mediciones, SQL y
limitaciones completas estan en [Ejercicio 6](ej6-benchmark.md) y
`docs/resultados/benchmark/`.

## 9.4 Ventajas de este flujo frente a cargar todo con Pandas

El flujo usado mantiene los 121,184,384 registros en Parquet o DuckDB y lleva a
Python solo el resultado agregado. Por ejemplo, los indicadores mensuales
producen 64 filas, en lugar de cargar todos los viajes en un DataFrame. DuckDB
puede seleccionar columnas y filtrar archivos antes de construir ese resultado;
esto reduce el volumen que debe mantenerse en memoria de Python.

SQL tambien permite expresar las mismas reglas de limpieza, agrupaciones,
joins con zonas y funciones de ventana en consultas reutilizables por scripts
y Metabase. Pandas sigue siendo util para graficar, exportar y transformar los
resultados pequenos: el script de indicadores lo usa precisamente en esa etapa.
DuckDB tambien puede consultar DataFrames de Pandas, por lo que ambos se pueden
combinar.

No se midio Pandas en el benchmark del Ejercicio 6: no afirmamos una ventaja de
tiempo ni un consumo de RAM numerico frente a Pandas. La ventaja demostrable de
este diseno es que evita cargar todos los viajes en Python. DuckDB puede usar
disco para ciertos resultados intermedios mayores que la memoria; eso requiere
espacio temporal y no elimina todas las limitaciones de memoria.

Referencias: [consultar Parquet](https://duckdb.org/docs/current/guides/file_formats/query_parquet),
[procesamiento mayor que la memoria](https://duckdb.org/docs/current/guides/performance/how_to_tune_workloads),
[SQL sobre Pandas](https://duckdb.org/docs/current/guides/python/sql_on_pandas).

## 9.5 Que permite incorporar nuevos datos con cambios minimos

_Pendiente - Persona A._

## 9.6 Que deberia automatizarse en un sistema de produccion

Automatizaria el flujo completo, con controles observables en cada etapa:

1. **Detectar publicaciones y descargar.** Consultar que meses estan disponibles,
   reintentar errores de red y conservar un manifiesto de nombre, tamano y hash.
   Diferenciar un archivo no publicado de un fallo HTTP o de conectividad.
2. **Validar antes de incorporar.** Comprobar lectura de Parquet, columnas y
   tipos requeridos, cobertura taxi/anio/mes, filas y cambios de esquema.
   Registrar los descartes R1-R6 por mes; una variacion inesperada debe producir
   una alerta, no desaparecer al filtrar los viajes.
3. **Actualizar la materializacion.** Incorporar archivos nuevos una sola vez
   usando el manifiesto como control de idempotencia. Construir una nueva
   version de la base y publicarla despues de validar, coordinando el cierre de
   lectores de Metabase para evitar conflictos con el escritor de DuckDB.
4. **Regenerar y comprobar indicadores.** Ejecutar las consultas, validar
   denominadores, cobertura, nulos y sumas de porcentajes; guardar resultados,
   version del SQL y fecha de corte. Recalcular los meses comunes para no
   comparar un anio parcial con uno completo.
5. **Actualizar el tablero y la evidencia.** Reutilizar las definiciones de las
   tarjetas, verificar que todas responden y conservar una exportacion portable
   y capturas del resultado.
6. **Monitorear costo y fallos.** Guardar duracion de cada etapa, uso de disco y
   cantidad de archivos/filas. Repetir el benchmark cuando cambie el volumen o
   las consultas, con la misma configuracion; respaldar el volumen de Metabase
   y mantener las credenciales fuera de Git.

Los scripts de este laboratorio cubren descarga, reconstruccion de la base,
benchmark, exportacion de indicadores y publicacion del tablero. La
materializacion actual es una reconstruccion completa: la incorporacion
incremental, el planificador y las alertas son propuestas para produccion,
no funcionalidades implementadas.

## 9.7 Decisiones de diseno importantes para la reproducibilidad

_Pendiente - Persona A._

## 9.8 Que se aprendio que no seria evidente con datos pequenos

1. **Un porcentaje pequeno sigue siendo mucha gente.** Las tarifas negativas
   son 3 % de yellow, pero son 3.7 M de registros; las distancias en cero, 3.1 M.
   Con 1,000 filas esos problemas aparecen como 1 o 2 casos "raros" y se borran
   sin mirar; con 121 M se ve que tienen estructura: todas las tarifas negativas
   vienen de un solo proveedor y, en 2026, el 89 % tiene un registro espejo
   positivo (son anulaciones de un cobro).
2. **Los problemas de calidad cambian con el tiempo.** La proporcion de
   registros sin detalle paso de 4 % a 28 % en dos anios, y las tarifas negativas
   en esos registros existieron solo de enero a noviembre de 2025. Una muestra
   de un mes no muestra ninguno de los dos; la calidad hay que medirla por
   periodo y por proveedor, no una sola vez.
3. **El esquema tambien cambia.** En un archivo de ejemplo nunca se ve que
   `cbd_congestion_fee` falta en 2024 o que `request_source` aparece en junio de
   2026. Con muchos archivos el esquema deja de ser fijo.
4. **Los agregados enganan si cambia la composicion.** La tarifa promedio
   yellow sube 9 % en 2026, pero la del taximetro solo 2.6 %: lo que cambia es la
   proporcion de un tipo de registro mas caro. Con muchos datos aparecen
   subgrupos con comportamiento propio, y el promedio general los mezcla.
5. **El promedio deja de describir el caso tipico.** La distancia promedio
   yellow (3.5 mi) casi duplica la mediana (1.9 mi) por unos pocos viajes largos.
   Con distribuciones de colas largas hay que trabajar con percentiles, y
   `approx_quantile` los calcula sobre millones de filas en milisegundos.
6. **Hay que pensar en el costo antes de ejecutar.** Un `SUMMARIZE` tarda 4 veces
   mas con 4 veces mas datos; una consulta mal planteada (por ejemplo, ordenar
   121 M de filas para sacar una muestra) puede tardar mucho. Leer solo las
   columnas y los archivos necesarios deja de ser una optimizacion y pasa a ser
   la forma normal de trabajar.
7. **Lo atipico no siempre es un error.** El criterio de IQR marca como atipico
   el 8.5 % de los totales, pero la mayoria son viajes de aeropuerto
   legitimos (8 % de los viajes y 21 % de los ingresos). Con datos pequenos se
   tienta borrar los extremos; con datos grandes se ve que forman un grupo
   propio.
