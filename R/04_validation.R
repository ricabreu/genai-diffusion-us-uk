# Rolling-origin out-of-sample evaluation (Section 7.4.3; Tashman, 2000).
# For each origin, every model is re-estimated with the observations available
# at that date and used to forecast the estimation-set observations of the
# following `horizon_months`. Accuracy: MAE and RMSE (percentage points) and
# MASE against a naive linear extrapolation of the last two observations of the
# same series (Hyndman & Koehler, 2006).
# Rscript R/04_validation.R            (all models)
# Rscript R/04_validation.R 0 1        (selected model codes)

source("R/functions.R")
cfg <- load_cfg()
inp <- read_inputs(cfg)
args <- commandArgs(trailingOnly = TRUE)
codes <- if (length(args)) as.integer(args) else
  c(unlist(cfg$estimation$models$bass_family), unlist(cfg$estimation$models$sigmoid_family))
vc <- cfg$validation
rows_all <- primary_rows(inp$data) %>% mutate(date_mid = as.Date(date_mid))

naive_forecast <- function(train, test) {
  map_dbl(seq_len(nrow(test)), function(i) {
    h <- train %>% filter(series == test$series[i], country == test$country[i]) %>% arrange(t)
    if (nrow(h) == 0) return(NA_real_)
    if (nrow(h) == 1) return(h$y[1])
    k <- nrow(h)
    h$y[k] + (h$y[k] - h$y[k - 1]) / (h$t[k] - h$t[k - 1]) * (test$t[i] - h$t[k])
  })
}

errs <- list()
origins <- as.Date(unlist(vc$origins))
# checkpoint: one file per origin and model, so an interrupted run can resume (STUDY4_RESUME=1)
ckpt <- out_dir(cfg, "checkpoints", "validation")
resume <- Sys.getenv("STUDY4_RESUME") == "1"
if (!resume) unlink(list.files(ckpt, full.names = TRUE))
for (k in seq_along(origins)) {
  origin <- origins[k]
  train <- rows_all %>% filter(date_mid <= origin)
  test  <- rows_all %>% filter(date_mid > origin, date_mid <= origin + round(vc$horizon_months * 30.44),
                               series != "anchor", series %in% train$series)
  if (nrow(test) == 0) next
  fore <- test %>% transmute(id = obs_id, country, series, date = as.character(date_mid), t)
  naive <- naive_forecast(train, test)
  for (code in codes) {
    f_ck <- file.path(ckpt, sprintf("%s_model%d.csv", format(origin), code))
    if (resume && file.exists(f_ck)) { errs[[length(errs) + 1]] <- read_csv(f_ck, show_col_types = FALSE); next }
    sd <- make_stan_data(train, inp$series, cfg, code, inp, fore = fore)
    fit <- tryCatch(fit_stan(sd, cfg, chains = vc$chains, iter_warmup = vc$iter_warmup,
                             iter_sampling = vc$iter_sampling), error = function(e) NULL)
    if (is.null(fit)) { warning("Fit failed: origin ", origin, " ", model_label(code)); next }
    # point forecast of the observation: posterior mean of lambda * F + delta (no noise)
    yf <- colMeans(fit$draws("y_fore", format = "matrix"))
    errs[[length(errs) + 1]] <- tibble(origin = origin, model = model_label(code), obs_id = test$obs_id,
      country = test$country, series = test$series, date = test$date_mid, post_break = test$post_break,
      horizon_months = round(test$t - months_since(origin, cfg), 1),
      y = test$y, forecast = yf, error_pp = 100 * (yf - test$y),
      naive_error_pp = 100 * (naive - test$y))
    write_csv(errs[[length(errs)]], f_ck)
    message(sprintf("origin %s  %-22s  MAE %.2f pp", format(origin), model_label(code), mae(100 * (yf - test$y))))
  }
}

errs <- bind_rows(errs)
tabs <- out_dir(cfg, "tables")
write_csv(errs, file.path(tabs, "rolling_origin_errors.csv"))
# Observations after a change of method that the training data could not have
# seen (e.g. Ofcom 2025 forecast from data before the change) are reported
# separately: their error mixes the model's error with the unforeseen level shift.
summ_acc <- function(e) e %>% group_by(model) %>%
  summarise(n_forecasts = n(), MAE_pp = mae(error_pp), RMSE_pp = rmse(error_pp),
            MASE = mean(abs(error_pp)) / mean(abs(naive_error_pp), na.rm = TRUE), .groups = "drop") %>%
  arrange(MAE_pp)
acc <- bind_rows(summ_acc(errs) %>% mutate(set = "all", .before = 1),
                 summ_acc(filter(errs, post_break == 0)) %>% mutate(set = "excluding post-break observations", .before = 1))
acc_country <- errs %>% group_by(model, country) %>%
  summarise(n_forecasts = n(), MAE_pp = mae(error_pp), RMSE_pp = rmse(error_pp), .groups = "drop")
write_csv(acc, file.path(tabs, "rolling_origin_accuracy.csv"))
write_csv(acc_country, file.path(tabs, "rolling_origin_accuracy_by_country.csv"))
print(acc)
