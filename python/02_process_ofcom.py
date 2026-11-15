"""Step 2: weighted estimates from the Ofcom Adults' Media Literacy Tracker files.

Adopter = answered yes (code 1) to the use question; respondents unaware of AI
(not asked) count as non-adopters, as in Ofcom's published figures. In 2025 the
AI questions were in Module 1 only, so the base is Module 1 respondents.

Usage:   python python/02_process_ofcom.py
Output:  data/interim/ofcom_estimates.csv
"""
from __future__ import annotations

import sys

import numpy as np
import pandas as pd

from utils import check_published, load_config, log, rpath, weighted_share


def process_wave(w: dict, max_working_code: int) -> pd.DataFrame:
    path = rpath(w["file"])
    if not path.exists():
        log.warning("Ofcom %s: file not found (%s) - skipped", w["year"], path)
        return pd.DataFrame()
    df = pd.read_csv(path, dtype=str, low_memory=False)
    for v in [w["use_var"], w["weight_var"], w["age_var"], w["sex_var"]] + ([w["module_var"]] if w["module_var"] else []):
        df[v] = pd.to_numeric(df[v].str.strip(), errors="coerce")

    base = df[df[w["weight_var"]].notna() & (df[w["weight_var"]] > 0)].copy()
    dropped = len(df) - len(base)
    if w["module_var"]:
        before = (df[w["module_var"]] == 1).sum()
        base = base[base[w["module_var"]] == 1]
        log.info("Ofcom %s: %d records without weight dropped (%d in the AI module)",
                 w["year"], dropped, before - len(base))
    else:
        log.info("Ofcom %s: %d records without weight dropped", w["year"], dropped)

    y = (base[w["use_var"]] == 1).astype(float).to_numpy()
    wt = base[w["weight_var"]].to_numpy()
    age = base[w["age_var"]].to_numpy()
    sex = base[w["sex_var"]].to_numpy()
    codes = {int(k): v for k, v in w["age_codes"].items()}

    groups = {"all": np.ones(len(base), bool),
              "16-64": np.isin(age, [c for c in codes if c <= max_working_code]),
              "65+": np.isin(age, [c for c in codes if c > max_working_code]),
              "men": sex == 1, "women": sex == 2}
    groups.update({lab: age == c for c, lab in codes.items()})

    rows = []
    for g, m in groups.items():
        r = weighted_share(y[m], wt[m])
        rows.append({"source": "Ofcom", "year": w["year"], "fieldwork_start": w["fieldwork"][0],
                     "fieldwork_end": w["fieldwork"][1], "item": w["item"], "group": g,
                     "n": r["n"], "n_eff": round(r["n_eff"], 1), "pct": round(100 * r["p"], 2),
                     "se_pct": round(100 * r["se"], 3)})
        if g in w.get("published", {}):
            check_published(f"Ofcom {w['year']} {g}", 100 * r["p"], w["published"][g])
    return pd.DataFrame(rows)


def main() -> int:
    cfg = load_config()
    oc = cfg["ofcom"]
    out = pd.concat([process_wave(w, oc["working_age_codes_max"]) for w in oc["waves"]], ignore_index=True)
    if out.empty:
        log.error("No Ofcom file processed. Put the files in data/raw/ofcom/ (see data/raw/README.md).")
        return 1
    dest = rpath(cfg["paths"]["interim"]) / "ofcom_estimates.csv"
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(dest, index=False)
    log.info("Wrote %s (%d rows)", dest, len(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
