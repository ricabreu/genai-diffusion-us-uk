# Analysis pipeline. Run from the repository root.
#   make data        Python: FRED retrieval, Ofcom and Pew processing, dataset, covariates (needs the raw data)
#   make models      R/Stan: descriptives, NLS, Bayesian fits, post-estimation, validation, robustness
#   make paper       Python: figures and benchmark accuracy table of the article, from the saved tables
#   make forecasts   R/Stan: record the prospective forecasts (commit the output!)
#   make check       syntax checks and the checksum of the registered forecast file
#   make all         data + models + paper

PY ?= python3
R  ?= Rscript

.PHONY: all data models paper forecasts check setup clean

all: data models paper

setup:
	$(PY) -m pip install -r requirements.txt
	$(R) R/00_setup.R

data:
	$(PY) python/01_fetch_fred.py
	$(PY) python/02_process_ofcom.py
	$(PY) python/03_process_pew.py
	$(PY) python/04_build_dataset.py
	$(PY) python/05_prepare_covariates.py

models:
	$(R) R/01_descriptives.R
	$(R) R/02_nls_fits.R
	$(R) R/03_fit_stan.R
	$(R) R/07_post_analysis.R
	$(R) R/04_validation.R
	$(R) R/08_parameters_by_origin.R
	$(R) R/06_robustness.R

paper:
	$(PY) python/06_paper_figures.py

forecasts:
	$(R) R/05_forecasts.R

check:
	$(PY) -m compileall -q python
	$(PY) python/check_forecast_checksum.py

clean:
	rm -rf output/fits/* stan/bass_family stan/sigmoid_family
