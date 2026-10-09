#!/usr/bin/env python3
"""Prueba el publicador en un Metabase efímero separado, con datos solo lectura.

Ejecutar desde el host cuando no haya materialización/benchmark activos.
No usa la cuenta, el puerto ni el volumen de Metabase del usuario.
"""

from __future__ import annotations

import argparse
import contextlib
import json
import secrets
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from publish_metabase import MetabaseAPI, PublishError, build_spec, publish, rows, write_json  # noqa: E402

CONTAINER = "lab8-metabase-repro-check"


def docker(*args: str) -> str:
    result = subprocess.run(["docker", *args], capture_output=True, text=True, check=False)
    if result.returncode:
        # Docker arguments have no secrets, but engine diagnostics are not needed.
        raise PublishError(f"Docker no pudo ejecutar {args[0]} en el contenedor de prueba.")
    return result.stdout.strip()


def wait_until_ready(base_url: str, deadline_seconds: int = 240) -> None:
    deadline = time.monotonic() + deadline_seconds
    while time.monotonic() < deadline:
        with contextlib.suppress(requests.RequestException, ValueError):
            response = requests.get(base_url + "/api/health", timeout=3)
            if response.ok and response.json().get("status") == "ok":
                return
        time.sleep(2)
    raise PublishError("Metabase de prueba no completó el inicio dentro del plazo.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", default="ds-lab08-metabase")
    parser.add_argument("--port", type=int, default=3001)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/metabase/reproduction-check.json")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535 or args.port == 3000:
        parser.error("usar un puerto 1024–65535 distinto de 3000")
    if not (ROOT / "data/processed/taxi.duckdb").is_file():
        parser.error("falta data/processed/taxi.duckdb; completar materialización")
    found = subprocess.run(["docker", "container", "inspect", CONTAINER],
                           capture_output=True, check=False)
    if found.returncode == 0:
        parser.error(f"ya existe {CONTAINER}; no se tocará ese contenedor")
    base_url = f"http://127.0.0.1:{args.port}"
    created = False
    api = None
    evidence = {"checked_at_utc": datetime.now(timezone.utc).isoformat(),
                "isolation": {"container": CONTAINER, "port": args.port,
                              "data_mount": "read-only", "app_database": "/tmp/repro-check/metabase.db",
                              "production_account_used": False, "production_volume_used": False}}
    try:
        image_id = docker("image", "inspect", args.image, "--format", "{{.Id}}")
        docker("run", "--detach", "--name", CONTAINER, "--cpus", "4", "--memory", "6g",
               "--publish", f"127.0.0.1:{args.port}:3000",
               "--env", "MB_DB_FILE=/tmp/repro-check/metabase.db",
               "--env", "MB_ANON_TRACKING_ENABLED=false",
               "--env", "JAVA_TOOL_OPTIONS=-Xmx768m",
               "--mount", f"type=bind,source={ROOT / 'data'},target=/workspace/data,readonly",
               args.image)
        created = True
        print("Instancia efímera iniciada; esperando API.", flush=True)
        wait_until_ready(base_url)
        api = MetabaseAPI(base_url)
        properties = api.call("GET", "/api/session/properties")
        setup_token = properties.get("setup-token")
        if not setup_token:
            raise PublishError("La instancia efímera no devolvió un token de configuración.")
        # La contraseña y los tokens solo viven en memoria y nunca van a Docker,
        # archivos, argumentos de proceso o los mensajes de la prueba.
        password = secrets.token_urlsafe(36) + "!Aa9"
        username = "prueba@example.invalid"
        api.call("POST", "/api/setup", json={"token": setup_token,
                 "prefs": {"site_name": "Lab 8 · validación efímera", "site_locale": "es"},
                 "user": {"email": username, "first_name": "Prueba", "last_name": "Efímera", "password": password}})
        del setup_token
        api.login(username, password)
        del password
        spec = build_spec()
        first = publish(api, spec)
        second = publish(api, spec)
        # URLs y los IDs pertenecen a la misma instancia efímera.
        assert first == second, "Los IDs cambiaron al repetir la publicación."
        dashboard = api.call("GET", f"/api/dashboard/{second['dashboard_id']}")
        cards = dashboard.get("dashcards", [])
        assert len(cards) == 9, "Se esperaban ocho preguntas y una nota."
        assert sum(c.get("card_id") is not None for c in cards) == 8
        assert sum(c.get("card_id") is None for c in cards) == 1
        collection_items = rows(api.call("GET", f"/api/collection/{second['collection_id']}/items",
                                        params={"show_dashboard_questions": "true"}))
        assert sum(item.get("model") == "card" for item in collection_items) == 8
        assert sum(item.get("model") == "dashboard" for item in collection_items) == 1
        query_checks = []
        for card in spec["cards"]:
            card_id = second["card_ids"][card["key"]]
            saved = api.call("GET", f"/api/card/{card_id}")
            assert saved["display"] == card["display"]
            assert saved["collection_id"] == second["collection_id"]
            started = time.perf_counter()
            result = api.call("POST", f"/api/card/{card_id}/query", json={"ignore_cache": True})
            elapsed = time.perf_counter() - started
            assert result.get("status") == "completed", f"Consulta incompleta: {card['key']}"
            data = result["data"]
            assert data["rows"], f"Consulta sin filas: {card['key']}"
            columns = [column["name"] for column in data["cols"]]
            metric = card["visualization_settings"].get("graph.metrics", [])
            dimensions = card["visualization_settings"].get("graph.dimensions", [])
            assert all(name in columns for name in metric + dimensions)
            assert "anio" in columns and "taxi" in columns
            year_index, taxi_index = columns.index("anio"), columns.index("taxi")
            years = sorted({row[year_index] for row in data["rows"]})
            taxis = sorted({row[taxi_index] for row in data["rows"]})
            assert years == [2024, 2025, 2026] and taxis == ["green", "yellow"]
            query_checks.append({"key": card["key"], "display": card["display"],
                                 "status": "completed", "rows": len(data["rows"]),
                                 "columns": columns, "years": years, "taxis": taxis,
                                 "seconds": round(elapsed, 3)})
            print(f"Consulta verificada: {card['key']} ({len(data['rows'])} filas).", flush=True)
        evidence.update({"status": "passed", "image_id": image_id,
                         "metabase_version": properties.get("version", {}).get("tag"),
                         "same_ids_after_two_publications": True,
                         "counts": {"saved_questions": 8, "charts": 6, "tables": 2, "notes": 1, "dashboards": 1},
                         "queries": query_checks})
    except (PublishError, AssertionError, OSError, KeyError) as error:
        evidence.update({"status": "failed", "error": str(error)})
        print(f"Error en prueba: {error}", file=sys.stderr)
    finally:
        if api:
            api.close()
        if created:
            try:
                docker("rm", "--force", CONTAINER)
                evidence["ephemeral_container_removed"] = True
            except PublishError:
                evidence["ephemeral_container_removed"] = False
        write_json(args.output, evidence)
    print(f"Resultado sanitizado: {args.output}", flush=True)
    return 0 if evidence.get("status") == "passed" and evidence.get("ephemeral_container_removed") else 1


if __name__ == "__main__":
    raise SystemExit(main())
