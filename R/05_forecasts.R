# Prospective forecasts (Section 7.4.3): forecasts for releases published after
# the data freeze, recorded with a date stamp and a checksum BEFORE the releases
# appear. Commit the output file to the repository (the commit is the time stamp).
# Rscript R/05_forecasts.R

source("R/functions.R")
cfg <- load_cfg()
inp <- read_inputs(cfg)
codes <- c(unlist(cfg$estimation$models$bass_family), unlist(cfg$estimation$models$sigmoid_family))
rows <- primary_rows(inp$data)
fore <- forecast_frame(cfg)

out <- list()
for (code in codes) {
  f_rds <- file.path(cfg$paths$output, "fits", sprintf("primary_model%d.rds", code))
  sd <- make_stan_data(rows, inp$series, cfg, code, inp, fore = fore)
  fit <- if (file.exists(f_rds)) readRDS(f_rds) else fit_stan(sd, cfg)
  out[[length(out) + 1]] <- forecast_draws(fit, sd) %>% mutate(model = model_label(code), .before = 1)
}
fc <- bind_rows(out) %>%
  mutate(across(c(mean, lo95, lo80, hi80, hi95, latent_F_mean), ~ round(100 * .x, 2)),
         freeze_date = cfg$project$freeze_date, recorded_on = as.character(Sys.Date()))

d <- out_dir(cfg, "forecasts")
f <- file.path(d, sprintf("forecasts_registered_%s_recorded_%s.csv", cfg$project$freeze_date, Sys.Date()))
write_csv(fc, f)
md5 <- unname(tools::md5sum(f))
writeLines(md5, paste0(f, ".md5"))
message("Recorded ", f, "\nMD5 ", md5, "\nCommit both files now; the commit date is the registration date.")
print(fc, n = Inf, width = Inf)
