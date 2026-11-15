# Step 1 (Section 7.4.2): non-linear least squares by country, and the internet
# benchmark for P1 (Section 7.4.4).
# Object factors are fixed at their prior means; observations after a change of
# method are excluded; the launch condition enters as an observation.
# Rscript R/02_nls_fits.R

source("R/functions.R")
suppressPackageStartupMessages(library(minpack.lm))
cfg <- load_cfg()
inp <- read_inputs(cfg)
stab <- inp$series

prep <- primary_rows(inp$data) %>%
  filter(post_break == 0) %>%
  left_join(select(stab, series, lambda_mu), by = "series") %>%
  mutate(y_adj = y / lambda_mu, se_adj = se / lambda_mu, w = 1 / se_adj^2)

specs <- list(
  M0 = list(f = y_adj ~ external_F(t, p, m), start = list(p = c(0.01, 0.05), m = c(0.6, 0.9)),
            lower = c(1e-5, 0.05), upper = c(1, 1)),
  M1 = list(f = y_adj ~ bass_F(t, p, q, m), start = list(p = c(0.005, 0.03), q = c(1e-4, 0.02, 0.2), m = c(0.6, 0.75, 0.9)),
            lower = c(1e-5, 1e-6, 0.05), upper = c(1, 3, 1)),
  M2 = list(f = y_adj ~ logistic_F(t, r, b, m), start = list(r = c(0.05, 0.2), b = c(10, 30), m = c(0.6, 0.9)),
            lower = c(1e-4, -50, 0.05), upper = c(5, 200, 1)),
  M3 = list(f = y_adj ~ gompertz_F(t, r, b, m), start = list(r = c(0.03, 0.1), b = c(1.5, 4), m = c(0.6, 0.9)),
            lower = c(1e-4, 1e-3, 0.05), upper = c(5, 50, 1))
)

fit_nls <- function(dat, spec) {
  grid <- expand.grid(spec$start)
  best <- NULL
  for (i in seq_len(nrow(grid))) {
    f <- tryCatch(nlsLM(spec$f, data = dat, start = as.list(grid[i, ]), weights = w,
                        lower = spec$lower, upper = spec$upper, control = nls.lm.control(maxiter = 500)),
                  error = function(e) NULL)
    if (!is.null(f) && (is.null(best) || deviance(f) < deviance(best))) best <- f
  }
  best
}

res <- list()
for (cc in countries) {
  dat <- filter(prep, country == cc)
  for (mn in names(specs)) {
    f <- fit_nls(dat, specs[[mn]])
    if (is.null(f)) { warning("No convergence: ", cc, " ", mn); next }
    co <- coef(f)
    resid_pp <- 100 * (dat$y_adj - fitted(f))[dat$series != "anchor"]
    res[[length(res) + 1]] <- tibble(
      country = cc, model = mn, n_obs = sum(dat$series != "anchor"),
      parameter = names(co), estimate = unname(co),
      annualised = ifelse(mn %in% c("M0", "M1") & names(co) %in% c("p", "q"), 12 * unname(co), NA_real_),
      rmse_pp = rmse(resid_pp), aic = AIC(f))
  }
}
nls <- bind_rows(res)
write_csv(nls, file.path(out_dir(cfg, "tables"), "nls_estimates.csv"))
print(nls, n = Inf)

# Internet benchmark: annual Bass fits, same model, assumed start years
bench <- list()
windows <- list(US = 1990:2015, UK = 1990:2024)   # US source break between 2015 and 2016
for (cc in names(windows)) {
  dat <- inp$internet %>% filter(country == cc, year %in% windows[[cc]]) %>% mutate(y = value / 100)
  for (t0 in c(1989, 1991)) {
    dd <- dat %>% mutate(t = year - t0 + 0.5, w = 1)
    f <- fit_nls(dd %>% mutate(y_adj = y), list(f = y_adj ~ bass_F(t, p, q, m),
             start = list(p = c(0.002, 0.01), q = c(0.2, 0.5), m = c(0.7, 0.95)),
             lower = c(1e-6, 1e-6, 0.3), upper = c(1, 3, 1)))
    if (is.null(f)) next
    co <- coef(f)
    bench[[length(bench) + 1]] <- tibble(country = cc, years = paste(range(windows[[cc]]), collapse = "-"),
      start_year = t0, p_annual = co["p"], q_annual = co["q"], q_over_p = co["q"] / co["p"], m = co["m"],
      peak_year = t0 + log(co["q"] / co["p"]) / (co["p"] + co["q"]),
      rmse_pp = rmse(100 * (dd$y - fitted(f))))
  }
}
bench <- bind_rows(bench)
write_csv(bench, file.path(out_dir(cfg, "tables"), "internet_benchmark.csv"))
print(bench)
