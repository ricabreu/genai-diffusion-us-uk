# How the estimates move as data accumulate (Sections 7.5.4 and 7.5.5, P6):
# M1 and M4 re-estimated at each rolling origin, with the settings of the
# validation, and compared with the fit on all data at the freeze.
# Rscript R/08_parameters_by_origin.R          (M1 and M4)
# Rscript R/08_parameters_by_origin.R 1 0      (selected model codes)
# Rscript R/08_parameters_by_origin.R plot     (redraw Figure 7.4 from the saved table)

source("R/functions.R")
cfg <- load_cfg()
inp <- read_inputs(cfg)
suppressPackageStartupMessages(library(ggplot2))
args <- commandArgs(trailingOnly = TRUE)
plot_only <- identical(args, "plot")
codes <- if (length(args) && !plot_only) as.integer(args) else c(1L, 4L)
vc <- cfg$validation
rows_all <- primary_rows(inp$data) %>% mutate(date_mid = as.Date(date_mid))
fore <- forecast_frame(cfg)   # all targets, so that saved full-run fits line up
origins <- c(as.Date(unlist(vc$origins)), as.Date(cfg$project$freeze_date))

out <- list()
for (k in seq_along(origins)[!plot_only]) {
  origin <- origins[k]
  train <- rows_all %>% filter(date_mid <= origin)
  for (code in codes) {
    sd <- make_stan_data(train, inp$series, cfg, code, inp, fore = fore)
    f_rds <- file.path(cfg$paths$output, "fits", sprintf("primary_model%d.rds", code))
    at_freeze <- k == length(origins)
    fit <- if (at_freeze && file.exists(f_rds)) readRDS(f_rds) else
      fit_stan(sd, cfg, chains = vc$chains, iter_warmup = vc$iter_warmup, iter_sampling = vc$iter_sampling)
    pr <- tidy_params(fit, sd, code) %>% filter(grepl("^(p_annual|q_annual|m)\\[", variable))
    fc <- forecast_draws(fit, sd) %>% filter(grepl("^F_", id))
    out[[length(out) + 1]] <- bind_rows(
      pr %>% transmute(origin = origin, model = model_label(code), quantity = label, mean, lo = `5%`, hi = `95%`),
      fc %>% transmute(origin = origin, model = model_label(code), quantity = id, mean, lo = lo80, hi = hi80)) %>%
      mutate(n_obs = sum(train$series != "anchor"), fit = ifelse(at_freeze, "full run (4 chains x 2000)", "validation settings"))
    message(sprintf("origin %s  %s done", format(origin), model_label(code)))
  }
}
f_out <- file.path(out_dir(cfg, "tables"), "parameters_by_origin.csv")
if (plot_only) res <- read_csv(f_out, show_col_types = FALSE) else { res <- bind_rows(out); write_csv(res, f_out) }

# Figure 7.4: market potential estimated at each origin
pal <- c("M1 Bass" = "#eb6834", "M4 generalised Bass" = "#e87ba4")   # same colours as Figure 7.5
fd <- res %>% filter(grepl("^m (US|UK)$", quantity)) %>%
  mutate(country = factor(sub("^m ", "", quantity), levels = countries), origin = as.Date(origin),
         x = origin + ifelse(model == "M1 Bass", -6, 6))
g5 <- ggplot(fd, aes(x, 100 * mean, colour = model, shape = model)) +
  geom_linerange(aes(ymin = 100 * lo, ymax = 100 * hi), linewidth = 0.5) +
  geom_line(linewidth = 0.4, alpha = 0.6) + geom_point(size = 2.4) +
  facet_wrap(~country, ncol = 2) +
  scale_colour_manual(NULL, values = pal) + scale_shape_manual(NULL, values = c(16, 17)) +
  scale_y_continuous("Market potential m (% of working-age adults)", limits = c(30, 100), expand = c(0, 0)) +
  scale_x_date("Data available up to", date_breaks = "6 months", date_labels = "%b %Y") +
  labs(title = "Estimates of the market potential rose as data accumulated",
       subtitle = "Posterior mean and 90% interval of m, re-estimated with the data available at each origin; last point = data freeze") +
  theme_minimal(base_size = 10) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = "#e6e5e0"),
        plot.title = element_text(colour = "#3d3d3a", face = "bold"), plot.subtitle = element_text(colour = "#73726c"))
ggsave(file.path(out_dir(cfg, "figures"), "fig7_4_m_by_origin.png"), g5, width = 8, height = 4.5, dpi = 300)
print(res %>% filter(grepl("^m |F_.*2030", quantity)), n = Inf)
