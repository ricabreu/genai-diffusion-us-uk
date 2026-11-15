# Robustness checks (Section 7.4.5, Table 7.8). Each scenario re-estimates the
# Bass model (M1) and, for comparison, pure external influence (M0).
# Rscript R/06_robustness.R              (all scenarios)
# Rscript R/06_robustness.R deff_3 all_adults   (selected scenarios)

source("R/functions.R")
cfg <- load_cfg()
inp <- read_inputs(cfg)
base_rows <- primary_rows(inp$data)
stab0 <- inp$series
h <- cfg$harmonisation
fore <- forecast_frame(cfg) %>% filter(series == "latent")

rescale_se <- function(d, deff_new) {
  # published-only estimates: SE was computed with the default design effect
  d %>% mutate(se = ifelse(se_source == "published n x deff", se * sqrt(deff_new / h$design_effect), se))
}

scenarios <- list(
  baseline          = function() list(rows = base_rows, stab = stab0),
  # current use can fall when people stop using the tools: the RPS series as a lower bound of F
  rps_lower_bound   = function() list(rows = base_rows, stab = stab0, lower_bound = "us_rps_any"),
  rps_outside_work  = function() list(rows = bind_rows(filter(base_rows, series != "us_rps_any"),
                                                       filter(inp$data, series == "us_rps_nonwork")), stab = stab0),
  pew2026_added     = function() list(rows = bind_rows(base_rows, filter(inp$data, grepl("^us_pew2026", series))),
                                      stab = stab0),
  # launch moved to mid-March 2023 (wide availability): time origin shifts by 3.5 months
  launch_mar2023    = function() list(rows = base_rows %>% mutate(t = pmax(t - 3.5, 0)) %>%
                                        filter(!(series != "anchor" & t <= 0)), stab = stab0,
                                      fore = fore %>% mutate(t = t - 3.5)),
  no_deloitte_2025  = function() list(rows = filter(base_rows, !(series == "uk_deloitte" & substr(date_mid, 1, 4) == "2025")),
                                      stab = stab0),
  no_ofcom_2025     = function() list(rows = filter(base_rows, !(series == "uk_ofcom" & post_break == 1)), stab = stab0),
  deff_1_5          = function() list(rows = rescale_se(base_rows, 1.5), stab = stab0),
  deff_3            = function() list(rows = rescale_se(base_rows, 3.0), stab = stab0),
  priors_half       = function() list(rows = base_rows, stab = stab0, prior_scale = 0.5),
  priors_double     = function() list(rows = base_rows, stab = stab0, prior_scale = 2),
  all_adults        = function() list(rows = secondary_rows(inp$data, cfg),
                                      stab = apply_overrides(stab0, cfg$secondary_analysis$overrides))
)
# leave-one-series-out (estimation series other than the anchor and reference series)
for (s in setdiff(unique(base_rows$series), c("anchor", "uk_ofcom", "us_pew_chatbot"))) {
  local({ ss <- s; scenarios[[paste0("drop_", ss)]] <<- function() list(rows = filter(base_rows, series != ss), stab = stab0) })
}

args <- commandArgs(trailingOnly = TRUE)
run <- if (length(args)) args else names(scenarios)
res <- list(); diag_rows <- list()
# checkpoint per scenario and model (STUDY4_RESUME=1 skips those already done)
ckpt <- out_dir(cfg, "checkpoints", "robustness")
resume <- Sys.getenv("STUDY4_RESUME") == "1"
if (!resume) unlink(list.files(ckpt, full.names = TRUE))
for (sc in run) {
  spec <- scenarios[[sc]]()
  for (code in c(1, 0)) {
    f_ck <- file.path(ckpt, sprintf("%s_model%d", sc, code))
    if (resume && file.exists(paste0(f_ck, "_res.csv"))) {
      res[[length(res) + 1]] <- read_csv(paste0(f_ck, "_res.csv"), show_col_types = FALSE)
      diag_rows[[length(diag_rows) + 1]] <- read_csv(paste0(f_ck, "_diag.csv"), show_col_types = FALSE)
      next
    }
    message("Scenario ", sc, " - ", model_label(code))
    sd <- make_stan_data(spec$rows, spec$stab, cfg, code, inp, fore = spec$fore %||% fore,
                         prior_scale = spec$prior_scale %||% 1,
                         lower_bound = spec$lower_bound %||% character())
    rc <- cfg$robustness %||% list(chains = 2, iter_warmup = 1000, iter_sampling = 1000)
    fit <- tryCatch(fit_stan(sd, cfg, chains = rc$chains, iter_warmup = rc$iter_warmup, iter_sampling = rc$iter_sampling),
                    error = function(e) NULL)
    if (is.null(fit)) { warning("Fit failed: ", sc); next }
    dg <- diagnostics_ok(fit, c("p", if (code != 0) "q", "m"))
    diag_rows[[length(diag_rows) + 1]] <- tibble(scenario = sc, model = model_label(code), max_rhat = dg$max_rhat,
                                                 min_ess = dg$min_ess, divergences = dg$divergences)
    pr <- tidy_params(fit, sd, code) %>% filter(grepl("^(p_annual|q_annual|m)\\[", variable))
    fc <- forecast_draws(fit, sd)
    res[[length(res) + 1]] <- bind_rows(
      pr %>% transmute(scenario = sc, model = model_label(code), quantity = label, mean,
                       interval = "90%", lo = `5%`, hi = `95%`),
      fc %>% transmute(scenario = sc, model = model_label(code), quantity = id, mean,
                       interval = "80%", lo = lo80, hi = hi80))
    write_csv(res[[length(res)]], paste0(f_ck, "_res.csv"))
    write_csv(diag_rows[[length(diag_rows)]], paste0(f_ck, "_diag.csv"))
  }
}
res <- bind_rows(res)
write_csv(res, file.path(out_dir(cfg, "tables"), "robustness.csv"))
write_csv(bind_rows(diag_rows), file.path(out_dir(cfg, "tables"), "robustness_diagnostics.csv"))
print(res, n = Inf)
