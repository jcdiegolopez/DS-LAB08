#!/usr/bin/env python3
"""Comprueba invariantes entre los CSV de indicadores, sin consultar la base.

Uso: docker compose exec -T lab python scripts/validate_indicators.py
"""

import argparse
import csv
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directorio", type=Path, default=ROOT / "docs/resultados/indicadores")
    args = parser.parse_args()
    directory = args.directorio.resolve()
    manifest = json.loads((directory / "manifest.json").read_text(encoding="utf-8"))
    expected = {(c["taxi"], str(c["anio"]), str(m))
                for c in manifest["cobertura"] for m in c["meses"]}
    results = {}
    for query in manifest["consultas"]:
        path = directory / query["csv"]
        with path.open(encoding="utf-8", newline="") as handle:
            data = list(csv.DictReader(handle))
        assert len(data) == query["filas"], f"Filas cambiaron: {path.name}"
        sql_text = (ROOT / query["sql"]).read_text(encoding="utf-8")
        sql_hash = hashlib.sha256(sql_text.encode("utf-8")).hexdigest()
        assert sql_hash == query["sha256"], f"SQL cambió desde la exportación: {query['sql']}"
        results[path.stem[:5]] = data

    def monthly(index):
        data = results[index]
        keyed = {(r["taxi"], r["anio"], r["mes"]): r for r in data}
        assert len(keyed) == len(data), f"Mes duplicado: {index}"
        assert set(keyed) == expected, f"Cobertura mensual incompleta: {index}"
        return keyed

    volumes, amounts, retention = (monthly(i) for i in ("07_01", "07_02", "07_08"))
    for key, row in volumes.items():
        count = int(row["viajes"])
        assert count == int(amounts[key]["viajes"]) == int(retention[key]["viajes_conservados"])
        original, discarded = (int(retention[key][c]) for c in ("registros_originales", "registros_descartados"))
        assert count + discarded == original and 0 <= count <= original
        assert math.isclose(float(row["viajes_por_dia"]), count / int(row["dias_calendario"]), abs_tol=0.0051)
        assert math.isclose(float(retention[key]["pct_conservado"]), 100 * count / original, abs_tol=0.00051)

    common = {str(month) for month in manifest["meses_comunes"]}
    annual = {(r["taxi"], r["anio"]): r for r in results["07_03"]}
    expected_annual = {(c["taxi"], str(c["anio"])) for c in manifest["cobertura"]}
    assert len(annual) == len(results["07_03"]) and set(annual) == expected_annual
    for key, row in annual.items():
        selected = [r for k, r in volumes.items() if k[:2] == key and k[2] in common]
        assert int(row["viajes"]) == sum(int(r["viajes"]) for r in selected)
        assert int(float(row["dias_calendario"])) == sum(int(r["dias_calendario"]) for r in selected)
    typical = {(r["taxi"], r["anio"]): r for r in results["07_04"]}
    assert len(typical) == len(results["07_04"]) and set(typical) == expected_annual
    for row in typical.values():
        assert int(row["viajes"]) == int(annual[row["taxi"], row["anio"]]["viajes"])

    payments = defaultdict(list)
    for row in results["07_05"]:
        payments[row["taxi"], row["anio"], row["mes"]].append(row)
    assert set(payments) == expected
    for key, rows in payments.items():
        assert sum(int(r["viajes"]) for r in rows) == int(volumes[key]["viajes"])
        assert abs(sum(float(r["pct_viajes"]) for r in rows) - 100) <= len(rows) * 0.00051
    expected_card_trips = defaultdict(int)
    for row in results["07_05"]:
        if row["metodo_pago"] == "Tarjeta" and row["mes"] in common:
            expected_card_trips[row["taxi"], row["anio"]] += int(row["viajes"])
    tips = {(r["taxi"], r["anio"]): r for r in results["07_06"]}
    assert len(tips) == len(results["07_06"]) and set(tips) == set(expected_card_trips)
    for key, row in tips.items():
        assert int(row["viajes_tarjeta"]) == expected_card_trips[key]
        assert int(row["viajes_propina_valida"]) + int(row["propinas_excluidas"]) == int(row["viajes_tarjeta"])
    ranks = defaultdict(list)
    for row in results["07_07"]:
        ranks[row["taxi"], row["anio"]].append(int(row["rango"]))
        assert 0 <= float(row["pct_viajes"]) <= 100
    assert set(ranks) == set(annual)
    assert all(sorted(values) == list(range(1, len(values) + 1)) and len(values) <= 5 for values in ranks.values())

    report = {"passed": True, "monthly_groups": len(expected), "annual_groups": len(annual),
              "common_months": manifest["meses_comunes"],
              "checks": ["SQL hashes and exported row counts", "monthly coverage and uniqueness",
                         "volumes equal retained records", "original = retained + discarded",
                         "calendar denominators", "annual common-period volume and days",
                         "typical-trip population", "payment counts and percentage totals",
                         "valid + excluded tips = card trips", "top-five ranks and percentages"]}
    (directory / "validation.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
