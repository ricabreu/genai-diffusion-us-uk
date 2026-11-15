# Post-estimation analysis (Sections 7.4.4-7.4.5 and 7.5): tests of the
# propositions, differences between countries, identifiability, posterior
# predictive checks, the market-potential profile, and Figures 7.3 and 7.5.
# Needs the fits saved by R/03_fit_stan.R and the tables of R/02_nls_fits.R.
# Rscript R/07_post_analysis.R

source("R/functions.R")
suppressPackageStartupMessages({ library(ggplot2); library(minpack.lm) })
cfg <- load_cfg()
inp <- read_inputs(cfg)
rows <- primary_rows(inp$data)
fore <- forecast_frame(cfg)
tabs <- out_dir(cfg, "tables"); figs <- out_dir(cfg, "figures")
codes <- c(unlist(cfg$estimation$models$bass_family), unlist(cfg$estimation$models$sigmoid_family))
fit_file <- function(code) file.path(cfg$paths$output, "fits", sprintf("primary_model%d.rds", code))
fits <- setNames(lapply(codes, function(k) if (file.exists(fit_file(k))) readRDS(fit_file(k))), codes)
fits <- fits[!vapply(fits, is.null, logical(1))]
sds <- lapply(names(fits), function(k) make_stan_data(rows, inp$series, cfg, as.integer(k), inp, fore = fore))
names(sds) <- names(fits)
G <- sds[[1]]$G
to_date <- function(t) as.Date(cfg$project$t0_date) + t * cfg$project$days_per_month
summ <- function(x, prefix = "") tibble(mean = mean(x), q05 = unname(quantile(x, 0.05)), q95 = unname(quantile(x, 0.95)))
draws_mat <- function(fit, v) {   # plain numeric matrix (a draws_matrix keeps one-column subsets as matrices)
  x <- fit$draws(v, format = "matrix")
  matrix(as.numeric(x), nrow = nrow(x), dimnames = list(NULL, colnames(x)))
}

# Benchmarks for P1: Sultan, Farley & Lehmann (1990) and the internet fits of R/02
sultan <- c(p = 0.03, q = 0.38)
inet <- read_csv(file.path(tabs, "internet_benchmark.csv"), show_col_types = FALSE) %>%
  group_by(country) %>%
  summarise(p_hi = max(p_annual), p_lo = min(p_annual), qp_lo = min(q_over_p), qp_hi = max(q_over_p), .groups = "drop")

# ---------------------------------------------------------------------------
# P1: external influence (models with p): annual p and q/p against benchmarks
# ---------------------------------------------------------------------------
p1 <- list()
for (k in intersect(names(fits), c("0", "1", "4", "5", "6"))) {
  f <- fits[[k]]
  pa <- draws_mat(f, "p_annual"); qa <- draws_mat(f, "q_annual")
  for (ci in seq_along(countries)) {
    cc <- countries[ci]; b <- filter(inet, country == cc)
    p <- pa[, ci]; q <- qa[, ci]; qp <- q / p
    p1[[length(p1) + 1]] <- tibble(
      model = model_label(as.integer(k)), country = cc,
      p_annual = mean(p), p_q05 = quantile(p, 0.05), p_q95 = quantile(p, 0.95),
      P_p_gt_sultan = mean(p > sultan["p"]), P_p_gt_internet = mean(p > b$p_hi),
      q_annual = mean(q), q_q05 = quantile(q, 0.05), q_q95 = quantile(q, 0.95),
      q_over_p = mean(qp), qp_q05 = quantile(qp, 0.05), qp_q95 = quantile(qp, 0.95),
      P_qp_lt_sultan = mean(qp < sultan["q"] / sultan["p"]), P_qp_lt_internet = mean(qp < b$qp_lo),
      P_q_gt_p = mean(q > p))
  }
}
p1 <- bind_rows(p1)
write_csv(p1, file.path(tabs, "p1_external_influence.csv"))

# ---------------------------------------------------------------------------
# P2: time-varying imitation (M5 alpha) and the share of new adoptions due to
# internal influence in M1, q F/m / (p + q F/m) (Eq. 6.1)
# ---------------------------------------------------------------------------
p2 <- list()
if ("5" %in% names(fits)) {
  a <- as.vector(draws_mat(fits[["5"]], "alpha_v"))
  p2[[length(p2) + 1]] <- tibble(quantity = "alpha (M5)", country = "pooled", !!!summ(a), P_gt_0.5 = mean(a > 0.5))
}
if ("4" %in% names(fits)) {
  bt <- draws_mat(fits[["4"]], "beta")
  for (j in seq_len(ncol(bt))) {
    p2[[length(p2) + 1]] <- tibble(quantity = paste0("beta ", sds[["4"]]$.shock_types[j], " (M4)"),
                                   country = "pooled", !!!summ(bt[, j]), P_gt_0 = mean(bt[, j] > 0))
  }
}
p2 <- bind_rows(p2)
write_csv(p2, file.path(tabs, "p2_alpha_beta.csv"))

internal <- list()
if ("1" %in% names(fits)) {
  f <- fits[["1"]]
  pm <- draws_mat(f, "p"); qm <- draws_mat(f, "q"); mm <- draws_mat(f, "m"); Fg <- draws_mat(f, "Fg")
  at <- c(`Dec 2023` = 12, `Dec 2024` = 24, `Dec 2025` = 36, `Nov 2026 (freeze)` = 47, `Dec 2030` = 96)
  for (ci in seq_along(countries)) for (lab in names(at)) {
    Fx <- Fg[, sprintf("Fg[%d,%d]", ci, at[[lab]] + 1)]
    imit <- qm[, ci] * Fx / mm[, ci]
    internal[[length(internal) + 1]] <- tibble(country = countries[ci], month = lab, !!!summ(imit / (pm[, ci] + imit)))
  }
}
internal <- bind_rows(internal)
write_csv(internal, file.path(tabs, "p2_internal_share_M1.csv"))

# ---------------------------------------------------------------------------
# Q7.5: differences between countries (US minus UK)
# ---------------------------------------------------------------------------
diffs <- list()
for (k in intersect(names(fits), c("0", "1", "6"))) {
  vars <- c("p_annual", if (k != "0") "q_annual", "m")
  for (v in vars) {
    d <- draws_mat(fits[[k]], v)
    diffs[[length(diffs) + 1]] <- tibble(model = model_label(as.integer(k)), quantity = paste0(v, " US - UK"),
                                         !!!summ(d[, 1] - d[, 2]), P_US_gt_UK = mean(d[, 1] > d[, 2]))
  }
}
diffs <- bind_rows(diffs)
write_csv(diffs, file.path(tabs, "country_differences.csv"))

# ---------------------------------------------------------------------------
# Identifiability (Section 7.4.5): posterior correlations and prior-to-posterior
# contraction of the country parameters in M1, and of the measurement terms
# ---------------------------------------------------------------------------
pr <- cfg$estimation$priors
set.seed(cfg$estimation$seed)
nsim <- 40000
prior_country <- function(mu, sd) rnorm(nsim, mu, sd) + abs(rnorm(nsim, 0, pr$tau_sd)) * rnorm(nsim)
ident <- list(); cors <- list()
for (k in intersect(names(fits), c("0", "1", "6"))) {
  f <- fits[[k]]
  lp <- log(draws_mat(f, "p")); lm <- qlogis(draws_mat(f, "m"))
  lq <- if (k != "0") log(draws_mat(f, "q")) else NULL
  priors_sd <- c(log_p = sd(prior_country(pr$logp_mu, pr$logp_sd)),
                 log_q = sd(prior_country(pr$logq_mu, pr$logq_sd)),
                 logit_m = sd(prior_country(pr$logitm_mu, pr$logitm_sd)))
  for (ci in seq_along(countries)) {
    post <- list(log_p = lp[, ci], logit_m = lm[, ci])
    if (!is.null(lq)) post$log_q <- lq[, ci]
    for (nm in names(post)) {
      ident[[length(ident) + 1]] <- tibble(model = model_label(as.integer(k)), country = countries[ci], parameter = nm,
        prior_sd = priors_sd[[nm]], posterior_sd = sd(post[[nm]]),
        contraction = 1 - var(post[[nm]]) / priors_sd[[nm]]^2)
    }
    if (!is.null(lq)) {
      cm <- cor(cbind(log_p = lp[, ci], log_q = lq[, ci], logit_m = lm[, ci]))
      cors[[length(cors) + 1]] <- tibble(model = model_label(as.integer(k)), country = countries[ci],
        r_logp_logq = cm[1, 2], r_logp_logitm = cm[1, 3], r_logq_logitm = cm[2, 3])
    }
  }
  # measurement terms
  sdk <- sds[[k]]
  lam <- draws_mat(f, "lambda"); del <- draws_mat(f, "delta"); kap <- draws_mat(f, "kappa")
  for (s in seq_len(sdk$S)) {
    nm <- sdk$.series_names[s]
    if (!sdk$is_ref[s]) ident[[length(ident) + 1]] <- tibble(model = model_label(as.integer(k)), country = "-",
      parameter = paste("lambda", nm), prior_sd = sdk$lambda_sd[s], posterior_sd = sd(lam[, s]),
      contraction = 1 - var(lam[, s]) / sdk$lambda_sd[s]^2)
    if (any(sdk$post_break[sdk$series == s] == 1)) ident[[length(ident) + 1]] <- tibble(model = model_label(as.integer(k)),
      country = "-", parameter = paste("delta", nm), prior_sd = sdk$delta_sd, posterior_sd = sd(del[, s]),
      contraction = 1 - var(del[, s]) / sdk$delta_sd^2)
  }
}
write_csv(bind_rows(ident), file.path(tabs, "identifiability_contraction.csv"))
write_csv(bind_rows(cors), file.path(tabs, "identifiability_correlations.csv"))

# Measurement terms of M1 (object factors, level shift, noise factors)
if ("1" %in% names(fits)) {
  s1 <- fits[["1"]]$summary(c("lambda", "delta", "kappa"), "mean", ~quantile(.x, c(0.05, 0.95)))
  s1 <- s1 %>% mutate(term = sub("\\[.*", "", variable),
                      series = sds[["1"]]$.series_names[as.integer(gsub("\\D", "", variable))])
  write_csv(s1, file.path(tabs, "measurement_terms_M1.csv"))
}

# ---------------------------------------------------------------------------
# Posterior predictive checks: coverage of the 90% predictive interval by series
# ---------------------------------------------------------------------------
ppc <- list()
for (k in names(fits)) {
  yr <- draws_mat(fits[[k]], "y_rep"); r <- sds[[k]]$.rows
  lo <- apply(yr, 2, quantile, 0.05); hi <- apply(yr, 2, quantile, 0.95); mu <- colMeans(yr)
  ppc[[length(ppc) + 1]] <- r %>% transmute(model = model_label(as.integer(k)), country, series, date_mid, y,
    pred = mu, inside90 = y >= lo & y <= hi, resid_pp = 100 * (y - mu))
}
ppc <- bind_rows(ppc) %>% filter(series != "anchor")
write_csv(ppc, file.path(tabs, "ppc_observations.csv"))
ppc_sum <- ppc %>% group_by(model) %>%
  summarise(n = n(), coverage90 = mean(inside90), mae_insample_pp = mae(resid_pp), max_abs_resid_pp = max(abs(resid_pp)),
            .groups = "drop")
write_csv(ppc_sum, file.path(tabs, "ppc_summary.csv"))

# Pareto k diagnostics of PSIS-LOO
pk <- bind_rows(lapply(names(fits), function(k) {
  l <- loo_fit(fits[[k]], sds[[k]]); kk <- l$diagnostics$pareto_k
  tibble(model = model_label(as.integer(k)), n = length(kk), k_gt_0.7 = sum(kk > 0.7), k_max = max(kk))
}))
write_csv(pk, file.path(tabs, "loo_pareto_k.csv"))

# ---------------------------------------------------------------------------
# P6: profile of the market potential (Step 1 data; Bass with m fixed on a grid)
# ---------------------------------------------------------------------------
prep <- rows %>% filter(post_break == 0) %>%
  left_join(select(inp$series, series, lambda_mu), by = "series") %>%
  mutate(y_adj = y / lambda_mu, w = 1 / (se / lambda_mu)^2)
t27 <- months_since("2027-12-01", cfg); t30 <- months_since("2030-12-01", cfg)
prof <- list()
for (cc in countries) {
  dat <- filter(prep, country == cc)
  for (mfix in seq(0.50, 1.00, by = 0.025)) {
    best <- NULL
    for (p0 in c(0.005, 0.03)) for (q0 in c(0.01, 0.1)) {
      fm <- tryCatch(nlsLM(y_adj ~ bass_F(t, p, q, mfix), data = dat, start = list(p = p0, q = q0), weights = w,
                           lower = c(1e-5, 1e-6), upper = c(1, 3), control = nls.lm.control(maxiter = 500)),
                     error = function(e) NULL)
      if (!is.null(fm) && (is.null(best) || deviance(fm) < deviance(best))) best <- fm
    }
    if (is.null(best)) next
    co <- coef(best)
    prof[[length(prof) + 1]] <- tibble(country = cc, m = mfix, p_annual = 12 * co[["p"]], q_annual = 12 * co[["q"]],
      wrss = deviance(best), n = nrow(dat), F_dec2027 = bass_F(t27, co[["p"]], co[["q"]], mfix),
      F_dec2030 = bass_F(t30, co[["p"]], co[["q"]], mfix))
  }
}
prof <- bind_rows(prof) %>% group_by(country) %>%
  mutate(s2 = min(wrss) / (n - 3), lr = (wrss - min(wrss)) / s2, in_95 = lr <= qchisq(0.95, 1)) %>%
  ungroup() %>% select(-s2)
write_csv(prof, file.path(tabs, "p6_m_profile.csv"))
prof_sum <- prof %>% filter(in_95) %>% group_by(country) %>%
  summarise(m_lo = min(m), m_hi = max(m), F2027_lo = min(F_dec2027), F2027_hi = max(F_dec2027),
            F2030_lo = min(F_dec2030), F2030_hi = max(F_dec2030), .groups = "drop")
write_csv(prof_sum, file.path(tabs, "p6_m_profile_summary.csv"))

# ---------------------------------------------------------------------------
# Latent paths of all models on the monthly grid (Bass family from Fg; sigmoid
# models in closed form), and Figures 7.3 and 7.5
# ---------------------------------------------------------------------------
grid_t <- 0:G
paths <- list()
for (k in names(fits)) {
  f <- fits[[k]]
  if (k %in% c("2", "3")) {
    r <- draws_mat(f, "r"); b <- draws_mat(f, "b"); mm <- draws_mat(f, "m")
    for (ci in seq_along(countries)) {
      Fm <- sapply(grid_t, function(t) if (k == "2") logistic_F(t, r[, ci], b[, ci], mm[, ci]) else gompertz_F(t, r[, ci], b[, ci], mm[, ci]))
      paths[[length(paths) + 1]] <- tibble(model = model_label(as.integer(k)), country = countries[ci], t = grid_t,
        mean = colMeans(Fm), lo90 = apply(Fm, 2, quantile, 0.05), hi90 = apply(Fm, 2, quantile, 0.95))
    }
  } else {
    Fg <- draws_mat(f, "Fg")
    for (ci in seq_along(countries)) {
      Fm <- Fg[, sprintf("Fg[%d,%d]", ci, grid_t + 1)]
      paths[[length(paths) + 1]] <- tibble(model = model_label(as.integer(k)), country = countries[ci], t = grid_t,
        mean = colMeans(Fm), lo90 = apply(Fm, 2, quantile, 0.05), hi90 = apply(Fm, 2, quantile, 0.95))
    }
  }
}
paths <- bind_rows(paths) %>% mutate(date = to_date(t), country = factor(country, levels = countries))
write_csv(paths, file.path(tabs, "latent_paths_all_models.csv"))

# Observations placed on the latent scale with M1's posterior means: (y - delta) / lambda
if ("1" %in% names(fits)) {
  mt <- read_csv(file.path(tabs, "measurement_terms_M1.csv"), show_col_types = FALSE) %>%
    select(term, series, mean) %>% pivot_wider(names_from = term, values_from = mean)
  src_lab <- c(us_rps_any = "RPS, current use", us_pew_chatgpt = "Pew, ever used ChatGPT",
               us_pew_chatgpt_purpose = "Pew, ChatGPT for a purpose", us_pew_chatbot = "Pew, ever used a chatbot",
               uk_ofcom = "Ofcom, 16-64", uk_ofcom_16plus = "Ofcom 2023, 16+", uk_deloitte = "Deloitte, 16-75")
  obs <- rows %>% filter(series != "anchor") %>% left_join(mt, by = "series") %>%
    mutate(y_lat = (y - delta * post_break) / lambda, lo = (y - 1.96 * se - delta * post_break) / lambda,
           hi = (y + 1.96 * se - delta * post_break) / lambda, date = as.Date(date_mid),
           source = factor(src_lab[series], levels = src_lab), country = factor(country, levels = countries))
  m1 <- filter(paths, model == model_label(1), date <= as.Date(cfg$project$freeze_date) + 31)
  ink <- "#3d3d3a"; muted <- "#73726c"
  g3 <- ggplot() +
    geom_ribbon(data = m1, aes(date, ymin = 100 * lo90, ymax = 100 * hi90), fill = "#2a78d6", alpha = 0.18) +
    geom_line(data = m1, aes(date, 100 * mean), colour = "#2a78d6", linewidth = 0.8) +
    geom_linerange(data = obs, aes(date, ymin = 100 * lo, ymax = 100 * hi), colour = muted, linewidth = 0.4) +
    geom_point(data = obs, aes(date, 100 * y_lat, shape = source), colour = ink, size = 2.4, fill = "white", stroke = 0.7) +
    scale_shape_manual(NULL, values = c(16, 17, 2, 15, 21, 23, 22)) +
    facet_wrap(~country, ncol = 2) +
    scale_y_continuous("Adults who have used generative AI (%)", limits = c(0, 80), expand = c(0, 0)) +
    scale_x_date(NULL, date_breaks = "1 year", date_labels = "%Y") +
    labs(title = "Bass model (M1): latent adoption curve and harmonised observations",
         subtitle = "Line: posterior mean of F(t); band: 90% interval. Points: observations divided by their object\nfactor and corrected for the change of method, with 95% sampling intervals") +
    theme_minimal(base_size = 10) +
    theme(legend.position = "bottom", panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = "#e6e5e0"),
          plot.title = element_text(colour = ink, face = "bold"), plot.subtitle = element_text(colour = muted)) +
    guides(shape = guide_legend(nrow = 2))
  ggsave(file.path(figs, "fig7_3_fit_M1.png"), g3, width = 8, height = 4.8, dpi = 300)
}

pal <- c("#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6")
names(pal) <- model_label(0:6)
lt <- setNames(c("solid", "solid", "dashed", "dotted", "dotdash", "longdash", "twodash"), model_label(0:6))
g4 <- ggplot(paths, aes(date, 100 * mean, colour = model, linetype = model)) +
  geom_vline(xintercept = as.Date(cfg$project$freeze_date), colour = "#a9a8a2", linewidth = 0.4) +
  geom_line(linewidth = 0.7) +
  annotate("text", x = as.Date(cfg$project$freeze_date), y = 5, label = " data freeze", hjust = 0, size = 3, colour = "#73726c") +
  facet_wrap(~country, ncol = 2) +
  scale_colour_manual(NULL, values = pal) + scale_linetype_manual(NULL, values = lt) +
  scale_y_continuous("Adults who have used generative AI (%)", limits = c(0, 100), expand = c(0, 0)) +
  scale_x_date(NULL, date_breaks = "2 years", date_labels = "%Y") +
  labs(title = "Latent adoption curves of the seven models, December 2022 to December 2030",
       subtitle = "Posterior means; working-age adults (US 18-64, UK 16-64)") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = "#e6e5e0"),
        plot.title = element_text(colour = "#3d3d3a", face = "bold"), plot.subtitle = element_text(colour = "#73726c")) +
  guides(colour = guide_legend(nrow = 2), linetype = guide_legend(nrow = 2))
ggsave(file.path(figs, "fig7_5_projections.png"), g4, width = 8, height = 4.8, dpi = 300)

print(p1, width = Inf); print(p2, width = Inf); print(internal); print(diffs, width = Inf)
print(bind_rows(cors), width = Inf); print(ppc_sum); print(pk); print(prof_sum, width = Inf)
message("Post-estimation tables and Figures 7.3 and 7.5 written.")
