"""Figures and the benchmark accuracy table of the journal article.

Reads the saved output tables (no model is re-estimated) and writes
  output/figures/paper/fig1_series.png          survey estimates by series
  output/figures/paper/fig2_fit.png             fit of the Bass and generalised Bass models
  output/figures/paper/fig3_m_by_origin.png     market potential by forecast origin
  output/figures/paper/fig4_projections.png     projections to December 2030
  output/tables/rolling_origin_accuracy_with_naive.csv   accuracy of each model and of the naive forecast

Run from the repository root, after the R scripts:  python3 python/06_paper_figures.py
"""
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[1]
OUT = REPO / "output" / "figures" / "paper"
OUT.mkdir(parents=True, exist_ok=True)
C = dict(blue="#2a78d6", orange="#eb6834", green="#1baf7a", yellow="#eda100", pink="#e87ba4",
         dgreen="#008300", violet="#6250d6", ink="#3d3d3a", grey="#73726c", grid="#e6e5e0")
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 8.5, "axes.edgecolor": C["grey"],
                     "axes.labelcolor": C["ink"], "xtick.color": C["grey"], "ytick.color": C["grey"],
                     "axes.spines.top": False, "axes.spines.right": False, "axes.grid": True,
                     "grid.color": C["grid"], "grid.linewidth": 0.6, "legend.frameon": False,
                     "axes.titlesize": 9.5, "axes.titleweight": "bold", "axes.titlecolor": C["ink"]})
FREEZE = pd.Timestamp("2026-11-01")
d = pd.read_csv(REPO / "data/processed/analysis_dataset.csv", parse_dates=["date_mid"])
est = d[(d.role == "estimation") & (d.series != "anchor")].copy()
SER = {  # label, colour, marker
    "us_rps_any": ("RPS: uses generative AI, 18–64", C["blue"], "o"),
    "us_pew_chatbot": ("Pew: ever used an AI chatbot, 18–64", C["orange"], "D"),
    "us_pew_chatgpt": ("Pew: ever used ChatGPT, 18–64", C["green"], "s"),
    "us_pew_chatgpt_purpose": ("Pew: used ChatGPT for a listed purpose, 18–64", C["yellow"], "^"),
    "uk_deloitte": ("Deloitte: ever used generative AI, 16–75", C["blue"], "o"),
    "uk_ofcom": ("Ofcom: ever used generative AI, 16–64", C["orange"], "D"),
    "uk_ofcom_16plus": ("Ofcom 2023: ever used generative AI, 16+", C["green"], "s"),
}
EVENTS = [("2023-03-01", "a"), ("2023-10-01", "b"), ("2024-04-01", "c"), ("2025-04-01", "d")]
NAMES = {"US": "United States", "UK": "United Kingdom"}


def fmt_axis(ax, start="2022-11-01", end="2026-12-15", ymax=80, step=12):
    ax.set_xlim(pd.Timestamp(start), pd.Timestamp(end)); ax.set_ylim(0, ymax)
    ax.xaxis.set_major_locator(mdates.MonthLocator(bymonth=[1], interval=1 if step == 12 else 2))
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
    ax.grid(axis="x", visible=False)


# ---- Figure 1: the survey series ------------------------------------------------
fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.9), sharey=True)
for ax, cc in zip(axes, ["US", "UK"]):
    for s, g in est[est.country == cc].groupby("series", sort=False):
        lab, col, mk = SER[s]; g = g.sort_values("date_mid")
        ax.errorbar(g.date_mid, 100 * g.y, yerr=196 * g.se, color=col, marker=mk, ms=4.5, lw=1.1,
                    elinewidth=0.8, capsize=1.5, label=lab, zorder=3)
        pb = g[g.post_break == 1]
        if len(pb):
            ax.plot(pb.date_mid, 100 * pb.y, marker=mk, ms=8.5, mfc="none", mec=col, mew=1, ls="none", zorder=4)
    ax.plot(pd.Timestamp("2022-12-01"), 0, marker="x", color=C["ink"], ms=5, ls="none", label="Launch of ChatGPT (30 Nov 2022)")
    for dt, lab in EVENTS:
        ax.axvline(pd.Timestamp(dt), color=C["grey"], lw=0.6, ls=":", zorder=1)
        ax.text(pd.Timestamp(dt), 78.5, lab, ha="center", va="top", fontsize=7.5, color=C["grey"],
                bbox=dict(fc="white", ec="none", pad=0.6))
    fmt_axis(ax); ax.set_title(NAMES[cc], loc="left")
    ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.12), fontsize=7, ncol=1, handlelength=1.8)
axes[0].set_ylabel("Share of the survey population (%)")
fig.tight_layout(); fig.savefig(OUT / "fig1_series.png", dpi=300); plt.close(fig)

# ---- Figure 2: fit of the Bass model ---------------------------------------------
lp = pd.read_csv(REPO / "output/tables/latent_paths_all_models.csv", parse_dates=["date"])
mt = pd.read_csv(REPO / "output/tables/measurement_terms_M1.csv")
lam = mt[mt.term == "lambda"].set_index("series")["mean"]; dlt = mt[mt.term == "delta"].set_index("series")["mean"]
fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.7), sharey=True)
for ax, cc in zip(axes, ["US", "UK"]):
    a = lp[(lp.country == cc) & (lp.date <= FREEZE)]
    m1 = a[a.model == "M1 Bass"]; m4 = a[a.model == "M4 generalised Bass"]
    ax.fill_between(m1.date, 100 * m1.lo90, 100 * m1.hi90, color=C["orange"], alpha=0.18, lw=0, label="Bass model: 90% interval")
    ax.plot(m1.date, 100 * m1["mean"], color=C["orange"], lw=1.6, label="Bass model: posterior mean")
    ax.plot(m4.date, 100 * m4["mean"], color=C["violet"], lw=1.3, ls="--", label="Generalised Bass model: posterior mean")
    for s, g in est[est.country == cc].groupby("series", sort=False):
        lab, col, mk = SER[s]
        adj = (g.y - dlt[s] * g.post_break) / lam[s]
        ax.plot(g.date_mid, 100 * adj, marker=mk, ms=4.5, ls="none", color=C["ink"], mfc="white", mew=0.9, zorder=4,
                label={"us_rps_any": "RPS", "us_pew_chatbot": "Pew: AI chatbot", "us_pew_chatgpt": "Pew: ChatGPT",
                       "us_pew_chatgpt_purpose": "Pew: ChatGPT for a purpose", "uk_deloitte": "Deloitte",
                       "uk_ofcom": "Ofcom (16–64)", "uk_ofcom_16plus": "Ofcom 2023 (16+)"}[s] + " (rescaled)")
    fmt_axis(ax); ax.set_title(NAMES[cc], loc="left")
    ax.legend(loc="upper left", fontsize=6.8, handlelength=1.8)
axes[0].set_ylabel("Adults who have used generative AI (%)")
fig.tight_layout(); fig.savefig(OUT / "fig2_fit.png", dpi=300); plt.close(fig)

# ---- Figure 3: market potential by forecast origin ---------------------------------
po = pd.read_csv(REPO / "output/tables/parameters_by_origin.csv", parse_dates=["origin"])
po = po[po.quantity.isin(["m US", "m UK"])]
fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.3), sharey=True)
for ax, cc in zip(axes, ["US", "UK"]):
    for mod, col, mk, off in [("M1 Bass", C["orange"], "o", -9), ("M4 generalised Bass", C["violet"], "^", 9)]:
        g = po[(po.model == mod) & (po.quantity == f"m {cc}")].sort_values("origin")
        x = g.origin + pd.Timedelta(days=off)
        ax.errorbar(x, 100 * g["mean"], yerr=[100 * (g["mean"] - g.lo), 100 * (g.hi - g["mean"])], color=col, marker=mk,
                    ms=4.5, lw=1, elinewidth=0.8, capsize=1.5, label=mod.replace("M1 Bass", "Bass model").replace("M4 generalised Bass", "Generalised Bass model"))
    ax.set_ylim(20, 100); ax.set_xlim(pd.Timestamp("2025-01-01"), pd.Timestamp("2026-12-15"))
    ax.xaxis.set_major_locator(mdates.MonthLocator(bymonth=[2, 5, 8, 11])); ax.xaxis.set_major_formatter(mdates.DateFormatter("%b\n%Y"))
    ax.grid(axis="x", visible=False); ax.set_title(NAMES[cc], loc="left"); ax.set_xlabel("Data available up to")
    ax.legend(loc="lower right", fontsize=7.2)
axes[0].set_ylabel("Estimated market potential m (%)")
fig.tight_layout(); fig.savefig(OUT / "fig3_m_by_origin.png", dpi=300); plt.close(fig)

# ---- Figure 4: projections to 2030 -------------------------------------------------
rb = pd.read_csv(REPO / "output/tables/robustness.csv")
fig, axes = plt.subplots(1, 2, figsize=(7.2, 3.7), sharey=True)
for ax, cc in zip(axes, ["US", "UK"]):
    a = lp[lp.country == cc]
    for mod, col, ls, lab, band in [("M1 Bass", C["orange"], "-", "Bass model", True), ("M4 generalised Bass", C["violet"], "--", "Generalised Bass model", True),
                                    ("M3 Gompertz", C["green"], ":", "Gompertz model", False)]:
        g = a[a.model == mod]
        if band: ax.fill_between(g.date, 100 * g.lo90, 100 * g.hi90, color=col, alpha=0.14, lw=0)
        ax.plot(g.date, 100 * g["mean"], color=col, ls=ls, lw=1.5, label=lab)
    r = rb[(rb.scenario == "rps_lower_bound") & (rb.model == "M1 Bass") & (rb.quantity == f"F_{cc.lower()}_dec2030")].iloc[0]
    ax.errorbar(pd.Timestamp("2031-02-15"), 100 * r["mean"], yerr=[[100 * (r["mean"] - r.lo)], [100 * (r.hi - r["mean"])]], color=C["blue"],
                marker="D", ms=4.5, capsize=2, elinewidth=1, ls="none", label="Bass model, RPS as a lower bound (Dec 2030, 80% interval)", clip_on=False)
    ax.axvline(FREEZE, color=C["grey"], lw=0.7, ls=":"); ax.text(FREEZE - pd.Timedelta(days=25), 3, "data freeze", rotation=90, fontsize=7, color=C["grey"], va="bottom", ha="right")
    ax.set_xlim(pd.Timestamp("2022-11-01"), pd.Timestamp("2031-05-01")); ax.set_ylim(0, 100)
    ax.xaxis.set_major_locator(mdates.YearLocator(2)); ax.xaxis.set_major_formatter(mdates.DateFormatter("%Y"))
    ax.grid(axis="x", visible=False); ax.set_title(NAMES[cc], loc="left")
axes[0].set_ylabel("Adults who have used generative AI (%)")
h, l = axes[0].get_legend_handles_labels()
fig.legend(h, l, loc="lower center", ncol=2, fontsize=7.2, bbox_to_anchor=(0.5, -0.01))
fig.tight_layout(rect=(0, 0.1, 1, 1)); fig.savefig(OUT / "fig4_projections.png", dpi=300); plt.close(fig)

# ---- Derived accuracy table with the naive benchmark -------------------------------
e = pd.read_csv(REPO / "output/tables/rolling_origin_errors.csv")
def acc(df, col="error_pp"):
    return pd.Series({"n": len(df), "MAE": df[col].abs().mean(), "RMSE": np.sqrt((df[col] ** 2).mean()), "bias": df[col].mean()})
rows = []
sets = {"all": e, "excl. post-break": e[e.post_break == 0], "US": e[e.country == "US"], "UK excl. post-break": e[(e.country == "UK") & (e.post_break == 0)],
        "RPS only": e[e.series == "us_rps_any"]}
for nm, df in sets.items():
    for mod, g in df.groupby("model"):
        rows.append(dict(set=nm, model=mod, **acc(g)))
    g = df[df.model == "M1 Bass"]; rows.append(dict(set=nm, model="naive", **acc(g, "naive_error_pp")))
t = pd.DataFrame(rows)
t.to_csv(REPO / "output" / "tables" / "rolling_origin_accuracy_with_naive.csv", index=False)
print(t.pivot(index="model", columns="set", values="MAE").round(2).to_string())
