# The diffusion of generative AI in the United States and the United Kingdom

Code and data for a study that estimates Bass-family diffusion models of the
first use of generative AI by working-age adults in the United States and the
United Kingdom, and forecasts it to 2030. The repository accompanies a journal
article (citation to be added on publication) and a chapter of the author's
doctoral thesis at ISEG, Universidade de Lisboa.

The study uses secondary data only. Twenty-four estimates from seven survey
series (March 2023 to August 2026) are linked to one latent adoption curve per
country through a measurement model. Seven models are estimated in a
hierarchical Bayesian framework that pools the two countries, compared from six
forecast origins against a naive benchmark, and used to produce forecasts that
were recorded before the data they refer to were released.

## What is in the repository

```
config/          config.yaml (all settings, priors, series definitions); events.csv (dated market events)
data/raw/        raw inputs: NOT in the repository (README.md there explains how to obtain them)
data/external/   published figures entered by hand, each with its source and access date
data/interim/    aggregate estimates computed from respondent-level survey files
data/processed/  the analysis data set and the covariates
python/          data pipeline; figures of the article
R/               estimation (cmdstanr), validation, forecasts, robustness
stan/            Stan programs
output/tables/   every table of results, as CSV
output/figures/  figures (paper/ holds the figures of the article)
output/forecasts/ the registered forecast file and its checksum
```

The processed data and all output tables are included, so the results can be
inspected, and the figures redrawn, without re-running the models.

## Models

| Code | Model | Program |
| --- | --- | --- |
| M0 | Pure external influence (modified exponential) | `stan/bass_family.stan` |
| M1 | Bass | `stan/bass_family.stan` |
| M2 | Logistic | `stan/sigmoid_family.stan` |
| M3 | Gompertz | `stan/sigmoid_family.stan` |
| M4 | Generalised Bass, with dated market events | `stan/bass_family.stan` |
| M5 | Time-varying imitation | `stan/bass_family.stan` |
| M6 | Dynamic market potential (internet ceiling) | `stan/bass_family.stan` |

Each survey estimate is modelled as `y = lambda_s * F_c(t) + delta_s * post_break + error`,
with a standard deviation of `kappa_s` times the sampling standard error. The
scale factor `lambda_s` is fixed at 1 for one reference series per country, and
`delta_s` is a level shift after a documented change of question wording. Time
is measured in months from 1 December 2022 (ChatGPT was released on
30 November 2022).

## Pipeline

| Step | Script | Main output |
| --- | --- | --- |
| 1 | `python/01_fetch_fred.py` | `data/raw/fred/*` (vintage fixed at the freeze date) |
| 2 | `python/02_process_ofcom.py` | `data/interim/ofcom_estimates.csv` |
| 3 | `python/03_process_pew.py` | `data/interim/pew_estimates.csv` |
| 4 | `python/04_build_dataset.py` | `data/processed/analysis_dataset.csv`, `series_table.csv` |
| 5 | `python/05_prepare_covariates.py` | `data/processed/shocks.csv`, `ceiling.csv`, `internet_annual.csv` |
| 6 | `R/01_descriptives.R` | `output/tables/dataset_composition.csv` |
| 7 | `R/02_nls_fits.R` | `nls_estimates.csv`, `internet_benchmark.csv` |
| 8 | `R/03_fit_stan.R` | `stan_parameters.csv`, `stan_diagnostics.csv`, `loo_comparison.csv`, `latent_paths.csv` |
| 9 | `R/07_post_analysis.R` | hypothesis tests, country differences, identifiability, posterior predictive checks, profile of the ceiling |
| 10 | `R/04_validation.R` | `rolling_origin_errors.csv`, `rolling_origin_accuracy*.csv` |
| 11 | `R/08_parameters_by_origin.R` | `parameters_by_origin.csv` |
| 12 | `R/06_robustness.R` | `robustness.csv`, `robustness_diagnostics.csv` |
| 13 | `R/05_forecasts.R` | `output/forecasts/forecasts_registered_*.csv` and `.md5` |
| 14 | `python/06_paper_figures.py` | `output/figures/paper/fig1–fig4`, `rolling_origin_accuracy_with_naive.csv` |

## Where each result of the article comes from

| Item in the article | Script | File |
| --- | --- | --- |
| Table 1, survey series | `python/04_build_dataset.py` | `data/processed/analysis_dataset.csv`, `series_table.csv` |
| Fig. 1, survey estimates | `python/06_paper_figures.py` | `output/figures/paper/fig1_series.png` |
| Table 3, least squares fits; internet benchmark | `R/02_nls_fits.R` | `nls_estimates.csv`, `internet_benchmark.csv` |
| Table 4, posterior estimates | `R/03_fit_stan.R` | `stan_parameters.csv` |
| Table 5, fit and diagnostics | `R/03_fit_stan.R`, `R/07_post_analysis.R` | `loo_comparison.csv`, `ppc_summary.csv`, `stan_diagnostics.csv`, `loo_pareto_k.csv` |
| Measurement terms | `R/07_post_analysis.R` | `measurement_terms_M1.csv` |
| Fig. 2, model fit | `python/06_paper_figures.py` | `fig2_fit.png` (from `latent_paths_all_models.csv`) |
| Tests of H1 and H2 | `R/07_post_analysis.R` | `p1_external_influence.csv`, `p2_alpha_beta.csv`, `p2_internal_share_M1.csv`, `country_differences.csv`, `identifiability_*.csv` |
| Fig. 3, ceiling by forecast origin | `R/08_parameters_by_origin.R` | `parameters_by_origin.csv`, `fig3_m_by_origin.png` |
| Profile of the ceiling | `R/07_post_analysis.R` | `p6_m_profile.csv`, `p6_m_profile_summary.csv` |
| Table 6, out-of-sample accuracy | `R/04_validation.R`, `python/06_paper_figures.py` | `rolling_origin_errors.csv`, `rolling_origin_accuracy_with_naive.csv` |
| Table 7, robustness | `R/06_robustness.R` | `robustness.csv`, `robustness_diagnostics.csv` |
| Table 8, registered forecasts | `R/05_forecasts.R` | `output/forecasts/forecasts_registered_2026-11-01_recorded_2026-11-02.csv` |
| Fig. 4, projections | `python/06_paper_figures.py` | `fig4_projections.png` |
| Table A1, market events | – | `config/events.csv` |
| Table B1, priors | – | `config/config.yaml`, `stan/*.stan` |

A note on numbering. The code was first written for the thesis chapter, and its
comments use the numbering of that chapter ("Section 7.4", "Table 7.8"). Files
named `p1_*`, `p2_*` and `p6_*` hold the tests of hypotheses H1, H2 and H3 of
the article. The files `output/figures/fig7_2` to `fig7_5` are the thesis
versions of Figs. 1 to 4.

## Requirements

- Python 3.10 or later: `pip install -r requirements.txt`
- R 4.3 or later with yaml, readr, dplyr, tidyr, purrr, ggplot2, minpack.lm,
  posterior, loo, jsonlite and cmdstanr, and CmdStan 2.33 or later:
  `Rscript R/00_setup.R`
- For step 1 only, a free FRED API key in the environment variable `FRED_API_KEY`

The versions used for the results in the repository are listed in
`output/sessionInfo.txt`.

## How to run

From the repository root:

```bash
make setup        # Python and R packages, CmdStan (once)
make paper        # redraw the figures of the article from the saved tables (seconds)
make models       # steps 6-12: re-estimate everything from the processed data (about 4 hours on two cores)
make data         # steps 1-5: rebuild the data set (needs the raw data and a FRED key)
make check        # syntax checks; checksum of the registered forecast file
```

Each script can also be run alone, for example `Rscript R/03_fit_stan.R 1 0`
(only M1 and M0) or `Rscript R/06_robustness.R deff_3 all_adults`.

- **Interrupted runs.** `STUDY4_RESUME=1` makes `R/03_fit_stan.R`,
  `R/04_validation.R` and `R/06_robustness.R` reuse the fits and checkpoints
  already saved.
- **Quick test.** `STUDY4_FAST=1 Rscript R/03_fit_stan.R` uses 2 chains and
  300 + 300 iterations. Use it only to check that the code runs.
- **Do not run `make forecasts` to "reproduce" Table 8.** That step records new
  forecasts. The registered file is the one already in `output/forecasts/`.

Settings of the reported results: 4 chains of 1,000 warm-up and 2,000 sampling
iterations, `adapt_delta` 0.99, seed 20261101 (validation and robustness runs:
2 chains of 500 + 500). Re-estimation reproduces the tables up to Monte Carlo
error and differences between platforms.

## Registered forecasts

The forecasts in `output/forecasts/` were produced from data frozen on
1 November 2026 and recorded with an MD5 checksum on 2 November 2026, before
the survey waves they refer to were released. See
[`output/forecasts/README.md`](output/forecasts/README.md). The date of the
first public commit of this repository is the date from which the record can be
verified by others.

## Data and licences

| Source | Access | Conditions |
| --- | --- | --- |
| Real-Time Population Survey, generative AI tracker (Bick, Blandin & Deming) | FRED, series `RPSGENAIUSAGESHAREALL` | Cite Bick, Blandin & Deming (2026), *Management Science*, 72(10), 8440–8456, https://doi.org/10.1287/mnsc.2025.02523 |
| Pew Research Center, American Trends Panel, waves 123, 131, 142, 152, 164 | Free account and data licence | Research use only; the files may not be redistributed; cite "Pew Research Center's American Trends Panel" |
| Ofcom, Adults' Media Literacy Tracker, 2024 and 2025 | Ofcom statistical release calendar | Cite Ofcom |
| Deloitte, Digital Consumer Trends (UK) | Published figures | Cite Deloitte |
| World Bank, World Development Indicators (internet users) | FRED, series `ITNETUSERP2USA`, `ITNETUSERP2GBR` | Cite the World Bank |

No respondent-level file is in the repository. `data/interim/` and
`data/processed/` hold only aggregate estimates, each with its source address
and access date. To rebuild them, obtain the raw files as described in
`data/raw/README.md`.

*This study uses data from Pew Research Center's American Trends Panel. The
opinions expressed herein, including any implications for policy, are those of
the author and not of Pew Research Center.*

## Use of AI assistance

Data retrieval and the code were prepared with the assistance of an AI agent
(Claude, Anthropic) under the author's supervision. All values in the data set
come from the providers' pages, files or APIs, or are computed from their
respondent-level files, and the scripts reproduce the providers' published
totals.

## Citation

Abreu, R. (2026). *The diffusion of generative AI in the United States and the
United Kingdom: Code and data* [Computer software]. See `CITATION.cff`. The
reference to the article will be added here when it is published.

## Licence

Code: MIT (see `LICENSE`). The data remain subject to their providers' terms.
