#!/usr/bin/env python3
"""Descarga la tabla de zonas de taxi de la TLC (taxi_zone_lookup.csv).

Los viajes solo traen PULocationID / DOLocationID. Esta tabla traduce cada id a
su borough y nombre de zona, y se usa en las consultas del analisis
exploratorio (vista `zonas` en sql/00_vistas.sql).

Uso:
    python scripts/download_zones.py

El archivo se guarda en data/raw/zones/taxi_zone_lookup.csv y no se vuelve a
descargar si ya existe.
"""

import sys
from pathlib import Path

import requests

URL = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"
DESTINO = Path("data/raw/zones/taxi_zone_lookup.csv")
TIEMPO_ESPERA = 60


def main() -> int:
    if DESTINO.exists() and DESTINO.stat().st_size > 0:
        print(f"ya existe, se omite: {DESTINO}")
        return 0

    DESTINO.parent.mkdir(parents=True, exist_ok=True)
    try:
        respuesta = requests.get(URL, timeout=TIEMPO_ESPERA)
        respuesta.raise_for_status()
    except requests.RequestException as error:
        print(f"ERROR: no se pudo descargar {URL}: {error}")
        return 1

    temporal = DESTINO.with_name(DESTINO.name + ".part")
    temporal.write_bytes(respuesta.content)
    temporal.replace(DESTINO)
    filas = respuesta.text.count("\n") - 1
    print(f"listo ({filas} zonas) -> {DESTINO}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
