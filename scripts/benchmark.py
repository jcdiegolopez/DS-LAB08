#!/usr/bin/env python3
"""Compara Parquet directo con tablas DuckDB; captura tiempo hasta fetchall.

Mantener Metabase sin consultar mientras se mide. No elimina la cache del SO.
Primera corrida registrada y >=5 repeticiones calientes, orden alternado.
"""

import argparse
import csv
import json
import math
import os
import statistics
import time
from pathlib import Path

import duckdb

from materialize import ROOT, VIEWS, environment

DATASETS = (("1_anio", [2026]), ("2_anios", [2024, 2026]), ("3_anios", [2024, 2025, 2026]))


def compare(expected, actual) -> tuple[float, float]:
    """Exactitud para cuentas/texto; floats toleran reordenamiento paralelo."""
    max_abs, max_rel = 0.0, 0.0

    def check(left, right, location):
        nonlocal max_abs, max_rel
        if isinstance(left, (list, tuple)):
            if not isinstance(right, (list, tuple)) or len(left) != len(right):
                raise AssertionError(f"Longitud distinta: {location}")
            for index, (a, b) in enumerate(zip(left, right)):
                check(a, b, f"{location}/{index}")
        elif isinstance(left, float) or isinstance(right, float):
            if left is None or right is None or not math.isclose(left, right, rel_tol=1e-10, abs_tol=1e-8):
                raise AssertionError(f"Diferencia numerica {location}: {left!r} != {right!r}")
            absolute = abs(left - right)
            max_abs = max(max_abs, absolute)
            max_rel = max(max_rel, absolute / max(abs(left), abs(right), 1e-30))
        elif left != right:
            raise AssertionError(f"Diferencia {location}: {left!r} != {right!r}")

    check(expected, actual, "resultado")
    return max_abs, max_rel


def write_csv(path: Path, columns, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(columns)
        writer.writerows(rows)


def run(con, sql):
    start = time.perf_counter()
    cursor = con.execute(sql)
    rows = cursor.fetchall()
    elapsed = time.perf_counter() - start
    return elapsed, [item[0] for item in cursor.description], rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, default=ROOT / "data/processed/taxi.duckdb")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/resultados/benchmark")
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument("--memory-limit", default="4GB")
    parser.add_argument("--repetitions", type=int, default=5)
    args = parser.parse_args()
    if args.repetitions < 5:
        parser.error("--repetitions debe ser >=5")
    args.database, args.output = args.database.resolve(), args.output.resolve()
    os.chdir(ROOT)
    args.output.mkdir(parents=True, exist_ok=True)
    queries = sorted((ROOT / "sql").glob("06_*.sql"))
    if not queries:
        parser.error("No se encontraron consultas sql/06_*.sql")
    metadata = {"environment": environment(args.threads, args.memory_limit),
                "database_bytes": args.database.stat().st_size, "repetitions": args.repetitions,
                "datasets": [{"name": name, "years": years} for name, years in DATASETS],
                "timing": "perf_counter around execute + fetchall; setup, validation and CSV writing excluded",
                "cache": "No OS cache eviction. First recorded execution is not guaranteed cold; later executions warm.",
                "float_tolerance": {"relative": 1e-10, "absolute": 1e-8},
                "ordering": "Alternate Parquet/table on each repetition; initial order alternates by dataset/query."}
    raw = duckdb.connect()
    table = duckdb.connect(str(args.database), read_only=True)
    connections = {"parquet": raw, "tabla": table}
    measurements, summary, checks = [], [], []
    try:
        for con in connections.values():
            con.execute("SET threads = ?", [args.threads])
            con.execute("SET memory_limit = ?", [args.memory_limit])
            con.execute("SET preserve_insertion_order = false")
        raw.execute(VIEWS.read_text(encoding="utf-8"))
        for dataset_index, (dataset, years) in enumerate(DATASETS):
            for con in connections.values():
                con.execute("SET VARIABLE anios = ?", [years])
            raw_bytes = sum(p.stat().st_size for taxi in ("yellow", "green") for year in years
                            for p in (ROOT / "data/raw" / taxi / str(year)).glob("*.parquet"))
            dataset_rows = table.execute("SELECT count(*) FROM viajes").fetchone()[0]
            for query_index, path in enumerate(queries):
                sql = path.read_text(encoding="utf-8")
                first_order = ["parquet", "tabla"] if (dataset_index + query_index) % 2 == 0 else ["tabla", "parquet"]
                reference, reference_columns = None, None
                first_times, hot_times = {}, {"parquet": [], "tabla": []}
                for repetition in range(args.repetitions + 1):
                    order = first_order if repetition % 2 == 0 else first_order[::-1]
                    for position, strategy in enumerate(order):
                        seconds, columns, result = run(connections[strategy], sql)
                        if reference is None:
                            reference, reference_columns = result, columns
                        if columns != reference_columns:
                            raise AssertionError(f"Columnas distintas: {dataset}/{path.name}/{strategy}")
                        max_abs, max_rel = compare(reference, result)
                        phase = "primera" if repetition == 0 else "caliente"
                        measurements.append([dataset, "+".join(map(str, years)), path.stem, strategy, phase,
                                             repetition, position + 1, seconds, len(result), dataset_rows, raw_bytes])
                        checks.append({"dataset": dataset, "query": path.stem, "strategy": strategy,
                                       "phase": phase, "repetition": repetition, "rows": len(result),
                                       "equal": True, "max_abs_float_difference": max_abs,
                                       "max_relative_float_difference": max_rel})
                        if repetition == 0:
                            first_times[strategy] = seconds
                            write_csv(args.output / f"{dataset}_{path.stem}_{strategy}.csv", columns, result)
                        else:
                            hot_times[strategy].append(seconds)
                        print(f"{dataset} {path.stem} {strategy} {phase} {repetition}: {seconds:.3f}s, {len(result)} filas, equivalencia OK", flush=True)
                    write_csv(args.output / "measurements.csv",
                              ["dataset", "years", "query", "strategy", "phase", "repetition", "order_position",
                               "seconds", "result_rows", "source_rows", "parquet_bytes"], measurements)
                med_raw, med_table = statistics.median(hot_times["parquet"]), statistics.median(hot_times["tabla"])
                summary.append([dataset, "+".join(map(str, years)), path.stem, dataset_rows, raw_bytes,
                                first_times["parquet"], first_times["tabla"], med_raw, med_table, med_raw / med_table,
                                min(hot_times["parquet"]), max(hot_times["parquet"]),
                                min(hot_times["tabla"]), max(hot_times["tabla"]), args.repetitions])
                write_csv(args.output / "summary.csv",
                          ["dataset", "years", "query", "source_rows", "parquet_bytes", "first_parquet_seconds",
                           "first_table_seconds", "median_parquet_seconds", "median_table_seconds", "speedup_parquet_over_table",
                           "min_parquet_seconds", "max_parquet_seconds", "min_table_seconds", "max_table_seconds", "repetitions"], summary)
                (args.output / "equivalence.json").write_text(json.dumps(checks, indent=2) + "\n", encoding="utf-8")
    finally:
        raw.close()
        table.close()
        (args.output / "environment.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    print(f"Benchmark terminado: {len(measurements)} mediciones; {len(checks)} validaciones.", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
