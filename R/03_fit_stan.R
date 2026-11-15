# Step 2 (Section 7.4.2): hierarchical Bayesian estimation of all models on the
# primary dataset, with convergence checks and LOO comparison (Section 7.4.3).
# Rscript R/03_fit_stan.R            (all models)
# Rscript R/03_fit_stan.R 1 0        (only the listed model codes)

source("R/functions.R")
cfg <- load_cfg()
inp <- read_inputs(cfg)
args <- commandArgs(trailingOnly = TRUE)
codes <- if (length(args)) as.integer(args) else
  c(unlist(cfg$estimation$models$bass_family), unlist(cfg$estimation$models$sigmoid_family))

rows <- primary_rows(inp$data)
# STUDY4_RESUME=1 reuses fits already saved in output/fits (after an interruption)
resume <- Sys.getenv("STUDY4_RESUME") == "1"
fore <- forecast_frame(cfg)
params <- list(); loos <- list(); diag <- list(); paths <- list()

for (code in codes) {
  message("Fitting ", model_label(code), " ...")
  sd <- make_stan_data(rows, inp$series, cfg, code, inp, fore = fore)
  f_rds <- file.path(out_dir(cfg, "fits"), sprintf("primary_model%d.rds", code))
  if (resume && file.exists(f_rds)) {
    message("  resuming from ", f_rds); fit <- readRDS(f_rds)
  } else {
    fit <- fit_stan(sd, cfg)
    fit$save_object(f_rds)
  }
  vars <- if (code %in% c(2, 3)) c("r", "b", "m") else c("p", if (code != 0) "q", "m")
  dg <- diagnostics_ok(fit, vars)
  diag[[length(diag) + 1]] <- tibble(model = model_label(code), !!!dg[c("max_rhat", "min_ess", "divergences", "ok")])
  if (!dg$ok) warning(model_label(code), ": convergence criteria not met (see diagnostics.csv)")
  params[[length(params) + 1]] <- tidy_params(fit, sd, code)
  loos[[model_label(code)]] <- loo_fit(fit, sd)
  if (!code %in% c(2, 3)) {
    # latent paths on the monthly grid, for plots (Figures 7.3-7.4)
    Fg <- fit$draws("Fg", format = "matrix")
    idx <- expand.grid(c = 1:2, g = 0:sd$G)
    paths[[length(paths) + 1]] <- tibble(model = model_label(code), country = countries[idx$c], t = idx$g,
      mean = colMeans(Fg[, sprintf("Fg[%d,%d]", idx$c, idx$g + 1)]),
      lo90 = apply(Fg[, sprintf("Fg[%d,%d]", idx$c, idx$g + 1)], 2, quantile, 0.05),
      hi90 = apply(Fg[, sprintf("Fg[%d,%d]", idx$c, idx$g + 1)], 2, quantile, 0.95))
  }
}

tabs <- out_dir(cfg, "tables")
write_csv(bind_rows(params), file.path(tabs, "stan_parameters.csv"))
write_csv(bind_rows(diag), file.path(tabs, "stan_diagnostics.csv"))
if (length(paths)) write_csv(bind_rows(paths), file.path(tabs, "latent_paths.csv"))
if (length(loos) > 1) {
  cmp <- loo::loo_compare(loos)
  cmp_df <- as_tibble(cmp, rownames = "model") %>% select(model, elpd_diff, se_diff, elpd_loo, p_loo, looic)
  write_csv(cmp_df, file.path(tabs, "loo_comparison.csv"))
  print(cmp_df)
}
print(bind_rows(diag))
