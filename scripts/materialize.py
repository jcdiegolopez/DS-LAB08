#!/usr/bin/env python3
"""Crea la base persistente para el benchmark y Metabase.

Ejecutar desde el contenedor lab. Recrea SOLO las tablas/vistas del laboratorio;
Metabase debe estar desconectado de este archivo durante la escritura.
"""

import argparse
import hashlib
import json
import os
import platform
import time
from datetime import datetime, timezone
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
VIEWS = ROOT / "sql" / "00_vistas.sql"


def environment(threads: int, memory_limit: str) -> dict:
    return {
        "utc": datetime.now(timezone.utc).isoformat(),
        "python": platform.python_version(),
        "duckdb": duckdb.__version__,
        "platform": platform.platform(),
        "logical_cpus": os.cpu_count(),
        "threads": threads,
        "memory_limit": memory_limit,
        "meminfo": Path("/proc/meminfo").read_text() if Path("/proc/meminfo").exists() else None,
        "cgroup_memory_max": Path("/sys/fs/cgroup/memory.max").read_text().strip()
        if Path("/sys/fs/cgroup/memory.max").exists() else None,
        "cgroup_cpu_max": Path("/sys/fs/cgroup/cpu.max").read_text().strip()
        if Path("/sys/fs/cgroup/cpu.max").exists() else None,
    }


def manifest() -> list[dict]:
    files = sorted((ROOT / "data/raw").rglob("*.parquet"))
    zones = ROOT / "data/raw/zones/taxi_zone_lookup.csv"
    if zones.exists():
        files.append(zones)
    entries = []
    for path in files:
        digest = hashlib.sha256()
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        entries.append({"path": path.relative_to(ROOT).as_posix(), "bytes": path.stat().st_size,
                        "sha256": digest.hexdigest()})
    return entries


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=ROOT / "data/processed/taxi.duckdb")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/resultados/benchmark")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--memory-limit", default="4GB")
    args = parser.parse_args()
    args.database = args.database.resolve()
    args.output = args.output.resolve()
    os.chdir(ROOT)
    args.database.parent.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    source_sql = VIEWS.read_text(encoding="utf-8")
    clean_view_sql = source_sql[source_sql.index("CREATE OR REPLACE VIEW viajes_limpios AS"):]
    source_manifest = manifest()
    metadata = {"environment": environment(args.threads, args.memory_limit), "source_manifest": source_manifest,
                "views_sql_sha256": hashlib.sha256(source_sql.encode()).hexdigest(),
                "database": args.database.relative_to(ROOT).as_posix(),
                "source_parquet_bytes": sum(e["bytes"] for e in source_manifest if e["path"].endswith(".parquet"))}
    start = time.perf_counter()
    with duckdb.connect(str(args.database)) as con:
        con.execute("SET threads = ?", [args.threads])
        con.execute("SET memory_limit = ?", [args.memory_limit])
        con.execute("SET preserve_insertion_order = false")
        # Incluye las vistas de origen: un rebuild fallido debe restaurar tambien
        # las vistas persistentes anteriores, sin volver a apuntarlas a raw.
        con.execute("BEGIN TRANSACTION")
        try:
            con.execute(source_sql)
            build_start = time.perf_counter()
            con.execute("CREATE OR REPLACE TABLE viajes_materializados AS SELECT * FROM viajes")
            metadata["create_trips_seconds"] = time.perf_counter() - build_start
            con.execute("CREATE OR REPLACE TABLE zonas_materializadas AS SELECT * FROM zonas")
            con.execute("""CREATE OR REPLACE VIEW viajes AS
                SELECT * FROM viajes_materializados
                WHERE getvariable('anios') IS NULL
                   OR list_contains(getvariable('anios'), anio_archivo)""")
            con.execute(clean_view_sql)
            con.execute("CREATE OR REPLACE VIEW zonas AS SELECT * FROM zonas_materializadas")
            con.execute("DROP VIEW yellow_raw")
            con.execute("DROP VIEW green_raw")
            con.execute("COMMIT")
        except Exception:
            con.execute("ROLLBACK")
            raise
        con.execute("CHECKPOINT")
        metadata["materialization_seconds_including_checkpoint"] = time.perf_counter() - start
        metadata["columns"] = [dict(zip(["name", "type", "null", "key", "default", "extra"], row))
                               for row in con.execute("DESCRIBE viajes_materializados").fetchall()]
        rows = con.execute("""SELECT taxi, anio_archivo, count(*) AS rows, count(DISTINCT archivo) AS files
                              FROM viajes_materializados GROUP BY ALL ORDER BY taxi, anio_archivo""").fetchall()
        metadata["rows_by_taxi_year"] = [dict(zip(["taxi", "year", "rows", "files"], row)) for row in rows]
        metadata["clean_rows_by_taxi_year"] = [dict(zip(["taxi", "year", "rows"], row)) for row in con.execute(
            "SELECT taxi, anio_archivo, count(*) FROM viajes_limpios GROUP BY ALL ORDER BY taxi, anio_archivo").fetchall()]
        metadata["zones_rows"] = con.execute("SELECT count(*) FROM zonas").fetchone()[0]
        metadata["persistent_views"] = [dict(zip(["name", "sql"], row)) for row in con.execute(
            "SELECT view_name, sql FROM duckdb_views() WHERE NOT internal ORDER BY view_name").fetchall()]
        forbidden = [v["name"] for v in metadata["persistent_views"] if "read_parquet(" in v["sql"] or "read_csv(" in v["sql"]]
        if forbidden:
            raise RuntimeError(f"Vistas aun dependientes de raw: {forbidden}")
    metadata["database_bytes"] = args.database.stat().st_size
    (args.output / "materialization.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"database": str(args.database), "seconds": metadata["materialization_seconds_including_checkpoint"],
                      "rows": sum(r["rows"] for r in metadata["rows_by_taxi_year"]),
                      "bytes": metadata["database_bytes"], "views": [v["name"] for v in metadata["persistent_views"]]}), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
