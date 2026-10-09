#!/usr/bin/env python3
"""Ejecuta consultas SQL del laboratorio con DuckDB sobre los archivos Parquet.

Antes de cada consulta se carga `sql/00_vistas.sql`, que define las vistas
sobre `data/raw/` (no se importa nada a una tabla). Cada archivo de `sql/`
contiene una sola consulta.

Uso (desde la raiz del repositorio, dentro del contenedor):
    python scripts/run_sql.py sql/03_01_archivos.sql
    python scripts/run_sql.py sql/03_*.sql sql/04_*.sql
    python scripts/run_sql.py sql/04_*.sql --anios 2026 --csv docs/resultados/2026

Sin --anios se consultan todos los archivos descargados. Con --anios solo se
leen los anios indicados (variable `anios` de sql/00_vistas.sql); la consulta
no cambia.

Con --csv, el resultado de cada consulta se guarda como <nombre>.csv en la
carpeta indicada, para poder citarlo en la documentacion.
"""

import argparse
import os
import sys
import time
from pathlib import Path

import duckdb

RAIZ = Path(__file__).resolve().parent.parent
VISTAS = RAIZ / "sql" / "00_vistas.sql"


def conectar(anios: list[int] | None = None) -> duckdb.DuckDBPyConnection:
    """Conexion en memoria con las vistas del laboratorio ya definidas.

    Si se indican `anios`, las vistas solo leen los archivos de esos anios.
    Debe llamarse con el directorio de trabajo en la raiz del repositorio.
    """
    con = duckdb.connect()
    con.execute(VISTAS.read_text(encoding="utf-8"))
    if anios:
        con.execute("SET VARIABLE anios = ?", [sorted(set(anios))])
    return con


def main() -> int:
    parser = argparse.ArgumentParser(description="Ejecuta archivos .sql con DuckDB.")
    parser.add_argument("archivos", nargs="+", type=Path, help="archivos .sql a ejecutar")
    parser.add_argument("--csv", type=Path, help="carpeta donde guardar cada resultado en CSV")
    parser.add_argument("--anios", type=int, nargs="+", help="limita las vistas a estos anios")
    parser.add_argument("--filas", type=int, default=40, help="filas a mostrar (por defecto 40)")
    argumentos = parser.parse_args()

    # Las rutas que recibe el script se resuelven antes de cambiar de carpeta:
    # las vistas usan rutas relativas a la raiz del repositorio.
    archivos = [archivo.resolve() for archivo in argumentos.archivos]
    salida_csv = argumentos.csv.resolve() if argumentos.csv else None
    os.chdir(RAIZ)

    con = conectar(argumentos.anios)
    if salida_csv:
        salida_csv.mkdir(parents=True, exist_ok=True)

    for archivo in archivos:
        if archivo == VISTAS:
            continue
        consulta = archivo.read_text(encoding="utf-8")
        inicio = time.perf_counter()
        resultado = con.sql(consulta)
        tabla = resultado.fetchdf()
        segundos = time.perf_counter() - inicio

        print(f"\n### {archivo.name}  ({len(tabla)} filas, {segundos:.2f} s)")
        print(tabla.head(argumentos.filas).to_string(index=False, max_colwidth=60))
        if salida_csv:
            tabla.to_csv(salida_csv / f"{archivo.stem}.csv", index=False)

    return 0


if __name__ == "__main__":
    sys.exit(main())
