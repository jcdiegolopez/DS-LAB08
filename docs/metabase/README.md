# Reproducir el tablero de indicadores

El tablero **NYC Taxi | 2024-2026** reúne ocho indicadores: seis gráficos y dos tablas. Las consultas están en `sql/07_*.sql`; `dashboard-spec.json` exporta sus textos, hashes SHA-256, visualizaciones, cobertura local y posiciones. Es portable: no contiene credenciales ni IDs de una instalación.

## Preparación

1. Levantar el proyecto con `docker compose up --build -d`.
2. Descargar los Parquet y el catálogo con los scripts existentes.
3. Materializar `data/processed/taxi.duckdb` con `docker compose exec lab python scripts/materialize.py`. Detener Metabase antes de escribir y esperar a que el script termine correctamente; después reiniciar el servicio.
4. Completar la primera cuenta de administrador en [Metabase local](http://localhost:3000).

El archivo persistente contiene `viajes`, `viajes_limpios` y `zonas`. Metabase usa el archivo `/workspace/data/processed/taxi.duckdb` montado por Compose, con `read_only=true`. No hay que ejecutar el SQL de creación de vistas dentro de una pregunta de Metabase.

Para regenerar la base cuando Metabase ya está conectado:

```powershell
docker compose stop metabase
docker compose exec lab python scripts/materialize.py
```

Cuando la materialización termine correctamente y se cierre la conexión de escritura, ejecutar:

```powershell
docker compose start metabase
```

DuckDB no permite un proceso escritor junto con lectores de otro proceso. Cerrar también las conexiones a este archivo en notebooks u otros scripts antes de materializar. Las preguntas y el tablero se conservan en el volumen `metabase-data` al detener y arrancar el servicio.

## Revisar sin credenciales

Desde la raíz del proyecto:

```powershell
docker compose exec lab python scripts/publish_metabase.py --dry-run
```

Esto regenera `docs/metabase/dashboard-spec.json` y valida los ocho archivos, seis gráficos, nombres únicos y posiciones sin superposición. No autentica, no modifica Metabase y no ejecuta consultas. La ejecución real de los SQL se verifica con `scripts/run_sql.py` y los resultados de `docs/resultados/indicadores/`.

## Crear o actualizar

```powershell
docker compose exec lab python scripts/publish_metabase.py --url http://metabase:3000
```

El script pide el correo y la contraseña en la terminal; la contraseña no se muestra ni se guarda. También acepta las variables de entorno `METABASE_USER` y `METABASE_PASSWORD`. Para evitar guardar secretos en el historial, preferir la entrada interactiva. Desde Python en el host, la URL predeterminada es `http://localhost:3000`.

La publicación crea la conexión **DuckDB Lab 8** si falta, la colección raíz **Lab 8 - Indicadores**, ocho preguntas SQL y un tablero con dos columnas. Al repetirla, busca nombres exactos únicamente dentro de esa colección y reutiliza los IDs. Si ya existe la conexión con otra ruta, motor o acceso de escritura, se detiene para no cambiar una conexión compartida. Si encuentra duplicados por nombre, pide resolverlos antes de continuar.

El tablero con ese nombre queda sincronizado con la especificación: incluye la nota de cobertura y las ocho preguntas en sus posiciones previstas. Cualquier tarjeta adicional añadida manualmente a ese mismo tablero queda fuera de la disposición reproducida; las preguntas guardadas no se borran. Otras colecciones y tableros no se modifican.

Opcionalmente, `--ids-output ruta.json` guarda los IDs y la URL locales sin credenciales. Ese archivo sirve para una instalación concreta; no hace falta para reproducir el tablero en otra computadora. La especificación portable continúa sin IDs.

## Visualizaciones y límites de interpretación

| Pregunta | Visualización | Lectura |
|---|---|---|
| I1: volumen | Línea por taxi | Viajes por día calendario, todos los meses disponibles |
| I2: monto registrado | Línea por taxi | USD nominales por día; no utilidad del conductor |
| I3: ticket promedio | Barras por año y taxi | Solo meses comunes a las seis combinaciones taxi-año |
| I4: viaje típico | Barras por año y taxi | Duración mediana aproximada en el período común |
| I5: mezcla de pagos | Tabla | Porcentaje por taxi, mes y método; incluye NULL/0 |
| I6: propina de tarjeta | Barras por año y taxi | Mediana de propina/fare_amount; conserva ceros |
| I7: zonas principales | Tabla | Cinco zonas por taxi-año, con porcentaje del total |
| I8: limpieza | Línea por taxi | Porcentaje de registros conservados tras R1–R6 |

La nota inicial identifica los meses descargados y los meses comunes. 2026 es parcial; los indicadores anuales comparan los mismos meses. Los gráficos mensuales no convierten meses ausentes en cero. Las propinas en efectivo no aparecen en los registros TLC. Las reglas y denominadores completos están en cada SQL y en la documentación del ejercicio 7.

La cobertura de la nota se detecta desde `data/raw/` al generar la especificación. Si se cambia la descarga, volver a materializar la base y publicar para mantener nota y consultas consistentes.

## API y comprobación

El script usa sesiones temporales, consultas nativas MBQL 5 y `PUT /api/dashboard/{id}` con `dashcards`, según el esquema de Metabase 0.63.19 disponible en [la documentación API local](http://localhost:3000/api/docs/) y [su OpenAPI JSON](http://localhost:3000/api/docs/openapi.json). El driver instalado anuncia `database_file` y `read_only` en `/api/session/properties`. No se usan tokens embebidos ni extracción de cookies.

Metabase advierte que su API puede cambiar entre versiones. Si cambia la imagen, revisar el esquema servido por la nueva instancia; consultar [la documentación API oficial](https://www.metabase.com/docs/latest/api) y [la introducción oficial a su API](https://www.metabase.com/learn/metabase-basics/administration/administration-and-operation/metabase-api).

Después de publicar, abrir la URL que imprime el script, comprobar que las seis gráficas y dos tablas cargan y capturar el tablero y la nota de cobertura para la entrega. `--dry-run` por sí solo no confirma publicación ni ejecución SQL.

## Prueba aislada de reproducción

En el host, con Docker abierto y cuando hayan terminado la materialización y los benchmarks:

```powershell
python docs/metabase/check_reproduction.py
```

La prueba inicia una segunda instancia temporal de la misma imagen en `127.0.0.1:3001`, monta los datos en solo lectura y crea su propia base de configuración dentro del contenedor. Crea una cuenta de prueba con contraseña aleatoria que permanece en memoria, publica dos veces, comprueba que los IDs no cambian y ejecuta las ocho consultas por la API. Al finalizar elimina exclusivamente el contenedor `lab8-metabase-repro-check` y guarda evidencia sin credenciales en `reproduction-check.json`.

Esta prueba requiere `requests` en el Python del host. No usa la cuenta del usuario, el puerto 3000 ni el volumen persistente de la instancia principal. El JSON de evidencia informa si la publicación, las consultas y la eliminación del contenedor terminaron correctamente.

La [comprobación registrada](reproduction-check.json) aprobó con Metabase **v0.63.19**: los IDs se conservaron tras dos publicaciones, quedaron ocho preguntas y una nota, y las ocho consultas devolvieron resultados con Yellow, Green y los tres años. El contenedor de prueba quedó eliminado. Sus tiempos HTTP describen esta comprobación y no sustituyen el benchmark del ejercicio 6.
