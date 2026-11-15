"""Shared helpers for the Study 4 data pipeline."""
from __future__ import annotations

import logging
from datetime import date
from pathlib import Path

import numpy as np
import pandas as pd
import yaml

ROOT = Path(__file__).resolve().parents[1]
log = logging.getLogger("study4")
logging.basicConfig(level=logging.INFO, format="%(levelname)s  %(message)s")


def load_config(path: str | Path | None = None) -> dict:
    """Read config/config.yaml (paths in it are relative to the repository root)."""
    path = Path(path) if path else ROOT / "config" / "config.yaml"
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def rpath(rel: str | Path) -> Path:
    """Absolute path for a path given relative to the repository root."""
    return ROOT / rel


def to_date(x) -> date:
    return pd.Timestamp(x).date()


def midpoint(start, end) -> date:
    s, e = pd.Timestamp(start), pd.Timestamp(end)
    return (s + (e - s) / 2).date()


def months_since(d, cfg: dict) -> float:
    """Time in months since t0 (config: project.t0_date), using an average month length."""
    t0 = pd.Timestamp(cfg["project"]["t0_date"])
    return (pd.Timestamp(d) - t0).days / float(cfg["project"]["days_per_month"])


def weighted_share(y: np.ndarray, w: np.ndarray) -> dict:
    """Weighted proportion with a Kish (1965) effective-sample-size standard error.

    p = sum(w*y) / sum(w);  n_eff = (sum w)^2 / sum(w^2);  se = sqrt(p(1-p)/n_eff).
    The SE allows for unequal weights only (not for stratification or clustering),
    so it is treated as a lower bound downstream.
    """
    y = np.asarray(y, dtype=float)
    w = np.asarray(w, dtype=float)
    ok = np.isfinite(w) & (w > 0)
    y, w = y[ok], w[ok]
    if w.size == 0:
        return {"n": 0, "p": np.nan, "se": np.nan, "n_eff": np.nan}
    sw = w.sum()
    p = float((w * y).sum() / sw)
    n_eff = float(sw ** 2 / (w ** 2).sum())
    se = float(np.sqrt(p * (1 - p) / n_eff))
    return {"n": int(w.size), "p": p, "se": se, "n_eff": n_eff}


def se_from_n(p: float, n: float | None, deff: float, default_n_eff: float) -> float:
    """SE of a published proportion from its sample size and an assumed design effect."""
    if n is None or (isinstance(n, float) and np.isnan(n)) or n == "":
        return float(np.sqrt(p * (1 - p) / default_n_eff))
    return float(np.sqrt(deff * p * (1 - p) / float(n)))


def check_published(label: str, computed_pct: float, published_pct, tol: float = 1.0) -> bool:
    """Compare a computed percentage with the provider's published (rounded) figure."""
    if published_pct is None or (isinstance(published_pct, float) and np.isnan(published_pct)):
        return True
    diff = computed_pct - float(published_pct)
    ok = abs(diff) <= tol
    log.info("%-45s computed %5.1f  published %5.1f  diff %+.1f  %s",
             label, computed_pct, float(published_pct), diff, "OK" if ok else "CHECK")
    return ok
