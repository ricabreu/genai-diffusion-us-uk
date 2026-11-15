"""Step 5: monthly covariates on the estimation grid (Section 7.3.7).

- Shocks: for each country and shock type, an indicator equal to 1 from the
  first month that starts after the first dated event of that type (step form).
  Used by model M4, where x(t) = exp(sum_k beta_k * shock_k(t)).
- Ceiling: internet users per 100 people (World Bank, via FRED) / 100, linearly
  interpolated to months and held constant after the last annual value. Used by
  model M6 as the time-varying ceiling of the market potential.
- Internet benchmark: the annual series, for the P1 benchmark fits in R.

Usage:   python python/05_prepare_covariates.py
Outputs: data/processed/shocks.csv, ceiling.csv, internet_annual.csv
"""
from __future__ import annotations

import sys

import numpy as np
import pandas as pd

from utils import load_config, log, months_since, rpath


def main() -> int:
    cfg = load_config()
    t0 = pd.Timestamp(cfg["project"]["t0_date"])
    end = pd.Timestamp(cfg["covariates"]["horizon_end"])
    months = pd.date_range(t0, end, freq="MS")
    G = len(months)
    out = rpath(cfg["paths"]["processed"])
    out.mkdir(parents=True, exist_ok=True)

    # Shocks
    ev = pd.read_csv(rpath("config/events.csv"))
    todo = ev[ev["date"].isna() | (ev["status"] != "verified")]
    if len(todo):
        log.warning("%d event(s) without a verified date are ignored:\n%s", len(todo),
                    todo[["country", "event"]].to_string(index=False))
    ev = ev.dropna(subset=["date"])
    ev = ev[ev["status"] == "verified"]
    ev["date"] = pd.to_datetime(ev["date"])
    types = cfg["covariates"]["shock_types"]
    rows = []
    for c in ["US", "UK"]:
        e = ev[(ev["country"] == c) & ev["type"].isin(types)]
        for g, m in enumerate(months):
            r = {"country": c, "g": g, "month": m.date(), "t": round(months_since(m, cfg), 4)}
            for k in types:
                r[k] = int(((e["type"] == k) & (e["date"] <= m)).any())
            rows.append(r)
    shocks = pd.DataFrame(rows)
    shocks.to_csv(out / "shocks.csv", index=False)
    log.info("shocks.csv: %d months x %d countries, types %s", G, 2, types)

    # Internet users: annual benchmark and monthly ceiling
    fred = rpath(cfg["paths"]["raw"]) / "fred"
    ann = []
    for c, sid in [("US", "ITNETUSERP2USA"), ("UK", "ITNETUSERP2GBR")]:
        f = fred / f"{sid}.csv"
        if not f.exists():
            log.warning("%s not found - run 01_fetch_fred.py first", f)
            return 1
        d = pd.read_csv(f).dropna()
        d["year"] = pd.to_datetime(d["date"]).dt.year
        d["country"] = c
        ann.append(d[["country", "year", "value"]])
    ann = pd.concat(ann)
    ann.to_csv(out / "internet_annual.csv", index=False)

    ceil_rows = []
    for c, d in ann.groupby("country"):
        # annual value placed at mid-year; linear interpolation; flat beyond the last year
        x = pd.to_datetime(d["year"].astype(str) + "-07-01")
        xs = np.array([(v - t0).days for v in x], float)
        ys = d["value"].to_numpy() / 100
        xm = np.array([(m - t0).days for m in months], float)
        share = np.interp(xm, xs, ys)  # np.interp holds end values constant
        for g, (m, s) in enumerate(zip(months, share)):
            ceil_rows.append({"country": c, "g": g, "month": m.date(), "ceiling": round(float(min(s, 1.0)), 5)})
    pd.DataFrame(ceil_rows).to_csv(out / "ceiling.csv", index=False)
    log.info("ceiling.csv and internet_annual.csv written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
