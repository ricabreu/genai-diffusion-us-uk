# One-off setup: R packages and CmdStan.
# Run once:  Rscript R/00_setup.R

pkgs <- c("yaml", "readr", "dplyr", "tidyr", "purrr", "ggplot2", "minpack.lm",
          "posterior", "loo", "jsonlite")
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing)) install.packages(missing, repos = "https://cloud.r-project.org")

if (!requireNamespace("cmdstanr", quietly = TRUE)) {
  install.packages("cmdstanr", repos = c("https://stan-dev.r-universe.dev", "https://cloud.r-project.org"))
}
cmdstanr::check_cmdstan_toolchain(fix = TRUE)
if (is.null(tryCatch(cmdstanr::cmdstan_path(), error = function(e) NULL))) {
  cmdstanr::install_cmdstan(cores = max(1, parallel::detectCores() - 1))
}
cat("CmdStan:", cmdstanr::cmdstan_version(), "\n")
writeLines(capture.output(sessionInfo()), "output/sessionInfo.txt")
