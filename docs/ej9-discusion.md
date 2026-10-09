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

_Pendiente - Persona C, a partir de los resultados del benchmark (Ej. 6)._

## 9.4 Ventajas de este flujo frente a cargar todo con Pandas

_Pendiente - Persona C._

## 9.5 Que permite incorporar nuevos datos con cambios minimos

_Pendiente - Persona A._

## 9.6 Que deberia automatizarse en un sistema de produccion

_Pendiente - Persona C._

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
