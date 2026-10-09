# Ejercicio 7 — Indicadores y tablero

Se definieron 12 preguntas y ocho indicadores. Las consultas están en `sql/07_*.sql` y los resultados ejecutados sobre los Parquet locales están en [resultados/indicadores](resultados/indicadores). El tablero de Metabase y su actualización a tres años se documentan en [ej8-tablero.md](ej8-tablero.md).

## Preguntas de análisis (7.1)

| Pregunta | Indicador que la responde | Motivo |
|---|---|---|
| P1. ¿Cómo cambia el volumen de viajes entre meses? | I1 | Identificar estacionalidad y cambios de actividad. |
| P2. ¿Qué participación tienen Yellow y Green en cada mes? | I1 | Evitar que el tamaño de Yellow oculte la evolución de Green. |
| P3. ¿Cuántos viajes se registran por día calendario? | I1 | Comparar meses de distinta duración. |
| P4. ¿Cómo cambia el monto cobrado total y diario? | I2 | Medir actividad económica registrada, con una definición explícita del monto. |
| P5. ¿Cómo cambia el ticket promedio en meses comparables? | I3 | Separar la variación del monto por viaje de la variación del volumen. |
| P6. ¿El viaje típico se vuelve más largo? | I4 | Describir cambios de distancia sin dejar que viajes extremos dominen el promedio. |
| P7. ¿El viaje típico tarda más y cambia su velocidad? | I4 | Comparar distancia, tiempo y velocidad conjuntamente. |
| P8. ¿Cómo cambia la mezcla de pagos y cuánto falta por identificar? | I5 | Hacer visible la pérdida de información en pagos NULL/0. |
| P9. ¿Qué propina se registra cuando el pago es con tarjeta? | I6 | Usar una población en la que el campo de propina es observable. |
| P10. ¿Qué proporción de pagos con tarjeta no registra propina? | I6 | Complementar la mediana con la frecuencia de ceros. |
| P11. ¿Cuáles son las principales zonas de recogida de cada taxi y año? | I7 | Identificar concentración geográfica y cambios del ranking. |
| P12. ¿Qué porcentaje del archivo original representan los indicadores? | I8 | Mostrar el efecto de las reglas de limpieza sobre la población analizada. |

## Población y comparabilidad

Fuente: `data/raw/yellow/<anio>/*.parquet`, `data/raw/green/<anio>/*.parquet` y el catálogo `data/raw/zones/taxi_zone_lookup.csv`. Se reutilizan las vistas `viajes`, `viajes_limpios` y `zonas` de [00_vistas.sql](../sql/00_vistas.sql). Las métricas de actividad usan `viajes_limpios`, con las reglas R1–R6 ya justificadas en el ejercicio 3: fecha dentro del mes de origen; duración positiva hasta 360 minutos; distancia positiva hasta 200 millas; tarifa y total positivos; total hasta 1,000 USD y velocidad hasta 80 mph. La limpieza no elimina duplicados ni exige conocer el pago o el número de pasajeros.

Los 64 archivos abarcan Yellow y Green de enero a diciembre de 2024 y 2025 y enero a agosto de 2026. I1, I2, I5 e I8 muestran toda la cobertura mensual. I3, I4, I6 e I7 calculan los meses presentes en **todas las combinaciones taxi-año** usando `viajes`, antes de aplicar la limpieza: actualmente enero–agosto. Por tanto, sus comparaciones anuales no enfrentan ocho meses con doce. El resultado incluye `meses_comunes`; no se escribe una lista fija de años o meses en el SQL. Si falta un archivo en un taxi, su mes se excluye del período común de ambos taxis.

El denominador diario usa los días calendario de los meses incluidos, aunque un día no tenga viajes. Enero–agosto tiene 244 días en 2024, año bisiesto, y 243 en 2025 y 2026. Los meses sin archivo no se representan como cero viajes.

## Definición y SQL de cada indicador (7.2, 7.3, 7.6, 7.7)

| Indicador | Cálculo y unidad | Archivo SQL y resultado | Visualización |
|---|---|---|---|
| I1. Volumen mensual | `count(*)`; viajes/día = viajes/días calendario; participación = viajes del taxi/todos los taxis del mes; variación contra el mismo mes del año anterior. | [SQL](../sql/07_01_volumen_mensual.sql), [CSV](resultados/indicadores/07_01_volumen_mensual.csv) | Línea temporal por taxi; revisar también porcentaje y variación. |
| I2. Monto cobrado mensual | `sum(total_amount)` en USD nominales; monto/día = suma/días calendario. Incluye tarifa, impuestos, peajes, recargos y propina registrada. | [SQL](../sql/07_02_monto_mensual.sql), [CSV](resultados/indicadores/07_02_monto_mensual.csv) | Línea temporal del monto diario por taxi. |
| I3. Ticket promedio | `avg(total_amount)` por taxi/año en período común. Reporta tarifa media, número de viajes y variación interanual del ticket y del volumen. | [SQL](../sql/07_03_ticket_periodo_comun.sql), [CSV](resultados/indicadores/07_03_ticket_periodo_comun.csv) | Barras año/taxi, USD por viaje. |
| I4. Viaje típico | Medianas aproximadas de distancia (millas), duración (minutos) y velocidad individual `trip_distance/(duracion_min/60)` (mph), en período común. | [SQL](../sql/07_04_viaje_tipico.sql), [CSV](resultados/indicadores/07_04_viaje_tipico.csv) | Barras de duración; las otras métricas quedan disponibles en la pregunta. |
| I5. Mezcla de pagos | Viajes por código/todos los viajes válidos del mismo taxi/mes, por 100. NULL/0 = sin detalle; códigos 5 y otros se conservan como categorías visibles. | [SQL](../sql/07_05_mezcla_pagos.sql), [CSV](resultados/indicadores/07_05_mezcla_pagos.csv) | Tabla mensual por taxi y categoría, o gráfico apilado con cada taxi separado. |
| I6. Propina con tarjeta | Solo `payment_type=1`, meses comunes. Mediana aproximada de `100*tip_amount/fare_amount`, promedio USD y porcentaje sin propina. Los ceros se incluyen; propinas nulas/negativas se excluyen de esas métricas y se cuentan aparte. | [SQL](../sql/07_06_propina_tarjeta.sql), [CSV](resultados/indicadores/07_06_propina_tarjeta.csv) | Barras de porcentaje de propina año/taxi. |
| I7. Zonas de recogida | Top 5 de `pu_location_id` por viajes para cada taxi/año en período común. `LEFT JOIN zonas` conserva IDs sin catálogo; el porcentaje usa todos los viajes, antes de limitar a cinco. | [SQL](../sql/07_07_zonas_top.sql), [CSV](resultados/indicadores/07_07_zonas_top.csv) | Tabla año/taxi/rango/zona/viajes/porcentaje. |
| I8. Retención tras limpieza | Viajes conservados/registros originales del mismo taxi/mes, por 100. También muestra registros descartados. | [SQL](../sql/07_08_retencion_limpieza.sql), [CSV](resultados/indicadores/07_08_retencion_limpieza.csv) | Línea mensual por taxi, porcentaje. |

Las medianas usan `approx_quantile`: son estimaciones sobre todos los viajes elegibles, no medianas exactas ni resultados de una muestra tomada por el script. Pueden variar ligeramente entre ejecuciones paralelas. La mediana de las velocidades individuales no es el cociente entre las medianas de distancia y duración.

## Resultados e interpretación (7.8)

Valores anuales en enero–agosto, derivados de I3 e I4:

| Taxi | Año | Viajes | Viajes/día | Ticket USD | Distancia mediana mi | Duración mediana min |
|---|---:|---:|---:|---:|---:|---:|
| Yellow | 2024 | 25,487,194 | 104,455.71 | 28.33 | 1.80 | 12.71 |
| Yellow | 2025 | 28,678,171 | 118,017.16 | 28.34 | 1.87 | 13.00 |
| Yellow | 2026 | 28,215,140 | 116,111.69 | 30.25 | 1.93 | 14.10 |
| Green | 2024 | 415,732 | 1,703.82 | 23.76 | 1.96 | 11.88 |
| Green | 2025 | 371,830 | 1,530.16 | 24.84 | 2.02 | 12.42 |
| Green | 2026 | 316,958 | 1,304.35 | 25.35 | 2.12 | 13.25 |

1. **Volumen (I1/I3):** Yellow crece 12.52 % en 2025 y cae 1.61 % en 2026; Green cae 10.56 % y 14.76 %. Usar toda la serie mensual permite comprobar si el cambio se concentra en algunos meses. La participación de Green en el período común pasa aproximadamente de 1.60 % a 1.11 %; comparar solo los totales combinados ocultaría su caída.
2. **Monto y ticket (I2/I3):** el ticket Yellow sube 6.75 % en 2026 frente a 2025 mientras baja el número de viajes. Su monto registrado de enero–agosto pasa de 812.71 a 853.56 millones USD. Green aumenta el ticket 2.06 %, pero su monto baja de 9.24 a 8.03 millones por la reducción del volumen. Es un monto cobrado registrado; no permite calcular utilidad, costos ni ingreso neto del conductor.
3. **Viaje típico (I4):** de 2024 a 2026 los viajes Yellow pasan de 1.80 a 1.93 millas y de 12.71 a 14.10 minutos. La velocidad mediana pasa de 9.52 a 9.27 mph: un ticket mayor coincide con viajes más largos, pero estas cifras descriptivas no identifican una causa única. La duración Green también aumenta.
4. **Pagos (I5):** ponderando por viajes, el porcentaje Yellow sin detalle de enero–agosto pasa de 8.99 % en 2024 a 19.61 % en 2025 y 24.93 % en 2026. En Green pasa de 4.04 % a 6.42 % y 13.46 %. El efectivo Yellow baja de 13.78 % a 9.05 %; Green, de 27.78 % a 19.70 %. No debe interpretarse toda esta caída como sustitución por tarjeta: cada vez hay más pagos sin detalle. La tabla mensual conserva estos registros en el denominador.
5. **Propinas (I6):** la propina mediana Yellow con tarjeta se mantiene alrededor del 26 % de la tarifa (25.93 %, 26.62 %, 26.42 %); Green ronda el 23.5 %. Los viajes Yellow con tarjeta y propina cero aumentan de 5.55 % a 8.87 %. En esta ejecución no hubo propinas nulas o negativas dentro de esa población. Estas cifras no describen las propinas en efectivo ni los registros sin detalle.
6. **Zonas (I7):** East Harlem North lidera Green en los tres años, con 23.22 %, 25.19 % y 27.40 % de sus viajes. El número de recogidas allí cae, de 96,534 a 86,855, mientras su participación crece: aumenta la concentración porque el resto cae más. Yellow pasa de Midtown Center en 2024/2025 a Upper East Side South en 2026; su zona líder representa cerca del 4.5 %, una distribución más dispersa.
7. **Retención (I8):** sumando originales y conservados de enero–agosto, Yellow conserva 96.59 %, 90.88 % y 94.99 %, frente a 93.76 %, 93.44 % y 94.02 % en Green. El deterioro de Yellow 2025 indica que la comparación económica depende también de los descartes de calidad. La retención se calcula como cociente de sumas, no como promedio simple de porcentajes mensuales.

## Límites de interpretación

- Los montos son USD nominales; no se ajustan por inflación. El cambio de ticket combina precios, duración, distancia, zonas y proporción de registros sin detalle.
- Los taxis de esta fuente no representan todos los modos de transporte ni todos los vehículos de NYC. Se reportan Yellow y Green por separado.
- La cobertura 2026 termina en agosto. Las curvas anuales no deben extrapolarse ni tratar septiembre–diciembre como ceros.
- `total_amount` no incorpora propinas en efectivo ausentes del registro y no mide utilidad del conductor. Se evita sumar de nuevo los componentes porque algunos registros tienen particularidades ya documentadas en el ejercicio 3.
- La limpieza define qué viajes entran al indicador; no demuestra que cada registro excluido sea inválido. I8 hace visible esta selección. No se corrige el conjunto por duplicados.
- Las categorías sin detalle se conservan; no se imputan formas de pago. Los rankings son de zonas de recogida, no de destino ni de conductores.

## Reproducción y evidencia (7.4, 7.5)

```bash
# Desde la raiz del repositorio, en el ambiente Docker ya configurado:
docker compose exec -T lab python scripts/export_indicators.py

# Verificar las invariantes entre los CSV, sin consultar la base:
docker compose exec -T lab python scripts/validate_indicators.py

# Ejecutar exactamente las consultas con el runner existente:
docker compose exec -T lab sh -c "python scripts/run_sql.py sql/07_*.sql --csv docs/resultados/indicadores"

# Reconstruir el alcance inicial de un solo anio, sin cambiar el SQL:
docker compose exec -T lab python scripts/export_indicators.py --anios 2026 --salida docs/resultados/indicadores-2026
```

`export_indicators.py` usa una conexión DuckDB en memoria y las vistas sobre Parquet; no abre ni escribe el archivo persistente de Metabase. Guarda ocho CSV y `manifest.json`, con cobertura taxi/año, meses comunes, versión DuckDB, cantidad de filas, tiempo y SHA-256 de cada SQL. Los tiempos de exportación son operativos, no sustituyen el benchmark del ejercicio 6. Para crear las preguntas y el tablero sobre la base materializada, seguir la evidencia y las instrucciones de [ej8-tablero.md](ej8-tablero.md).

La ejecución de `validate_indicators.py` aprobó diez comprobaciones sobre los CSV: hashes y conteos, cobertura mensual, consistencia del volumen y de la retención, días calendario, período común anual, población del viaje típico, pagos, propinas y rankings. El reporte [validation.json](resultados/indicadores/validation.json) registra 64 grupos mensuales y seis anuales. La validación lee resultados exportados y no abre la base persistente ni vuelve a ejecutar las consultas.
