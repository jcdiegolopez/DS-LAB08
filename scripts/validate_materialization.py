"""Regresion de rebuild atomico; usa solo datos sinteticos y una base temporal.

Ejecutar: docker compose exec -T lab python scripts/validate_materialization.py -v
"""

import contextlib
import importlib.util
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import duckdb


REPO = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("materialize", REPO / "scripts/materialize.py")
materialize = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(materialize)
SOURCE_SQL = (REPO / "sql/00_vistas.sql").read_text(encoding="utf-8")


class MaterializationAtomicityTest(unittest.TestCase):
    def write_inputs(self, root: Path, yellow_rows: int, fare: int) -> None:
        """Un archivo por taxi, todos los registros pasan R1-R6."""
        for taxi, pickup_prefix in (("yellow", "tpep"), ("green", "lpep")):
            folder = root / "data/raw" / taxi / "2026"
            folder.mkdir(parents=True, exist_ok=True)
            target = folder / f"{taxi}_tripdata_2026-01.parquet"
            count = yellow_rows if taxi == "yellow" else 1
            extra_column = "0.0::DOUBLE AS Airport_fee" if taxi == "yellow" else "1::BIGINT AS trip_type"
            with duckdb.connect() as con:
                con.execute(f"""COPY (
                    SELECT 1::BIGINT AS VendorID,
                           TIMESTAMP '2026-01-10 10:00:00' AS {pickup_prefix}_pickup_datetime,
                           TIMESTAMP '2026-01-10 10:10:00' AS {pickup_prefix}_dropoff_datetime,
                           1::BIGINT AS passenger_count, 2.0::DOUBLE AS trip_distance,
                           1::BIGINT AS RatecodeID, 'N' AS store_and_fwd_flag,
                           1::BIGINT AS PULocationID, 1::BIGINT AS DOLocationID,
                           1::BIGINT AS payment_type, {fare}::DOUBLE AS fare_amount,
                           0.0::DOUBLE AS extra, 0.5::DOUBLE AS mta_tax,
                           2.0::DOUBLE AS tip_amount, 0.0::DOUBLE AS tolls_amount,
                           1.0::DOUBLE AS improvement_surcharge,
                           {fare + 4}::DOUBLE AS total_amount,
                           0.0::DOUBLE AS congestion_surcharge,
                           {extra_column}, 0.0::DOUBLE AS cbd_congestion_fee,
                           'test' AS request_source
                    FROM range({count})
                ) TO ? (FORMAT PARQUET)""", [str(target)])
        zones = root / "data/raw/zones/taxi_zone_lookup.csv"
        zones.parent.mkdir(parents=True, exist_ok=True)
        zones.write_text("LocationID,Borough,Zone,service_zone\n1,Manhattan,Fixture,Yellow Zone\n", encoding="utf-8")

    def invoke(self, root: Path) -> int:
        original_cwd = Path.cwd()
        try:
            with patch.object(materialize, "ROOT", root), \
                    patch.object(materialize, "VIEWS", root / "sql/00_vistas.sql"), \
                    patch.object(sys, "argv", ["materialize.py", "--threads", "1", "--memory-limit", "128MB"]), \
                    contextlib.redirect_stdout(io.StringIO()):
                return materialize.main()
        finally:
            os.chdir(original_cwd)

    def test_failed_rebuild_restores_tables_and_persistent_views(self) -> None:
        with tempfile.TemporaryDirectory(prefix="lab8-materialize-regression-") as folder:
            root = Path(folder)
            (root / "sql").mkdir()
            (root / "sql/00_vistas.sql").write_text(SOURCE_SQL, encoding="utf-8")
            self.write_inputs(root, yellow_rows=1, fare=10)
            self.assertEqual(self.invoke(root), 0)
            database = root / "data/processed/taxi.duckdb"

            def snapshot():
                with duckdb.connect(str(database), read_only=True) as con:
                    return {
                        "views": con.execute("SELECT view_name, sql FROM duckdb_views() WHERE NOT internal ORDER BY view_name").fetchall(),
                        "trips": con.execute("SELECT * FROM viajes_materializados ORDER BY taxi, pickup").fetchall(),
                        "clean": con.execute("SELECT taxi, count(*), sum(total_amount) FROM viajes_limpios GROUP BY taxi ORDER BY taxi").fetchall(),
                        "zones": con.execute("SELECT * FROM zonas ORDER BY location_id").fetchall(),
                    }

            before = snapshot()
            self.assertEqual(len(before["trips"]), 2)
            self.write_inputs(root, yellow_rows=2, fare=20)
            real_connect = duckdb.connect
            observed_new_raw_counts = []

            class FailAfterSourceViews:
                def __init__(self, con):
                    self.con = con

                def __enter__(self):
                    return self

                def __exit__(self, *args):
                    return self.con.__exit__(*args)

                def execute(self, sql, *args):
                    if sql.startswith("CREATE OR REPLACE TABLE viajes_materializados"):
                        # Confirma que el main ya sustituyo las vistas por el origen nuevo.
                        observed_new_raw_counts.append(self.con.execute("SELECT count(*) FROM viajes").fetchone()[0])
                        return self.con.execute("SELECT error('injected failure after source views')")
                    return self.con.execute(sql, *args)

            with patch.object(materialize.duckdb, "connect", side_effect=lambda *a, **kw: FailAfterSourceViews(real_connect(*a, **kw))):
                with self.assertRaisesRegex(duckdb.Error, "injected failure after source views"):
                    self.invoke(root)

            self.assertEqual(observed_new_raw_counts, [3])
            # Incluye definiciones SQL: el rollback no debe dejar yellow_raw/green_raw
            # ni reemplazar viajes por una vista que lea los nuevos Parquet.
            self.assertEqual(snapshot(), before)
            # Rebuild exitoso despues de la falla incorpora el nuevo snapshot.
            self.assertEqual(self.invoke(root), 0)
            after = snapshot()
            self.assertEqual(len(after["trips"]), 3)
            self.assertEqual(sum(row[1] for row in after["clean"]), 3)
            self.assertEqual([name for name, _ in after["views"]], ["viajes", "viajes_limpios", "zonas"])


if __name__ == "__main__":
    unittest.main()
