#!/usr/bin/env python3
"""Exporta los ocho indicadores a CSV desde Parquet, sin abrir una base persistente.

Uso desde la raiz del proyecto:
    docker compose exec -T lab python scripts/export_indicators.py
    docker compose exec -T lab python scripts/export_indicators.py --anios 2026 --salida docs/resultados/indicadores-2026

Las consultas son las mismas que utiliza Metabase sobre la base materializada.
El manifiesto registra cobertura, meses comunes, version y hashes del SQL.
"""

import argparse
import hashlib
import json
import os
import time
from datetime import datetime, timezone
from pathlib import Path

import duckdb

from run_sql import RAIZ, conectar


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--anios", type=int, nargs="+", help="limitar los anios leidos")
    parser.add_argument("--salida", type=Path, default=RAIZ / "docs/resultados/indicadores")
    args = parser.parse_args()
    salida = args.salida.resolve()
    salida.mkdir(parents=True, exist_ok=True)
    os.chdir(RAIZ)
    archivos = sorted((RAIZ / "sql").glob("07_*.sql"))
    if len(archivos) < 6:
        raise RuntimeError("Se requieren al menos seis consultas sql/07_*.sql.")

    con = conectar(args.anios)
    try:
        cobertura = con.execute(
            "SELECT taxi, anio_archivo, list(DISTINCT mes_archivo ORDER BY mes_archivo), "
            "count(DISTINCT archivo) FROM viajes GROUP BY taxi, anio_archivo "
            "ORDER BY taxi, anio_archivo"
        ).fetchall()
        meses_comunes = sorted(set.intersection(*(set(fila[2]) for fila in cobertura)))
        manifiesto = {
            "generado_utc": datetime.now(timezone.utc).isoformat(),
            "duckdb_version": duckdb.__version__,
            "origen": "Parquet mediante sql/00_vistas.sql; conexion en memoria",
            "anios_solicitados": sorted(set(args.anios)) if args.anios else None,
            "cobertura": [
                {"taxi": taxi, "anio": anio, "meses": meses, "archivos": n}
                for taxi, anio, meses, n in cobertura
            ],
            "meses_comunes": meses_comunes,
            "moneda": "USD nominales; total_amount no es utilidad del conductor",
            "limpieza": "R1-R6 de sql/00_vistas.sql; no elimina duplicados",
            "consultas": [],
        }
        for archivo in archivos:
            sql = archivo.read_text(encoding="utf-8")
            inicio = time.perf_counter()
            tabla = con.execute(sql).fetchdf()
            segundos = time.perf_counter() - inicio
            csv = salida / f"{archivo.stem}.csv"
            tabla.to_csv(csv, index=False)
            manifiesto["consultas"].append({
                "sql": archivo.relative_to(RAIZ).as_posix(),
                "sha256": hashlib.sha256(sql.encode("utf-8")).hexdigest(),
                "csv": csv.name,
                "filas": len(tabla),
                "columnas": list(tabla.columns),
                "segundos": round(segundos, 4),
            })
            print(f"{archivo.name}: {len(tabla)} filas en {segundos:.2f} s -> {csv}", flush=True)
        (salida / "manifest.json").write_text(
            json.dumps(manifiesto, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        print(f"Meses comunes: {meses_comunes}; manifiesto: {salida / 'manifest.json'}", flush=True)
    finally:
        con.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
