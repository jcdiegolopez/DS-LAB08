# Lab 8 - DuckDB

Repositorio base del laboratorio 8 del curso **CC3084 - Data Science**
(Universidad del Valle de Guatemala, Ciclo 2, 2026).

Este es el repositorio **proporcionado por el docente**. Contiene la estructura
del proyecto, el ambiente de ejecucion basado en Docker y un script que descarga
los datos de **2026**. Todo lo demas debe ser construido por cada equipo.

## Trabajo con fork

El laboratorio se desarrolla y se entrega sobre un **fork** de este repositorio.
No se trabaja directamente sobre el repositorio del docente.

1. Realice un fork de este repositorio:
   <https://github.com/menene/duckdb>

2. Clone **su propio fork** (no el del docente):

   ```bash
   git clone https://github.com/<su-usuario>/duckdb.git
   cd duckdb
   ```

3. Opcional, para recibir correcciones publicadas por el docente:

   ```bash
   git remote add upstream https://github.com/menene/duckdb.git
   git fetch upstream
   ```

Realice commits frecuentes y descriptivos: el historial del repositorio es parte
de la evaluacion. **La entrega del laboratorio es la URL de su fork.**

## Estructura

```text
duckdb/
|
+-- data/
|   +-- raw/
|   +-- processed/
|
+-- notebooks/
|
+-- scripts/
|
+-- sql/
|
+-- docs/
|
+-- Dockerfile
+-- metabase.Dockerfile
+-- docker-compose.yml
+-- README.md
```

## Requisitos

- Docker, con Docker Compose
- Git

La primera construccion del ambiente descarga varios cientos de MB y puede
tardar algunos minutos.

Considere el espacio en disco: las imagenes de Docker ocupan unos 3 GB y los
datos de los tres anios del laboratorio superan 1.5 GB, a los que se suma la
base materializada del Ejercicio 6. Se recomienda tener al menos 10 GB libres.

## Datos

El repositorio incluye `scripts/download_data.py`, que descarga los archivos de
2026 publicados por la TLC (`--help` muestra las opciones disponibles). Los
archivos se guardan en `data/raw/<tipo>/<anio>/`.

La TLC publica cada mes con varias semanas de atraso, por lo que los ultimos
meses de 2026 todavia no existen. El script consulta al servidor que meses estan
publicados, de modo que vuelve a ejecutarse sin problema conforme aparezcan
nuevos archivos.

Los datos descargados **no deben incluirse en el repositorio Git**. El archivo
`.gitignore` ya esta configurado para evitarlo.

Fuente de datos: NYC TLC Trip Record Data
<https://www.nyc.gov/site/tlc/about/tlc-trip-record-data.page>

Dentro de los contenedores, la carpeta `data/` del proyecto esta montada en
`/workspace/data`. Esa es la ruta que deben usar las herramientas que corren
dentro del ambiente, no la ruta de su computadora.

> **Nota sobre DuckDB:** un archivo `.duckdb` admite un solo proceso con permiso
> de escritura a la vez. Si conecta una herramienta externa a su base de datos,
> use el modo de solo lectura (`read_only`) en esa conexion; de lo contrario los
> demas procesos no podran abrir el archivo.

## Material a entregar

Al finalizar, su fork debe contener:

- el codigo fuente modificado y los scripts de descarga;
- las consultas SQL desarrolladas;
- el notebook o notebooks utilizados;
- la documentacion de las consultas;
- los scripts utilizados para los benchmarks;
- el codigo de los indicadores y visualizaciones;
- el tablero o la evidencia del tablero desarrollado;
- este `README.md`, completado segun la siguiente seccion.

Los archivos de datos descargados **no** deben incluirse.

---

# Documentacion del equipo

Las siguientes secciones deben ser completadas por cada equipo. El README final
debe permitir que una persona que no participo en el desarrollo pueda levantar el
ambiente, descargar los datos, ejecutar el analisis, reproducir los benchmarks y
generar los resultados principales.

## Como levantar el ambiente

1. Instalar Docker (con Docker Compose) y Git, y dejar Docker corriendo.
2. Clonar el fork y entrar a la carpeta:

   ```bash
   git clone git@github.com:jcdiegolopez/DS-LAB08.git
   cd DS-LAB08
   ```

3. Construir y levantar los servicios (la primera vez descarga unos 3 GB):

   ```bash
   docker compose up --build -d
   ```

4. Verificar que ambos servicios esten arriba:

   ```bash
   docker compose ps
   ```

| Servicio | Contenedor | URL | Para que se usa |
|---|---|---|---|
| `lab` | `lab8-lab` | <http://localhost:8888> | JupyterLab con DuckDB, pandas, pyarrow y matplotlib |
| `metabase` | `lab8-metabase` | <http://localhost:3000> | Tablero y visualizaciones |

Si el puerto 3000 ya esta ocupado en su computadora, Metabase puede usar otro:

```bash
METABASE_PORT=3001 docker compose up -d      # PowerShell: $env:METABASE_PORT=3001; docker compose up -d
```

Para ejecutar un comando dentro del ambiente:

```bash
docker compose exec lab python --version
docker compose exec lab bash
```

Para apagar los servicios: `docker compose down`.

### Herramientas disponibles en el contenedor `lab`

| Herramienta | Version |
|---|---|
| Python | 3.11.14 |
| DuckDB | 1.5.5 |
| pandas | 3.0.6 |
| pyarrow | 25.0.1 |
| matplotlib | 3.11.2 |
| requests | 2.34.2 |
| JupyterLab | 4.6.4 |
| curl | 8.14.1 |

Las versiones estan fijadas en `requirements.txt`. Metabase corre en su propio
contenedor y se conecta a DuckDB mediante el driver indicado en
`metabase.Dockerfile`.

### Proposito de cada directorio

| Directorio | Proposito |
|---|---|
| `data/raw/` | Archivos Parquet tal como los publica la TLC, sin modificar. Se organizan como `<tipo>/<anio>/`. |
| `data/processed/` | Datos derivados, por ejemplo la base `.duckdb` con la tabla materializada. Se puede regenerar a partir de `raw/`. |
| `notebooks/` | Notebooks de Jupyter con la exploracion y el analisis. |
| `scripts/` | Scripts reutilizables: descarga de datos y benchmarks. |
| `sql/` | Consultas SQL del laboratorio, un archivo por consulta o grupo de consultas. |
| `docs/` | Documentacion de las consultas, resultados y evidencia del tablero. |

`data/raw/` y `data/processed/` estan en `.gitignore`: los datos no van en Git,
solo el codigo que permite obtenerlos.

### Por que un ambiente reproducible

Un analisis solo es confiable si otra persona (o uno mismo dentro de seis meses)
puede obtener los mismos resultados. Con Docker las versiones de Python, DuckDB
y las librerias son siempre las mismas, sin depender de lo que haya instalado en
cada computadora. Esto evita errores del tipo "en mi maquina funciona", reduce
el tiempo de configuracion de cada integrante del equipo y permite repetir el
proceso completo cuando lleguen datos nuevos.

## Como descargar los datos

El script `scripts/download_data.py` baja los archivos mensuales de taxis
amarillos y verdes desde la fuente original de la TLC. Se ejecuta dentro del
contenedor:

```bash
docker compose exec lab python scripts/download_data.py                  # 2026 (por defecto)
docker compose exec lab python scripts/download_data.py --taxi yellow
docker compose exec lab python scripts/download_data.py --anios 2024 2025 2026
```

Los archivos quedan en `data/raw/<tipo>/<anio>/`, por ejemplo
`data/raw/yellow/2026/yellow_tripdata_2026-01.parquet`. El script se puede
ejecutar las veces que haga falta: no vuelve a descargar un archivo que ya
existe.

### Cambios hechos al script proporcionado

- **Anio como parametro.** El anio 2026 estaba escrito en el codigo. Ahora las
  funciones reciben el anio y la opcion `--anios` permite elegir uno o varios.
  Agregar un anio nuevo no requiere tocar la logica de descarga.
- **Verificacion de tamano.** Antes de descargar, el script consulta al
  servidor el tamano del archivo (`Content-Length`). Si los bytes recibidos no
  coinciden, descarta el archivo y reintenta, hasta tres veces.
- Se conservaron los comportamientos que ya traia: consulta al servidor que
  meses estan publicados, descarga a un archivo `.part` que solo se renombra al
  terminar, y omision de archivos existentes.

### Como se verifico que la descarga esta completa

1. El resumen final del script reporta cuantos archivos se descargaron, cuantos
   ya existian, cuantos aun no estan publicados y cuantos fallaron (debe ser 0).
2. Los meses que la TLC todavia no publica se detectan con una peticion `HEAD`
   al servidor, no se asumen. Al 8 de octubre de 2026 estaban publicados enero a
   agosto de 2026, es decir, 8 archivos por tipo de taxi (16 en total).
3. Cada descarga se compara contra el tamano que informa el servidor, y se
   comprobo que DuckDB puede leer todos los archivos.
4. Una segunda ejecucion del script reporta 0 descargados y 16 existentes.

Al dia de esa descarga, 2026 tiene 29,703,355 viajes amarillos y 337,114
verdes repartidos en esos archivos.

## Como ejecutar el analisis

El analisis (Ejercicios 3, 4 y 8) se hace con SQL de DuckDB **directamente
sobre los Parquet** de `data/raw/`, sin importar los datos a una tabla.

### 1. Datos necesarios

Ademas de los viajes, el analisis usa la tabla de zonas de la TLC (borough y
nombre de cada `LocationID`):

```bash
docker compose exec lab python scripts/download_data.py --anios 2024 2025 2026
docker compose exec lab python scripts/download_zones.py
```

### 2. Como esta organizado

| Archivo | Que contiene |
|---|---|
| `sql/00_vistas.sql` | Vistas sobre los Parquet: `yellow_raw`, `green_raw`, `viajes` (yellow + green unificados), `viajes_limpios` (reglas de limpieza R1-R6) y `zonas`. Se carga antes de cualquier consulta. |
| `sql/03_*.sql` | Ejercicio 3: archivos, registros, esquema, muestra y calidad de datos |
| `sql/04_*.sql` | Ejercicio 4: analisis exploratorio (P1-P10) |
| `sql/08_*.sql` | Ejercicio 8: evolucion 2024-2026 |
| `scripts/run_sql.py` | Ejecuta uno o varios `.sql` con las vistas cargadas |
| `notebooks/analisis_exploratorio.ipynb` | Ejecuta los mismos `.sql` y genera las graficas de `docs/img/` |
| `docs/ej3-consultas.md`, `docs/ej4-eda.md`, `docs/ej8-evolucion.md` | Documentacion de cada consulta: objetivo, fuente, resultado, decision e interpretacion |

Cada archivo `.sql` tiene una sola consulta y empieza con un comentario que
indica su objetivo y su fuente. Ninguna consulta nombra un archivo ni un anio:
leen `data/raw/<tipo>/*/*.parquet`, asi que un mes o un anio nuevo entra sin
cambiar el SQL.

### 3. Ejecutar las consultas

```bash
# Una consulta
docker compose exec lab python scripts/run_sql.py sql/03_02_registros.sql

# Ejercicios 3 y 4 sobre 2026 (como se documentaron), guardando cada resultado en CSV
docker compose exec lab sh -c 'python scripts/run_sql.py sql/03_*.sql sql/04_*.sql --anios 2026 --csv docs/resultados/2026'

# Las mismas consultas y las del Ejercicio 8 sobre todos los anios descargados
docker compose exec lab sh -c 'python scripts/run_sql.py sql/03_*.sql sql/04_*.sql sql/08_*.sql --csv docs/resultados/2024-2026'
```

`--anios` limita las vistas a esos anios (DuckDB ni abre los demas archivos);
sin `--anios` se usa todo lo descargado.

### 4. Ejecutar el notebook

Abrir <http://localhost:8888>, entrar a `notebooks/analisis_exploratorio.ipynb`
y ejecutar todas las celdas (*Run > Run All Cells*). O desde la terminal:

```bash
docker compose exec lab jupyter nbconvert --to notebook --execute --inplace notebooks/analisis_exploratorio.ipynb
```

Tarda alrededor de un minuto y vuelve a generar las graficas de `docs/img/`.

Para usar las vistas desde otro notebook o script:

```python
import os, sys
os.chdir("/workspace")                 # las vistas usan rutas relativas a la raiz
sys.path.insert(0, "/workspace/scripts")
from run_sql import conectar

con = conectar([2026])                 # o conectar() para todos los anios
con.sql("SELECT taxi, count(*) FROM viajes_limpios GROUP BY taxi").show()
```

## Como reproducir los benchmarks

Primero descargar Yellow y Green de 2024, 2025 y 2026 y el catalogo de zonas,
como se indica arriba. Detener Metabase durante la construccion de la base y
las mediciones para liberar el archivo DuckDB y evitar consultas simultaneas:

```bash
docker compose stop metabase
docker compose exec -T lab python scripts/materialize.py
docker compose exec -T lab python scripts/benchmark.py --repetitions 5
docker compose start metabase
```

`materialize.py` crea `data/processed/taxi.duckdb`, con la tabla unificada de
viajes originales y el catalogo de zonas. Las vistas persistentes `viajes`,
`viajes_limpios` y `zonas` permiten usar el mismo SQL del analisis en Metabase.
La vista limpia conserva las reglas R1-R6; la base no se incluye en Git y puede
reconstruirse. Agregar archivos requiere volver a materializar para actualizar
este snapshot.

El benchmark ejecuta cuatro consultas de `sql/06_*.sql` sobre Parquet y tabla,
con un anio (2026), dos (2024 y 2026) y tres (2024-2026). Ambas rutas aplican la
misma limpieza y comprueban la equivalencia de resultados. Se fijan 4 hilos y
4 GB como limite de memoria por conexion. Se mide hasta obtener todas las
filas; la primera corrida se registra aparte y la mediana usa cinco repeticiones
posteriores alternando el orden de las fuentes. No se vacia la cache del SO:
la primera corrida no se presenta como una medicion garantizada en frio.

Resultados en `docs/resultados/benchmark/`: `summary.csv` contiene las medianas,
primeras corridas y rangos; `measurements.csv` todas las mediciones;
`equivalence.json` las comprobaciones; `materialization.json` el manifiesto
SHA-256, conteos y costo de construccion; `environment.json` el ambiente medido.
La interpretacion y las consultas se documentan en
[Ejercicio 6](docs/ej6-benchmark.md). Los tiempos deben medirse de nuevo en cada
computadora, no asumirse iguales a los guardados.

## Como generar los resultados principales

Los ejercicios 7 y 8.4 tienen 12 preguntas y ocho indicadores. Sus consultas
`sql/07_*.sql` funcionan sobre las vistas Parquet del runner o sobre las vistas
persistentes de la base materializada:

```bash
docker compose exec -T lab python scripts/export_indicators.py
docker compose exec -T lab python scripts/validate_indicators.py
```

El primer script guarda ocho CSV y un manifiesto de cobertura, meses comunes,
version y hashes del SQL en `docs/resultados/indicadores/`. El segundo comprueba
consistencia de poblaciones, denominadores, totales de pagos y rankings, sin
consultar la base. Ver las definiciones e interpretaciones en
[Ejercicio 7](docs/ej7-indicadores.md).

### Crear el tablero en una instalacion de Metabase

1. Construir `data/processed/taxi.duckdb` con `materialize.py` y dejar Metabase
   activo. Si se reconstruye la base, detener Metabase antes y arrancarlo al
   terminar, como en la seccion de benchmarks.
2. Abrir <http://localhost:3000> y completar la configuracion inicial de la
   cuenta de administrador. Esta cuenta y los tableros se guardan en el volumen
   Docker `metabase-data` de cada computadora; no llegan al clonar el fork.
3. Publicar con el script desde una terminal interactiva:

   ```bash
   docker compose exec lab python scripts/publish_metabase.py --url http://metabase:3000 --ids-output docs/metabase/installation.json
   ```

   El script pide el correo y la contrasena de esa cuenta. No los guarda en los
   archivos ni imprime la sesion. Crea o actualiza solo los objetos del proyecto
   por sus nombres, conservando sus IDs al repetirlo. La conexion `DuckDB Lab 8`
   usa `/workspace/data/processed/taxi.duckdb` en **solo lectura**.
4. Abrir la coleccion `Lab 8 - Indicadores` y el tablero `NYC Taxi | 2024-2026`.
   Contiene seis graficos, dos tablas y una nota de cobertura. La evidencia de
   esta instalacion y las instrucciones manuales estan en
   [actualizacion del tablero](docs/ej8-tablero.md).

Para generar/revisar la especificacion portable sin iniciar sesion:

```bash
docker compose exec -T lab python scripts/publish_metabase.py --dry-run
```

La especificacion en `docs/metabase/dashboard-spec.json` incluye consultas,
visualizaciones y posiciones. Cada instalacion asigna sus propios IDs.
Para incorporar meses nuevos, ejecutar de nuevo la descarga, reconstruir la
base con Metabase detenido, exportar/validar indicadores y volver a publicar.
Las comparaciones anuales usan los meses presentes en todos los anios y tipos;
las series mensuales muestran toda la cobertura, sin convertir meses ausentes
en ceros. Los resultados actuales tienen 2024 y 2025 completos y enero-agosto
de 2026. Las respuestas 9.3, 9.4 y 9.6 se encuentran en
[discusion](docs/ej9-discusion.md).
