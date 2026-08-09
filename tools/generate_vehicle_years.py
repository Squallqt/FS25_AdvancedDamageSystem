#!/usr/bin/env python
"""Regenerates scripts/ADS_VehicleYearsData.lua from the upstream Vehicle Years database.

Usage: python tools/generate_vehicle_years.py
"""

import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

SOURCE_URL = "https://gitlab.com/thalley/fs25_vehicle_years/-/raw/main/data/vehicle_years.xml"
TARGET = Path(__file__).resolve().parent.parent / "FS25_RealisticMechanicalSystems" / "scripts" / "ADS_VehicleYearsData.lua"
OLDEST_YEAR = 1800
NEWEST_YEAR = 2100

# Store item paths are keyed the way the game exposes them: mod name, then the raw XML filename.
def build_key(mod_name: str, raw_xml_filename: str) -> str:
    path = raw_xml_filename.replace("\\", "/").strip()
    prefix = mod_name.strip() + "/" if mod_name.strip() else ""
    return (prefix + path).lower()


def collect_years(root: ET.Element) -> dict[str, int]:
    years: dict[str, int] = {}

    for category in root:
        for brand in category:
            for vehicle in brand.findall("vehicle"):
                raw_year = (vehicle.findtext("year") or "").strip()
                path = (vehicle.findtext("rawXMLFilename") or "").strip()

                if not raw_year.isdigit() or not path:
                    continue

                year = int(raw_year)

                if year < OLDEST_YEAR or year > NEWEST_YEAR:
                    continue

                key = build_key(vehicle.findtext("mod_name") or "", path)

                if '"' in key or "\\" in key:
                    raise ValueError(f"unsupported characters in key: {key}")

                years.setdefault(key, year)

    return years


def main() -> None:
    with urllib.request.urlopen(SOURCE_URL) as response:
        root = ET.fromstring(response.read())

    years = collect_years(root)

    lines = ["--- Generated table of vehicle production years, keyed by store item path.",
             "ADS_VehicleYearsData = {"]
    lines += [f'    ["{key}"] = {years[key]},' for key in sorted(years)]
    lines += ["}", ""]

    TARGET.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    print(f"{len(years)} entries written to {TARGET}")


if __name__ == "__main__":
    main()
