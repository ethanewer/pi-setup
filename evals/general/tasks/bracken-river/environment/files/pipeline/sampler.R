#!/usr/bin/env Rscript
# Osprey Ridge flow sampler stage.
# usage: Rscript --vanilla sampler.R <params-file> <output-file>
#
# Params file: key=value lines (seed, n, mu, sigma). Blank lines and lines
# starting with '#' are ignored.
# Draws set.seed(seed); x <- mu + sigma * rnorm(n) and writes
# mean/sd/median/min/max formatted with six decimals.

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2) {
  cat("usage: sampler.R <params-file> <output-file>\n", file = stderr())
  quit(status = 2)
}
params_file <- args[1]
out_file <- args[2]

kv <- list()
for (line in readLines(params_file)) {
  trimmed <- gsub("^[[:space:]]+|[[:space:]]+$", "", line)
  if (nchar(trimmed) == 0 || substr(trimmed, 1, 1) == "#") next
  parts <- strsplit(trimmed, "=", fixed = TRUE)[[1]]
  if (length(parts) != 2) next
  key <- gsub("^[[:space:]]+|[[:space:]]+$", "", parts[1])
  val <- gsub("^[[:space:]]+|[[:space:]]+$", "", parts[2])
  kv[[key]] <- val
}

needed <- c("seed", "n", "mu", "sigma")
if (any(!needed %in% names(kv))) {
  cat("sampler.R: missing params\n", file = stderr())
  quit(status = 2)
}

seed <- as.integer(kv$seed)
n <- as.integer(kv$n)
mu <- as.numeric(kv$mu)
sigma <- as.numeric(kv$sigma)

set.seed(seed)
x <- mu + sigma * rnorm(n)

fmt <- function(v) sprintf("%.6f", v)
writeLines(
  c(
    paste0("mean=", fmt(mean(x))),
    paste0("sd=", fmt(sd(x))),
    paste0("median=", fmt(median(x))),
    paste0("min=", fmt(min(x))),
    paste0("max=", fmt(max(x)))
  ),
  out_file
)
