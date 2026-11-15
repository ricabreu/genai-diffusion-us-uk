"""Step 4: build the harmonised analysis dataset (Section 7.3.6-7.3.7).

Inputs
    data/raw/fred/RPSGENAIUSAGESHAREALL.csv, RPSGENAIUSAGESHARENONWORK.csv  (step 1)
    data/interim/ofcom_estimates.csv                                        (step 2)
    data/interim/pew_estimates.csv                                          (step 3)
    data/external/published_estimates.csv, pew2026_age_groups.csv           (hand-entered, with sources)
Outputs
    data/processed/analysis_dataset.csv   one row per estimate (long format)
    data/processed/series_table.csv       series definitions (object-factor priors, breaks)

Usage:   python python/04_build_dataset.py
"""
from __future__ import annotations

import sys

import numpy as np
import pandas as pd

from utils import load_config, log, midpoint, months_since, rpath, se_from_n

FRED_URL = "https://fred.stlouisfed.org/series/{}"


def rps_rows(cfg: dict) -> list[dict]:
    fred_dir = rpath(cfg["paths"]["raw"]) / "fred"
    qmap = {int(k): v for k, v in cfg["fred"]["rps_quarter_to_fieldwork_month"].items()}
    n = cfg["fred"]["rps_n_per_wave"]
    deff = cfg["harmonisation"]["design_effect"]
    out = []
    for sid, series, label in [("RPSGENAIUSAGESHAREALL", "us_rps_any", "Uses generative AI for any purpose"),
                               ("RPSGENAIUSAGESHARENONWORK", "us_rps_nonwork", "Uses generative AI outside work")]:
        f = fred_dir / f"{sid}.csv"
        if not f.exists():
            log.warning("%s not found - run 01_fetch_fred.py first", f)
            continue
        df = pd.read_csv(f).dropna()
        for _, r in df.iterrows():
            d = pd.Timestamp(r["date"])
            fw = pd.Timestamp(year=d.year, month=qmap[d.month], day=15)
            p = r["value"] / 100
            out.append(dict(country="US", series=series, source="RPS (Bick, Blandin & Deming) via FRED",
                            item=label, population="18-64", fieldwork_start=fw.replace(day=1).date(),
                            fieldwork_end=(fw + pd.offsets.MonthEnd(0)).date(), date_mid=fw.date(),
                            y=p, n=n, se=se_from_n(p, n, deff, None), se_source="published n x deff",
                            derived=0, note=f"FRED label {r['date']}; n approximate (>40,000 over 9 waves)",
                            url=FRED_URL.format(sid)))
    return out


def pew_rows(cfg: dict) -> list[dict]:
    f = rpath(cfg["paths"]["interim"]) / "pew_estimates.csv"
    if not f.exists():
        log.warning("%s not found - run 03_process_pew.py first", f)
        return []
    df = pd.read_csv(f)
    smap = {("chatgpt_ever", "18-64"): "us_pew_chatgpt", ("chatgpt_purpose", "18-64"): "us_pew_chatgpt_purpose",
            ("chatbot_ever", "18-64"): "us_pew_chatbot", ("chatgpt_ever", "18+"): "us_pew_all_chatgpt",
            ("chatgpt_purpose", "18+"): "us_pew_all_purpose", ("chatbot_ever", "18+"): "us_pew_all_chatbot"}
    out = []
    for _, r in df.iterrows():
        key = (r["item_name"], r["group"])
        if key not in smap:
            continue
        out.append(dict(country="US", series=smap[key], source=f"Pew ATP {r['wave']} (respondent-level data)",
                        item=r["item"], population=r["group"], fieldwork_start=r["fieldwork_start"],
                        fieldwork_end=r["fieldwork_end"], date_mid=midpoint(r["fieldwork_start"], r["fieldwork_end"]),
                        y=r["pct"] / 100, n=int(r["n"]), se=r["se_pct"] / 100, se_source="microdata (Kish)",
                        derived=1, note=f"form {r['form']}",
                        url=f"https://www.pewresearch.org/dataset/american-trends-panel-wave-{r['wave'][1:]}/"))
    return out


def ofcom_rows(cfg: dict) -> list[dict]:
    f = rpath(cfg["paths"]["interim"]) / "ofcom_estimates.csv"
    if not f.exists():
        log.warning("%s not found - run 02_process_ofcom.py first", f)
        return []
    df = pd.read_csv(f)
    out = []
    for _, r in df[df["group"].isin(["16-64", "all"])].iterrows():
        series = "uk_ofcom" if r["group"] == "16-64" else "uk_ofcom_all"
        out.append(dict(country="UK", series=series, source=f"Ofcom Adults' Media Literacy Tracker {r['year']} (respondent-level data)",
                        item=r["item"], population="16-64" if r["group"] == "16-64" else "16+",
                        fieldwork_start=r["fieldwork_start"], fieldwork_end=r["fieldwork_end"],
                        date_mid=midpoint(r["fieldwork_start"], r["fieldwork_end"]),
                        y=r["pct"] / 100, n=int(r["n"]), se=r["se_pct"] / 100, se_source="microdata (Kish)",
                        derived=1, note="", url="https://www.ofcom.org.uk/media-use-and-attitudes/media-habits-adults/adults-media-use-and-attitudes"))
    return out


def published_rows(cfg: dict) -> list[dict]:
    h = cfg["harmonisation"]
    df = pd.read_csv(rpath(cfg["paths"]["external"]) / "published_estimates.csv")
    out = []
    for _, r in df.iterrows():
        p = r["value_pct"] / 100
        n = None if pd.isna(r["n"]) else float(r["n"])
        out.append(dict(country=r["country"], series=r["series"], source=r["source"], item=r["item"],
                        population=r["population"], fieldwork_start=r["fieldwork_start"], fieldwork_end=r["fieldwork_end"],
                        date_mid=midpoint(r["fieldwork_start"], r["fieldwork_end"]), y=p, n=n,
                        se=se_from_n(p, n, h["design_effect"], h["default_n_eff"]),
                        se_source="published n x deff" if n else "assumed n_eff",
                        derived=0, note=r["note"] if isinstance(r["note"], str) else "", url=r["url"]))
    # Pew 2026: convert published age-group figures to 18-64 with approximate population weights
    ag = pd.read_csv(rpath(cfg["paths"]["external"]) / "pew2026_age_groups.csv")
    w = h["pew2026_age_weights"]
    for series, g in ag.groupby("series"):
        g = g.set_index("age_group")
        wa = ["18-29", "30-49", "50-64"]
        p = sum(w[a] * g.loc[a, "value_pct"] for a in wa) / sum(w[a] for a in wa) / 100
        n_wa = g["n_total"].iloc[0] * sum(w[a] for a in wa)
        out.append(dict(country="US", series=series, source="Pew Research Center (2026), converted from age groups",
                        item=g["item"].iloc[0], population="18-64 (approx.)", fieldwork_start=g["fieldwork_start"].iloc[0],
                        fieldwork_end=g["fieldwork_end"].iloc[0],
                        date_mid=midpoint(g["fieldwork_start"].iloc[0], g["fieldwork_end"].iloc[0]), y=p, n=round(n_wa),
                        se=se_from_n(p, n_wa, h["design_effect"], h["default_n_eff"]), se_source="published n x deff",
                        derived=1, note="age weights 0.20/0.34/0.24 (18-29/30-49/50-64); replace with microdata when public",
                        url=g["url"].iloc[0]))
    return out


def anchor_rows(cfg: dict) -> list[dict]:
    t0 = pd.Timestamp(cfg["project"]["t0_date"]).date()
    return [dict(country=c, series="anchor", source="Launch condition F(0) = 0", item="Public release of ChatGPT",
                 population="target", fieldwork_start=t0, fieldwork_end=t0, date_mid=t0, y=0.0, n=None,
                 se=cfg["harmonisation"]["anchor_se"], se_source="fixed", derived=1,
                 note="launch 30 Nov 2022; t = 0", url="") for c in ["US", "UK"]]


def main() -> int:
    cfg = load_config()
    stab = pd.DataFrame.from_dict(cfg["harmonisation"]["series"], orient="index")
    stab.index.name = "series"
    stab = stab.reset_index()
    stab["break_date"] = stab.get("break_date")
    stab["has_break"] = stab["break_date"].notna().astype(int)

    rows = rps_rows(cfg) + pew_rows(cfg) + ofcom_rows(cfg) + published_rows(cfg) + anchor_rows(cfg)
    df = pd.DataFrame(rows)
    unknown = set(df["series"]) - set(stab["series"])
    if unknown:
        raise ValueError(f"Series not defined in config: {unknown}")

    df = df.merge(stab[["series", "measure", "role", "break_date"]], on="series", how="left")
    df["date_mid"] = pd.to_datetime(df["date_mid"])
    freeze = pd.Timestamp(cfg["project"]["freeze_date"])
    late = df["date_mid"] > freeze
    if late.any():
        log.info("Dropping %d rows after the freeze date (kept for prospective tests)", late.sum())
        df = df[~late]
    df["t"] = df["date_mid"].apply(lambda d: round(months_since(d, cfg), 4))
    df["post_break"] = [int(pd.notna(b) and d >= pd.Timestamp(b)) for d, b in zip(df["date_mid"], df["break_date"])]
    df["accessed"] = cfg["project"]["freeze_date"]
    df = df.sort_values(["country", "series", "t"]).reset_index(drop=True)
    df.insert(0, "obs_id", [f"o{i+1:03d}" for i in range(len(df))])
    cols = ["obs_id", "country", "series", "role", "measure", "population", "source", "item",
            "fieldwork_start", "fieldwork_end", "date_mid", "t", "y", "se", "n", "se_source",
            "derived", "post_break", "note", "url", "accessed"]
    df["date_mid"] = df["date_mid"].dt.date
    df = df[cols]

    out = rpath(cfg["paths"]["processed"])
    out.mkdir(parents=True, exist_ok=True)
    df.to_csv(out / "analysis_dataset.csv", index=False)
    stab.drop(columns=[c for c in ["index"] if c in stab]).to_csv(out / "series_table.csv", index=False)

    summ = df.groupby(["country", "role", "series"]).agg(rows=("y", "size"), first=("date_mid", "min"),
                                                        last=("date_mid", "max")).reset_index()
    log.info("Analysis dataset: %d rows (%s)\n%s", len(df),
             ", ".join(f"{k} {v}" for k, v in df["country"].value_counts().items()), summ.to_string(index=False))
    est = df[df.role == "estimation"]
    log.info("Primary estimation set: %s", ", ".join(f"{k} {v}" for k, v in est["country"].value_counts().items()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
