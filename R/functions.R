# Shared functions for the estimation scripts.
# Run all R scripts from the repository root, e.g. `Rscript R/03_fit_stan.R`.

suppressPackageStartupMessages({
  library(yaml)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(posterior)
  library(loo)
})

if (!file.exists("config/config.yaml")) {
  stop("Run the R scripts from the repository root (config/config.yaml not found).")
}

`%||%` <- function(a, b) if (is.null(a)) b else a

load_cfg <- function() {
  cfg <- yaml::read_yaml("config/config.yaml")
  # Quick test run: STUDY4_FAST=1 Rscript R/03_fit_stan.R  (few draws; not for results)
  if (Sys.getenv("STUDY4_FAST") == "1") {
    cfg$estimation$chains <- 2; cfg$estimation$iter_warmup <- 300; cfg$estimation$iter_sampling <- 300
    cfg$validation$chains <- 1; cfg$validation$iter_warmup <- 200; cfg$validation$iter_sampling <- 200
    cfg$robustness <- list(chains = 1, iter_warmup = 200, iter_sampling = 200)
    message("STUDY4_FAST=1: reduced number of draws (test run only)")
  }
  cfg
}

out_dir <- function(cfg, ...) {
  d <- file.path(cfg$paths$output, ...)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

months_since <- function(date, cfg) {
  as.numeric(as.Date(date) - as.Date(cfg$project$t0_date)) / cfg$project$days_per_month
}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------
read_inputs <- function(cfg) {
  p <- cfg$paths$processed
  list(
    data    = read_csv(file.path(p, "analysis_dataset.csv"), show_col_types = FALSE),
    series  = read_csv(file.path(p, "series_table.csv"), show_col_types = FALSE),
    shocks  = read_csv(file.path(p, "shocks.csv"), show_col_types = FALSE),
    ceiling = read_csv(file.path(p, "ceiling.csv"), show_col_types = FALSE),
    internet = read_csv(file.path(p, "internet_annual.csv"), show_col_types = FALSE)
  )
}

# Rows of the primary analysis (Section 7.3.7)
primary_rows <- function(d) filter(d, role == "estimation")

# Rows of the secondary analysis for all adults (config: secondary_analysis)
secondary_rows <- function(d, cfg) {
  sa <- cfg$secondary_analysis
  d %>%
    filter(role %in% sa$include_roles | series %in% sa$include_series) %>%
    mutate(series = recode(series, !!!sa$relabel))
}

apply_overrides <- function(stab, overrides) {
  for (s in names(overrides)) {
    for (k in names(overrides[[s]])) stab[[k]][stab$series == s] <- overrides[[s]][[k]]
  }
  stab
}

# ---------------------------------------------------------------------------
# Stan data
# ---------------------------------------------------------------------------
countries <- c("US", "UK")

forecast_frame <- function(cfg, targets = cfg$forecast_targets) {
  bind_rows(lapply(targets, as_tibble)) %>%
    mutate(t = months_since(date, cfg))
}

make_stan_data <- function(rows, stab, cfg, model, inputs, fore = NULL,
                           prior_scale = 1, priors = cfg$estimation$priors, lower_bound = character()) {
  # lower_bound: series treated as a lower bound of F (censored likelihood, object factor fixed at 1)
  rows <- rows %>% arrange(country, series, t)
  used <- unique(rows$series)
  st <- stab %>% filter(series %in% used) %>% slice(match(used, series))
  st$is_ref[st$series %in% lower_bound] <- 1
  sidx <- setNames(seq_along(used), used)

  # monthly grid: t = 0 .. G (months); covariates at the start of each month g = 0 .. G-1
  G <- max(inputs$ceiling$g)
  if (max(rows$t) >= G) stop("Observation beyond the covariate grid; extend covariates$horizon_end.")
  shock_types <- unlist(cfg$covariates$shock_types)
  shocks <- lapply(countries, function(c) {
    s <- inputs$shocks %>% filter(country == c, g < G) %>% arrange(g)
    as.matrix(s[, shock_types, drop = FALSE])
  })
  ceil <- lapply(countries, function(c) {
    inputs$ceiling %>% filter(country == c, g < G) %>% arrange(g) %>% pull(ceiling)
  })

  if (is.null(fore)) fore <- tibble(country = character(), series = character(), t = numeric(),
                                    date = character())
  fore <- fore %>%
    mutate(f_series = ifelse(series %in% names(sidx), sidx[series], 0L))
  if (any(fore$series != "latent" & fore$f_series == 0)) {
    warning("Forecast targets for series not in the data are returned on the latent scale.")
  }
  # post-break flag and a typical SE for each forecast target
  brk <- setNames(st$break_date, st$series)
  fore <- fore %>% mutate(
    f_post_break = as.numeric(!is.na(brk[series]) & as.Date(date) >= as.Date(brk[series])),
    f_post_break = ifelse(is.na(f_post_break), 0, f_post_break),
    f_se = map_dbl(series, function(s) {
      v <- rows$se[rows$series == s]
      if (length(v)) median(v) else 0.01
    })
  )

  list(
    N = nrow(rows), C = length(countries), S = length(used),
    country = match(rows$country, countries), series = unname(sidx[rows$series]),
    t = rows$t, g0 = grid_index(rows$t, G), gw = rows$t - grid_index(rows$t, G),
    y = rows$y, se = rows$se, post_break = rows$post_break,
    is_ref = as.integer(st$is_ref), fix_kappa = as.integer(st$series == "anchor"),
    is_lb = as.integer(rows$series %in% lower_bound),
    lambda_mu = st$lambda_mu, lambda_sd = st$lambda_sd,
    G = as.integer(G), K = as.integer(cfg$estimation$substeps_per_month), model_code = as.integer(model),
    J = length(shock_types), shocks = shocks, ceiling = ceil,
    logp_mu = priors$logp_mu, logp_sd = priors$logp_sd * prior_scale,
    logq_mu = priors$logq_mu, logq_sd = priors$logq_sd * prior_scale,
    logitm_mu = priors$logitm_mu, logitm_sd = priors$logitm_sd * prior_scale,
    tau_sd = priors$tau_sd * prior_scale,
    logkappa_mu = priors$logkappa_mu, logkappa_sd = priors$logkappa_sd,
    delta_sd = priors$delta_sd,
    NF = nrow(fore), f_country = match(fore$country, countries), f_series = as.integer(fore$f_series),
    f_t = fore$t, f_g0 = grid_index(fore$t, G), f_gw = fore$t - grid_index(fore$t, G),
    f_post_break = fore$f_post_break, f_se = fore$f_se,
    # bookkeeping (ignored by Stan)
    .series_names = used, .rows = rows, .fore = fore, .shock_types = shock_types
  )
}

# Index of the grid interval [g, g+1] that contains t (t = G uses the last interval)
grid_index <- function(t, G) {
  if (any(t > G)) stop("Time beyond the covariate grid; extend covariates$horizon_end in config.yaml.")
  as.integer(pmin(floor(t), G - 1))
}

stan_input <- function(sd) sd[!startsWith(names(sd), ".")]

# ---------------------------------------------------------------------------
# Fitting
# ---------------------------------------------------------------------------
.compiled <- new.env()
get_model <- function(code) {
  file <- if (code %in% c(2, 3)) "stan/sigmoid_family.stan" else "stan/bass_family.stan"
  if (!requireNamespace("cmdstanr", quietly = TRUE)) stop("Package cmdstanr is required: run R/00_setup.R")
  if (is.null(.compiled[[file]])) .compiled[[file]] <- cmdstanr::cmdstan_model(file)
  .compiled[[file]]
}

model_label <- function(code) {
  c(`0` = "M0 pure external", `1` = "M1 Bass", `2` = "M2 logistic", `3` = "M3 Gompertz",
    `4` = "M4 generalised Bass", `5` = "M5 time-varying q", `6` = "M6 dynamic m")[as.character(code)]
}

# Initial values: near the centre of the priors, with random jitter per chain.
# Stan's default (uniform on [-2, 2] on the unconstrained scale) can start the
# ODE at imitation rates above 7 per month, where chains get stuck.
make_inits <- function(sd, chains, seed) {
  set.seed(seed)
  C <- sd$C; S <- sd$S; code <- sd$model_code
  lapply(seq_len(chains), function(i) {
    common <- list(mu_logitm = qlogis(0.65) + rnorm(1, 0, 0.2), tau_logitm = runif(1, 0.05, 0.3),
                   z_m = rnorm(C, 0, 0.3), lambda_raw = pmax(sd$lambda_mu + rnorm(S, 0, 0.02), 0.1),
                   delta = rnorm(S, 0, 0.01), log_kappa = rnorm(S, 0.4, 0.1))
    if (code %in% c(2, 3)) {
      return(c(common, list(mu_logr = log(0.1) + rnorm(1, 0, 0.2), tau_logr = runif(1, 0.05, 0.3),
                            z_r = rnorm(C, 0, 0.3),
                            mu_loc = if (code == 2) 15 + rnorm(1, 0, 2) else log(2.5) + rnorm(1, 0, 0.1),
                            tau_loc = runif(1, 0.05, 0.3), z_l = rnorm(C, 0, 0.3))))
    }
    out <- c(common, list(mu_logp = log(0.04) + rnorm(1, 0, 0.3), tau_logp = runif(1, 0.05, 0.3),
                          z_p = rnorm(C, 0, 0.3)))
    if (code != 0) out <- c(out, list(mu_logq = array(log(0.005) + rnorm(1, 0, 0.5)),
                                      tau_logq = array(runif(1, 0.05, 0.3)), z_q = rnorm(C, 0, 0.3)))
    if (code == 5) out$alpha <- array(runif(1, 0.5, 1.5))
    if (code == 4) out$beta <- rnorm(sd$J, 0, 0.1)
    out
  })
}

fit_stan <- function(sd, cfg, chains = cfg$estimation$chains, iter_warmup = cfg$estimation$iter_warmup,
                     iter_sampling = cfg$estimation$iter_sampling, refresh = 0) {
  mod <- get_model(sd$model_code)
  mod$sample(data = stan_input(sd), seed = cfg$estimation$seed, chains = chains,
             init = make_inits(sd, chains, cfg$estimation$seed),
             parallel_chains = min(chains, parallel::detectCores()),
             iter_warmup = iter_warmup, iter_sampling = iter_sampling,
             adapt_delta = cfg$estimation$adapt_delta, refresh = refresh, show_messages = FALSE)
}

diagnostics_ok <- function(fit, vars) {
  s <- fit$summary(variables = vars)
  d <- fit$diagnostic_summary(quiet = TRUE)
  list(max_rhat = max(s$rhat, na.rm = TRUE), min_ess = min(s$ess_bulk, na.rm = TRUE),
       divergences = sum(d$num_divergent),
       ok = max(s$rhat, na.rm = TRUE) < 1.01 && min(s$ess_bulk, na.rm = TRUE) > 400 && sum(d$num_divergent) == 0)
}

key_params <- function(code) {
  base <- c("m", "lambda", "delta", "kappa")
  if (code %in% c(2, 3)) return(c("r", "b", base))
  extra <- switch(as.character(code), `0` = NULL, `1` = "t_peak", `4` = "beta", `5` = "alpha", NULL)
  c("p_annual", if (code != 0) "q_annual", extra, base)
}

tidy_params <- function(fit, sdat, code) {
  s <- fit$summary(variables = key_params(code), "mean", "sd",
                   ~quantile(.x, probs = c(0.05, 0.95), na.rm = TRUE), "rhat", "ess_bulk")
  suppressWarnings(s %>% mutate(model = model_label(code),
               label = case_when(
                 grepl("^alpha", variable) ~ "alpha",
                 grepl("^beta\\[", variable) ~
                   paste0("beta ", sdat$.shock_types[as.integer(gsub("\\D", "", variable))]),
                 grepl("^(lambda|delta|kappa)\\[", variable) ~
                   paste0(sub("\\[.*", "", variable), " ", sdat$.series_names[as.integer(gsub("\\D", "", variable))]),
                 grepl("\\[[12]\\]$", variable) ~
                   paste0(sub("\\[.*", "", variable), " ", countries[as.integer(gsub(".*\\[(\\d)\\]", "\\1", variable))]),
                 TRUE ~ variable)))
}

loo_fit <- function(fit, sd) {
  ll <- fit$draws("log_lik", format = "matrix")
  keep <- sd$.rows$series != "anchor"
  loo::loo(ll[, keep, drop = FALSE], r_eff = loo::relative_eff(exp(ll[, keep, drop = FALSE]),
           chain_id = rep(seq_len(fit$num_chains()), each = nrow(ll) / fit$num_chains())))
}

forecast_draws <- function(fit, sd) {
  if (sd$NF == 0) return(tibble())
  yf <- fit$draws("y_fore", format = "matrix")
  Ff <- fit$draws("F_fore", format = "matrix")
  q <- function(m, p) apply(m, 2, quantile, probs = p, na.rm = TRUE)
  bind_cols(sd$.fore %>% select(any_of(c("id", "country", "series", "date", "description"))),
            tibble(mean = colMeans(yf), lo95 = q(yf, 0.025), lo80 = q(yf, 0.10),
                   hi80 = q(yf, 0.90), hi95 = q(yf, 0.975), latent_F_mean = colMeans(Ff)))
}

# ---------------------------------------------------------------------------
# Closed forms (Step 1, NLS) and accuracy measures
# ---------------------------------------------------------------------------
bass_F <- function(t, p, q, m) m * (1 - exp(-(p + q) * t)) / (1 + (q / p) * exp(-(p + q) * t))
external_F <- function(t, p, m) m * (1 - exp(-p * t))
logistic_F <- function(t, r, b, m) m / (1 + exp(-r * (t - b)))
gompertz_F <- function(t, r, b, m) m * exp(-b * exp(-r * t))

mae  <- function(e) mean(abs(e), na.rm = TRUE)
rmse <- function(e) sqrt(mean(e^2, na.rm = TRUE))
