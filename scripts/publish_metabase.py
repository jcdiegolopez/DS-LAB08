#!/usr/bin/env python3
"""Reproduce la colección, las ocho preguntas y el tablero de indicadores.

--dry-run genera un JSON portable sin iniciar sesión ni llamar a Metabase.
La publicación usa la API de Metabase 0.63 y conserva los IDs al repetirla.
"""

from __future__ import annotations

import argparse
import copy
import getpass
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent.parent
COLLECTION = "Lab 8 - Indicadores"
DATABASE = "DuckDB Lab 8"
DASHBOARD = "NYC Taxi | 2024-2026"
DB_FILE = "/workspace/data/processed/taxi.duckdb"

# Los nombres y las columnas corresponden a sql/07_*.sql.
INDICATORS = [
    ("07_01_volumen_mensual.sql", "I1 · Viajes por día calendario", "line",
     "mes_fecha", "viajes_por_dia", "Viajes / día",
     "Todos los meses disponibles. Denominador: días calendario del mes; no se rellenan meses ausentes con cero."),
    ("07_02_monto_mensual.sql", "I2 · Monto registrado por día", "line",
     "mes_fecha", "monto_por_dia_usd", "USD nominales / día",
     "Total registrado dividido entre días calendario. Incluye tarifas, impuestos, peajes, recargos y propina registrada; no mide utilidad."),
    ("07_03_ticket_periodo_comun.sql", "I3 · Ticket promedio en meses comunes", "bar",
     "anio", "ticket_promedio_usd", "USD nominales / viaje",
     "Promedio ponderado por viajes, usando solo meses presentes en todas las combinaciones taxi-año. Los meses se muestran en el resultado SQL."),
    ("07_04_viaje_tipico.sql", "I4 · Duración del viaje típico", "bar",
     "anio", "duracion_mediana_min", "Minutos, mediana aproximada",
     "Mediana aproximada de duración en meses comunes. El resultado SQL también contiene distancia y velocidad medianas."),
    ("07_05_mezcla_pagos.sql", "I5 · Mezcla mensual de métodos de pago", "table",
     None, None, None,
     "Porcentaje dentro de cada taxi y mes. NULL/0 se mantienen como sin detalle. La tabla permite ver simultáneamente Yellow y Green sin mezclar denominadores."),
    ("07_06_propina_tarjeta.sql", "I6 · Propina con tarjeta sobre tarifa", "bar",
     "anio", "propina_pct_mediana", "% de fare_amount, mediana aproximada",
     "Solo tarjeta, meses comunes. Mantiene propinas cero; excluye nulas/negativas. Las propinas en efectivo no están registradas en los datos TLC."),
    ("07_07_zonas_top.sql", "I7 · Cinco zonas principales de recogida", "table",
     None, None, None,
     "Cinco zonas por taxi y año en meses comunes. Los porcentajes usan todos los viajes del taxi-año; conserva zonas sin catálogo."),
    ("07_08_retencion_limpieza.sql", "I8 · Registros conservados tras limpieza", "line",
     "mes_fecha", "pct_conservado", "% de registros originales",
     "Viajes conservados / registros originales de cada taxi-mes después de R1–R6. Los descartes no equivalen necesariamente a viajes inexistentes."),
]


class PublishError(RuntimeError):
    """Error publicable sin cuerpos HTTP ni información de autenticación."""


def coverage_from_files() -> dict[str, list[int]]:
    """Detecta la cobertura local sin abrir los Parquet ni la base en uso."""
    coverage: dict[str, set[int]] = {}
    for path in sorted((ROOT / "data/raw").glob("*/*/*.parquet")):
        match = re.fullmatch(r"(yellow|green)_tripdata_(\d{4})-(\d{2})\.parquet", path.name)
        if match:
            taxi, year, month = match.groups()
            coverage.setdefault(f"{taxi}/{year}", set()).add(int(month))
    return {key: sorted(value) for key, value in coverage.items()}


def month_ranges(months: list[int]) -> str:
    ranges: list[str] = []
    for month in months:
        if not ranges or month != end + 1:
            if ranges:
                ranges[-1] = f"{start:02d}–{end:02d}" if start != end else f"{start:02d}"
            start = end = month
            ranges.append(f"{month:02d}")
        else:
            end = month
    if ranges:
        ranges[-1] = f"{start:02d}–{end:02d}" if start != end else f"{start:02d}"
    return ", ".join(ranges)


def named_month_ranges(months: list[int]) -> str:
    names = ["enero", "febrero", "marzo", "abril", "mayo", "junio",
             "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
    return ", ".join("–".join(names[int(month) - 1] for month in group.split("–"))
                     for group in month_ranges(months).split(", ")) if months else ""


def coverage_summary(coverage: dict[str, list[int]]) -> str:
    by_year: dict[int, dict[str, list[int]]] = {}
    for key, months in coverage.items():
        taxi, year = key.split("/")
        by_year.setdefault(int(year), {})[taxi] = months
    complete_years = []
    partial = []
    for year, taxis in sorted(by_year.items()):
        if set(taxis) == {"green", "yellow"} and taxis["green"] == taxis["yellow"]:
            if taxis["green"] == list(range(1, 13)):
                complete_years.append(year)
            else:
                partial.append(f"{year} {named_month_ranges(taxis['green'])}")
        else:
            details = " / ".join(f"{taxi.title()} {named_month_ranges(months)}"
                                 for taxi, months in sorted(taxis.items()))
            partial.append(f"{year} {details}")
    captions = ([f"{month_ranges(complete_years)} {'completo' if len(complete_years) == 1 else 'completos'}"]
                if complete_years else [])
    return "; ".join(captions + partial) or "consultar manifiesto de materialización"


def build_spec(database_file: str = DB_FILE) -> dict[str, Any]:
    cards = []
    for index, (filename, name, display, x, y, unit, description) in enumerate(INDICATORS):
        sql_path = ROOT / "sql" / filename
        if not sql_path.is_file():
            raise PublishError(f"Falta {sql_path.relative_to(ROOT)}.")
        sql = sql_path.read_text(encoding="utf-8-sig").strip()
        if not sql or "{{" in sql or "[[" in sql:
            raise PublishError(f"SQL vacío o con parámetros no definidos: {filename}.")
        settings: dict[str, Any] = {}
        if display in {"line", "bar"}:
            settings = {
                "graph.dimensions": [x, "taxi"],
                "graph.metrics": [y],
                "graph.show_values": display == "bar",
                "graph.y_axis.title_text": unit,
                "graph.x_axis.title_text": "Mes del archivo" if x == "mes_fecha" else "Año",
                "graph.show_goal": False,
                "graph.show_trendline": False,
                "graph.colors": ["#2A9D8F", "#E9B949"],
            }
            if display == "bar":
                settings["stackable.stack_type"] = None
            if y == "pct_conservado":
                settings.update({"graph.y_axis.auto_range": False,
                                 "graph.y_axis.min": 0, "graph.y_axis.max": 100})
        cards.append({
            "key": filename.removesuffix(".sql"),
            "name": name,
            "description": description,
            "display": display,
            "visualization_settings": settings,
            "sql_file": f"sql/{filename}",
            "sql_sha256": hashlib.sha256(sql.encode()).hexdigest(),
            "sql": sql,
            "position": {"col": 0 if index % 2 == 0 else 12,
                         "row": 4 + (index // 2) * 8, "size_x": 12, "size_y": 8},
        })
    coverage = coverage_from_files()
    common = sorted(set.intersection(*(set(months) for months in coverage.values()))) if coverage else []
    notes = (
        f"**Cobertura:** {coverage_summary(coverage)}. "
        f"Anuales: {named_month_ranges(common) + ' común' if common else 'meses comunes calculados en SQL'}; "
        "mensuales: cobertura disponible/día calendario. "
        "USD nominales: cobros, no utilidad. Limpieza R1–R6; "
        "propinas solo tarjeta; pagos sin detalle incluidos."
    )
    spec = {
        "spec_version": 1,
        "api_target": "Metabase 0.63 (esquema local /api/docs/openapi.json)",
        "collection": {"name": COLLECTION,
                       "description": "Ejercicios 7 y 8.4 · NYC Yellow y Green, 2024–2026"},
        "database": {"name": DATABASE, "engine": "duckdb",
                     "details": {"database_file": database_file, "read_only": True,
                                 "memory_limit": "4GB", "init_sql": "SET threads=4;"}},
        "dashboard": {"name": DASHBOARD,
                      "description": "Ocho indicadores · Yellow y Green · cobertura parcial 2026 y comparación por meses comunes.",
                      "width": "full", "parameters": [], "grid_columns": 24,
                      "note": {"text": notes, "position": {"col": 0, "row": 0, "size_x": 24, "size_y": 4}}},
        "coverage": coverage,
        "common_months": common,
        "cards": cards,
    }
    validate_spec(spec)
    return spec


def validate_spec(spec: dict[str, Any]) -> None:
    """Valida el contrato portable y los rectángulos, sin ejecutar SQL."""
    cards = spec["cards"]
    if len(cards) != 8 or len({card["name"] for card in cards}) != len(cards):
        raise PublishError("Se requieren ocho preguntas con nombres únicos.")
    if sum(card["display"] != "table" for card in cards) < 6:
        raise PublishError("Se requieren al menos seis gráficos.")
    positions = [spec["dashboard"]["note"]["position"]] + [c["position"] for c in cards]
    for index, position in enumerate(positions):
        if (position["col"] < 0 or position["row"] < 0 or position["size_x"] <= 0
                or position["size_y"] <= 0 or position["col"] + position["size_x"] > 24):
            raise PublishError("Posición de tablero fuera de la grilla.")
        for other in positions[:index]:
            overlap = (position["col"] < other["col"] + other["size_x"]
                       and other["col"] < position["col"] + position["size_x"]
                       and position["row"] < other["row"] + other["size_y"]
                       and other["row"] < position["row"] + position["size_y"])
            if overlap:
                raise PublishError("Hay tarjetas que se superponen.")


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


class MetabaseAPI:
    def __init__(self, base_url: str):
        import requests

        self.requests = requests
        self.base_url = base_url.rstrip("/")
        parsed = urlsplit(self.base_url)
        if (parsed.scheme not in {"http", "https"} or not parsed.hostname
                or parsed.username or parsed.password or parsed.query or parsed.fragment):
            raise PublishError("URL de Metabase inválida; usar una URL sin credenciales.")
        if parsed.scheme == "http" and parsed.hostname not in {"localhost", "127.0.0.1", "::1", "metabase"}:
            raise PublishError("Para un servidor remoto, usar HTTPS.")
        self.session = requests.Session()
        self.authenticated = False

    def call(self, method: str, path: str, **kwargs: Any) -> Any:
        try:
            response = self.session.request(method, self.base_url + path,
                                            timeout=(10, 60), **kwargs)
        except self.requests.RequestException:
            raise PublishError(f"No se pudo conectar con Metabase ({method} {path}).") from None
        if not response.ok:
            hint = " Revisar usuario, contraseña y permisos de administrador." if response.status_code in {401, 403} else ""
            # No se muestran cuerpos de error: pueden repetir datos enviados.
            raise PublishError(f"Metabase respondió HTTP {response.status_code} ({method} {path}).{hint}")
        if not response.content:
            return None
        try:
            return response.json()
        except ValueError:
            raise PublishError(f"Respuesta no JSON de Metabase ({method} {path}).") from None

    def login(self, username: str, password: str) -> None:
        result = self.call("POST", "/api/session", json={"username": username, "password": password})
        token = result.get("id") if isinstance(result, dict) else None
        if not token:
            raise PublishError("Metabase no devolvió una sesión válida.")
        self.session.headers["X-Metabase-Session"] = token
        self.authenticated = True

    def close(self) -> None:
        if self.authenticated:
            try:
                self.call("DELETE", "/api/session")
            except PublishError:
                pass
        self.session.headers.pop("X-Metabase-Session", None)
        self.session.close()


def rows(value: Any) -> list[dict[str, Any]]:
    if isinstance(value, list):
        return value
    if isinstance(value, dict) and isinstance(value.get("data"), list):
        return value["data"]
    raise PublishError("Formato inesperado al listar objetos de Metabase.")


def unique_match(items: list[dict[str, Any]], name: str, model: str | None = None) -> dict[str, Any] | None:
    matches = [item for item in items if item.get("name") == name
               and (model is None or item.get("model") == model)]
    if len(matches) > 1:
        raise PublishError(f"Hay más de un objeto llamado '{name}'; resolver el duplicado antes de publicar.")
    return matches[0] if matches else None


def native_query(database_id: int, sql: str) -> dict[str, Any]:
    # MBQL 5 y template-tags como lista corresponden a Metabase 0.63.
    return {"database": database_id, "lib/type": "mbql/query",
            "stages": [{"lib/type": "mbql.stage/native", "native": sql, "template-tags": []}]}


def publish(api: MetabaseAPI, spec: dict[str, Any]) -> dict[str, Any]:
    database_spec = spec["database"]
    database = unique_match(rows(api.call("GET", "/api/database")), database_spec["name"])
    if database:
        database = api.call("GET", f"/api/database/{database['id']}")
        details = database.get("details", {})
        if database.get("engine") != "duckdb" or details.get("database_file") != database_spec["details"]["database_file"]:
            raise PublishError("Existe 'DuckDB Lab 8' con otro motor o archivo. No se cambiará esa conexión.")
        if details.get("read_only") is not True:
            raise PublishError("La conexión 'DuckDB Lab 8' debe tener read_only=true antes de publicar.")
    else:
        database = api.call("POST", "/api/database", json=database_spec)
    database_id = database["id"]

    collections = rows(api.call("GET", "/api/collection"))
    # Solo una colección no personal en la raíz; no busca en otros proyectos.
    root_collections = [c for c in collections if c.get("location") == "/" and not c.get("personal_owner_id")]
    collection = unique_match(root_collections, spec["collection"]["name"])
    if collection is None:
        collection = api.call("POST", "/api/collection", json={**spec["collection"], "parent_id": None})
    collection_id = collection["id"]
    items = rows(api.call("GET", f"/api/collection/{collection_id}/items",
                          params={"show_dashboard_questions": "true"}))
    dashboard_match = unique_match(items, spec["dashboard"]["name"], "dashboard")
    # Detectar todos los duplicados antes de modificar preguntas.
    matches = {card["key"]: unique_match(items, card["name"], "card") for card in spec["cards"]}
    card_ids: dict[str, int] = {}
    for card in spec["cards"]:
        payload = {key: copy.deepcopy(card[key])
                   for key in ("name", "description", "display", "visualization_settings")}
        payload.update({"collection_id": collection_id, "type": "question",
                        "dataset_query": native_query(database_id, card["sql"])})
        match = matches[card["key"]]
        if match:
            saved = api.call("PUT", f"/api/card/{match['id']}", json=payload)
        else:
            saved = api.call("POST", "/api/card", json=payload)
        card_ids[card["key"]] = saved["id"]
        print(f"Pregunta lista: {card['name']}", flush=True)

    dashboard_payload = {key: spec["dashboard"][key] for key in ("name", "description", "parameters")}
    dashboard_payload["collection_id"] = collection_id
    if dashboard_match:
        dashboard = api.call("GET", f"/api/dashboard/{dashboard_match['id']}")
    else:
        dashboard = api.call("POST", "/api/dashboard", json=dashboard_payload)
    dashboard_id = dashboard["id"]
    existing = dashboard.get("dashcards", [])
    # Reutilizar el ID de cada dashcard; una nueva recibe un ID temporal negativo.
    note_id = next((c["id"] for c in existing if c.get("card_id") is None
                    and c.get("visualization_settings", {}).get("virtual_card", {}).get("display") == "text"), -1)
    note = spec["dashboard"]["note"]
    dashcards = [{"id": note_id, "card_id": None, **note["position"], "series": [],
                  "parameter_mappings": [], "visualization_settings": {
                      "virtual_card": {"name": None, "display": "text",
                                       "visualization_settings": {}, "dataset_query": {}},
                      "text": note["text"]}}]
    for index, card in enumerate(spec["cards"], start=2):
        card_id = card_ids[card["key"]]
        old = next((c for c in existing if c.get("card_id") == card_id), None)
        dashcards.append({"id": old["id"] if old else -index, "card_id": card_id,
                          **card["position"], "parameter_mappings": [], "series": [],
                          "visualization_settings": {}})
    api.call("PUT", f"/api/dashboard/{dashboard_id}",
             json={**dashboard_payload, "width": spec["dashboard"]["width"], "dashcards": dashcards})
    return {"collection_id": collection_id, "database_id": database_id,
            "dashboard_id": dashboard_id, "card_ids": card_ids,
            "dashboard_url": f"{api.base_url}/dashboard/{dashboard_id}"}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="http://localhost:3000", help="Desde lab: http://metabase:3000")
    parser.add_argument("--database-file", default=DB_FILE, help="Ruta vista por el contenedor Metabase")
    parser.add_argument("--dry-run", action="store_true", help="Solo validar contrato y generar JSON; no requiere cuenta")
    parser.add_argument("--output", type=Path, default=ROOT / "docs/metabase/dashboard-spec.json")
    parser.add_argument("--ids-output", type=Path, help="Opcional: guardar IDs de esta instalación, sin credenciales")
    args = parser.parse_args()
    try:
        spec = build_spec(args.database_file)
        write_json(args.output, spec)
        print(f"Especificación portable: {args.output}", flush=True)
        if args.dry_run:
            print("Validado: 8 consultas, 6 gráficos y 2 tablas; grilla sin superposiciones. No se ejecutó SQL ni se llamó a Metabase.")
            return 0
        username = os.environ.get("METABASE_USER")
        password = os.environ.get("METABASE_PASSWORD")
        if not username or not password:
            if not sys.stdin.isatty():
                raise PublishError("Usar terminal interactiva o definir METABASE_USER y METABASE_PASSWORD en el entorno.")
            username = username or input("Correo de Metabase: ").strip()
            password = password or getpass.getpass("Contraseña de Metabase: ")
        api = MetabaseAPI(args.url)
        try:
            api.login(username, password)
            del password
            ids = publish(api, spec)
        finally:
            api.close()
        if args.ids_output:
            write_json(args.ids_output, ids)
        print(f"Tablero listo: {ids['dashboard_url']}")
        return 0
    except (PublishError, OSError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    except ImportError:
        print("Error: falta requests; ejecutar desde el contenedor lab o instalar requirements.txt.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
