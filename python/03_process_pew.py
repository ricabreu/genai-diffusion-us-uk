"""Step 3: weighted estimates from Pew American Trends Panel waves (SPSS files).

The Pew files are licensed: keep them out of version control and do not share
them. Only the aggregate estimates written here leave the raw-data folder.

Coding (Section 7.3.5):
- In W131, W142 and W164 the sample was split at random into two forms: Form 1
  received "Have you ever used ChatGPT?" and Form 2 the three purpose items.
  The base of each estimate is all respondents in the form that received it.
- Respondents who had not heard of the product (not asked) and those who did
  not answer count as non-adopters, as in Pew's published figures.
- Purpose item (W123 and Form 2): adopter = yes to any of the three purposes.

Usage:   python python/03_process_pew.py
Output:  data/interim/pew_estimates.csv
"""
from __future__ import annotations

import glob
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pyreadstat

from utils import check_published, load_config, log, rpath, weighted_share


def find_sav(pew_dir: Path, wave: str) -> Path | None:
    # glob (unlike Path.rglob) also follows symbolic links to folders
    hits = sorted(glob.glob(str(pew_dir / "**" / f"ATP {wave}.sav"), recursive=True))
    return Path(hits[0]) if hits else None


def main() -> int:
    cfg = load_config()
    pc = cfg["pew"]
    pew_dir = rpath(pc["dir"])
    codes = {int(k): v for k, v in pc["age_codes"].items()}
    rows = []
    for wv in pc["waves"]:
        wave = wv["wave"]
        sav = find_sav(pew_dir, wave)
        if sav is None:
            log.warning("Pew %s: 'ATP %s.sav' not found under %s - skipped", wave, wave, pew_dir)
            continue
        df, _ = pyreadstat.read_sav(str(sav))
        wcol = f"WEIGHT_{wave}"
        df = df[df[wcol].notna() & (df[wcol] > 0)]
        age = df[pc["age_var"]].to_numpy()
        form = df[f"FORM_{wave}"].to_numpy() if f"FORM_{wave}" in df.columns else None

        for it in wv["items"]:
            if it["type"] == "single":
                y = (df[it["vars"][0]] == 1).astype(float).to_numpy()
            elif it["type"] == "purpose_net":
                y = (df[it["vars"]] == 1).any(axis=1).astype(float).to_numpy()
            else:
                raise ValueError(it["type"])
            base = np.ones(len(df), bool) if it["form"] is None else (form == it["form"])
            groups = {"18+": np.ones(len(df), bool),
                      "18-64": np.isin(age, pc["working_age_codes"])}
            groups.update({lab: age == c for c, lab in codes.items()})
            for g, m in groups.items():
                mm = m & base
                r = weighted_share(y[mm], df[wcol].to_numpy()[mm])
                rows.append({"source": "Pew ATP", "wave": wave,
                             "fieldwork_start": wv["fieldwork"][0], "fieldwork_end": wv["fieldwork"][1],
                             "item_name": it["name"], "item": it["label"],
                             "form": it["form"] if it["form"] is not None else "all",
                             "group": g, "n": r["n"], "n_eff": round(r["n_eff"], 1),
                             "pct": round(100 * r["p"], 2), "se_pct": round(100 * r["se"], 3)})
                if g == "18+":
                    check_published(f"Pew {wave} {it['name']}", 100 * r["p"], it.get("published"))

    if not rows:
        log.error("No Pew wave processed. Put the unzipped files in data/raw/pew/ (see data/raw/README.md).")
        return 1
    out = pd.DataFrame(rows)
    # Ratio of the purpose item to the ever-used item in waves that carried both (18-64)
    piv = out[out.group == "18-64"].pivot_table(index="wave", columns="item_name", values="pct")
    if {"chatgpt_ever", "chatgpt_purpose"} <= set(piv.columns):
        ratio = (piv["chatgpt_purpose"] / piv["chatgpt_ever"]).dropna()
        log.info("Purpose/ever ratio (18-64) by wave: %s; mean %.3f",
                 ", ".join(f"{k} {v:.3f}" for k, v in ratio.items()), ratio.mean())
    dest = rpath(cfg["paths"]["interim"]) / "pew_estimates.csv"
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(dest, index=False)
    log.info("Wrote %s (%d rows)", dest, len(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
