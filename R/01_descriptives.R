# Descriptives: all series on one time axis (Figure 7.2) and the dataset composition.
# Rscript R/01_descriptives.R

source("R/functions.R")
suppressPackageStartupMessages(library(ggplot2))
cfg <- load_cfg()
inp <- read_inputs(cfg)
d <- inp$data %>% filter(series != "anchor") %>% mutate(date_mid = as.Date(date_mid))

comp <- d %>% count(country, role, series, name = "rows") %>% arrange(country, role, series)
write_csv(comp, file.path(out_dir(cfg, "tables"), "dataset_composition.csv"))
print(comp, n = Inf)

plot_d <- d %>% filter(role %in% c("estimation", "robustness", "check")) %>%
  mutate(country = factor(country, levels = countries))
g <- ggplot(plot_d, aes(date_mid, 100 * y, colour = series, shape = role)) +
  geom_linerange(aes(ymin = 100 * (y - 1.96 * se), ymax = 100 * (y + 1.96 * se)), alpha = 0.5) +
  geom_point(size = 2) +
  geom_line(data = filter(plot_d, role == "estimation"), alpha = 0.4) +
  facet_wrap(~country, ncol = 1) +
  scale_y_continuous("Share of adults (%)", limits = c(0, 80)) +
  scale_x_date(NULL, date_breaks = "6 months", date_labels = "%b %Y") +
  labs(title = "Generative AI adoption: all series used in Study 4",
       subtitle = "Points with 95% sampling intervals; lines join the estimation series") +
  theme_minimal(base_size = 11) + theme(legend.position = "bottom", legend.box = "vertical")
ggsave(file.path(out_dir(cfg, "figures"), "fig7_2_series.png"), g, width = 8, height = 8, dpi = 300)
message("Saved output/figures/fig7_2_series.png")
