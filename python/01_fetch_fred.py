"""Step 1: retrieve FRED series (metadata and observations) as of the freeze date.

In the thesis, the series were retrieved through the FRED MCP connector of the
Federal Reserve Bank of St. Louis. This script reproduces the retrieval with the
public FRED API, fixing the vintage at the freeze date so that later revisions
do not change the results.

Usage:
    export FRED_API_KEY=xxxxxxxx
    python python/01_fetch_fred.py
Outputs:
    data/raw/fred/<SERIES_ID>.csv          (date, value)
    data/raw/fred/<SERIES_ID>_meta.json    (title, units, frequency, notes, ...)
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone

import pandas as pd
import requests

from utils import load_config, log, rpath

API = "https://api.stlouisfed.org/fred"


def fred_get(endpoint: str, params: dict) -> dict:
    r = requests.get(f"{API}/{endpoint}", params=params, timeout=60)
    r.raise_for_status()
    return r.json()


def main() -> int:
    cfg = load_config()
    key = os.environ.get("FRED_API_KEY")
    if not key:
        log.error("Set the environment variable FRED_API_KEY (free key from FRED).")
        return 1
    vintage = cfg["project"]["freeze_date"]
    outdir = rpath(cfg["paths"]["raw"]) / "fred"
    outdir.mkdir(parents=True, exist_ok=True)
    base = {"api_key": key, "file_type": "json",
            "realtime_start": vintage, "realtime_end": vintage}

    for s in cfg["fred"]["series"]:
        sid = s["id"]
        meta = fred_get("series", {**base, "series_id": sid})["seriess"][0]
        obs = fred_get("series/observations", {**base, "series_id": sid})["observations"]
        df = pd.DataFrame(obs)[["date", "value"]]
        df["value"] = pd.to_numeric(df["value"], errors="coerce")
        df.to_csv(outdir / f"{sid}.csv", index=False)
        meta["retrieved_utc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
        meta["vintage"] = vintage
        meta["use"] = s.get("use")
        with open(outdir / f"{sid}_meta.json", "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
        log.info("%-28s %3d obs  %s to %s  (last updated %s)", sid, len(df),
                 df["date"].min(), df["date"].max(), meta.get("last_updated"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
