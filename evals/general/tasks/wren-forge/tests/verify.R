#!/usr/bin/env Rscript
# verify.R for wren-forge — called by tests/test.sh. Exits 0 iff all checks
# pass. Prints "verify failures: ..." at the end. Guards every parse.
suppressMessages(library(rstan))
suppressMessages(library(jsonlite))

failures <- character(0)
add_failure <- function(msg) failures <<- c(failures, msg)

norm_flat <- function(lines) gsub("[[:space:]]+", "", paste(lines, collapse = ""))

# ---- 1. Stan source contract (deliverable /app/hier_model.stan) -------------
src_lines <- tryCatch(readLines("/app/hier_model.stan", warn = FALSE),
                      error = function(e) NULL)
if (is.null(src_lines) || length(src_lines) == 0) {
  add_failure("hier_model.stan unreadable or empty")
} else {
  flat <- norm_flat(src_lines)
  hyper <- "-0.5*log(alpha)-0.5*log(beta)-0.5*log(alpha+beta)"
  if (!grepl("target+=", flat, fixed = TRUE))
    add_failure("stan source has no target += hyper-prior term")
  if (!grepl(hyper, flat, fixed = TRUE))
    add_failure("stan source is missing the exact Jeffreys-type hyper-prior term")
  if (!grepl("theta~beta(alpha,beta);", flat, fixed = TRUE))
    add_failure("stan source is missing the shared beta group prior")
  if (!grepl("k~binomial(n,theta);", flat, fixed = TRUE))
    add_failure("stan source is missing the per-group binomial likelihood")
}

# ---- helpers ----------------------------------------------------------------
run_fit <- function(csv, outdir) {
  out <- suppressWarnings(system2("Rscript", c("/app/fit.R", csv, outdir),
                                  stdout = TRUE, stderr = TRUE))
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  list(status = status, log = paste(out, collapse = "\n"))
}

read_csv_trials <- function(path) {
  d <- tryCatch(read.csv(path, stringsAsFactors = FALSE, colClasses = "character"),
                error = function(e) NULL)
  if (is.null(d) || !identical(names(d), c("batch", "trials", "germinated"))) return(NULL)
  trials <- suppressWarnings(as.integer(d$trials))
  germ <- suppressWarnings(as.integer(d$germinated))
  if (any(is.na(trials)) || any(is.na(germ))) return(NULL)
  list(d = d, trials = trials, germ = germ)
}

check_summary_vs_rates <- function(path, tbl, label, tol_abs = 0.08) {
  s <- tryCatch(fromJSON(path, simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(s) || is.null(s$theta_mean) || length(s$theta_mean) != nrow(tbl$d)) {
    add_failure(sprintf("%s: summary.json missing/invalid theta_mean", label))
    return(invisible(NULL))
  }
  for (g in seq_len(nrow(tbl$d))) {
    p <- tbl$germ[g] / tbl$trials[g]
    se <- sqrt(p * (1 - p) / tbl$trials[g])
    tol <- max(tol_abs, 4 * se)
    if (abs(s$theta_mean[g] - p) > tol)
      add_failure(sprintf("%s: theta_mean[%d]=%.4f too far from empirical rate %.4f",
                          label, g, s$theta_mean[g], p))
  }
  if (!is.finite(s$alpha_mean) || s$alpha_mean <= 0 ||
      !is.finite(s$beta_mean) || s$beta_mean <= 0)
    add_failure(sprintf("%s: alpha_mean/beta_mean not strictly positive", label))
  invisible(s)
}

# ---- 2. Re-run the driver on the visible data -------------------------------
vis_dir <- "/tmp/wf_vis"
unlink(vis_dir, recursive = TRUE)
vis_run <- tryCatch(run_fit("/app/trials.csv", vis_dir), error = function(e) NULL)
if (is.null(vis_run) || vis_run$status != 0) {
  add_failure(sprintf("fit.R failed on visible data: %s",
                      if (!is.null(vis_run)) vis_run$log else "crashed"))
} else {
  # the run must reproduce the exact Stan program
  a <- tryCatch(readLines("/app/hier_model.stan", warn = FALSE), error = function(e) NULL)
  b <- tryCatch(readLines(file.path(vis_dir, "hier_model.stan"), warn = FALSE),
                error = function(e) NULL)
  if (is.null(a) || is.null(b) || !identical(a, b))
    add_failure("fit.R did not reproduce hier_model.stan byte-identically")

  # deliverable summary must match a fresh regeneration (within tolerance)
  s_app <- tryCatch(fromJSON("/app/summary.json", simplifyVector = TRUE),
                    error = function(e) NULL)
  s_new <- tryCatch(fromJSON(file.path(vis_dir, "summary.json"),
                             simplifyVector = TRUE), error = function(e) NULL)
  if (is.null(s_app) || is.null(s_new)) {
    add_failure("summary.json unreadable (deliverable or regenerated)")
  } else {
    need <- c("groups", "batch_ids", "theta_mean", "alpha_mean", "beta_mean",
              "n_draws", "seed")
    if (!all(need %in% names(s_app)))
      add_failure("deliverable summary.json missing required keys")
    else {
      if (s_app$groups != s_new$groups)
        add_failure("deliverable summary groups mismatch")
      if (!identical(as.character(s_app$batch_ids), as.character(s_new$batch_ids)))
        add_failure("deliverable summary batch_ids mismatch")
      if (s_app$n_draws != s_new$n_draws || s_app$seed != s_new$seed)
        add_failure("deliverable summary n_draws/seed mismatch")
      if (max(abs(s_app$theta_mean - s_new$theta_mean)) > 0.02 ||
          abs(s_app$alpha_mean - s_new$alpha_mean) > 0.5 ||
          abs(s_app$beta_mean - s_new$beta_mean) > 0.5)
        add_failure("deliverable summary means do not match regeneration")
    }
  }

  # posterior.csv schema
  for (pp in c("/app/posterior.csv", file.path(vis_dir, "posterior.csv"))) {
    hdr <- tryCatch(readLines(pp, n = 1, warn = FALSE), error = function(e) NULL)
    if (is.null(hdr)) { add_failure(sprintf("%s unreadable", pp)); next }
    g <- length(suppressWarnings(read.csv("/app/trials.csv")$batch))
    want <- paste(c(paste0("theta", seq_len(g)), "alpha", "beta"), collapse = ",")
    if (gsub("[[:space:]]", "", hdr) != want)
      add_failure(sprintf("%s header %r != %s", pp, hdr, want))
    body <- tryCatch(read.csv(pp), error = function(e) NULL)
    if (is.null(body) || nrow(body) < 1000)
      add_failure(sprintf("%s has too few posterior draws", pp))
  }

  # visible rates sanity via the regenerated summary
  tbl_vis <- read_csv_trials("/app/trials.csv")
  if (!is.null(tbl_vis))
    check_summary_vs_rates(file.path(vis_dir, "summary.json"), tbl_vis, "visible")
}

# ---- 3. Independent compile + sampling of the deliverable Stan program ------
if (length(src_lines) > 0) {
  sm <- tryCatch(stan_model(model_code = paste(src_lines, collapse = "\n")),
                 error = function(e) {
                   add_failure("deliverable hier_model.stan failed to compile")
                   NULL
                 })
  if (!is.null(sm)) {
    for (case in list(
        list(label = "visible", csv = "/app/trials.csv"),
        list(label = "hid-g4", csv = "/tests/hidden/hid-g4/trials.csv"),
        list(label = "hid-g7", csv = "/tests/hidden/hid-g7/trials.csv"))) {
      tbl <- read_csv_trials(case$csv)
      if (is.null(tbl)) { add_failure(sprintf("%s: hidden csv unreadable", case$label)); next }
      fit <- tryCatch(sampling(sm, data = list(G = nrow(tbl$d), n = tbl$trials,
                                               k = tbl$germ),
                               chains = 2, warmup = 300, iter = 700,
                               seed = 20240607L, refresh = 0),
                      error = function(e) NULL)
      if (is.null(fit)) { add_failure(sprintf("%s: sampling failed", case$label)); next }
      dr <- tryCatch(extract(fit, pars = c("theta", "alpha", "beta")),
                     error = function(e) NULL)
      if (is.null(dr)) { add_failure(sprintf("%s: no posterior draws", case$label)); next }
      for (g in seq_len(nrow(tbl$d))) {
        p <- tbl$germ[g] / tbl$trials[g]
        tol <- max(0.08, 4 * sqrt(p * (1 - p) / tbl$trials[g]))
        if (abs(mean(dr$theta[, g]) - p) > tol)
          add_failure(sprintf("%s: independent posterior theta[%d] %.4f far from rate %.4f",
                              case$label, g, mean(dr$theta[, g]), p))
      }
      if (mean(dr$alpha) <= 0 || mean(dr$beta) <= 0)
        add_failure(sprintf("%s: hyperparameters not positive", case$label))
    }
  }
}

# ---- 4. Driver generalization on hidden tables + invalid-input handling -----
for (case in list(
    list(label = "hid-g4", csv = "/tests/hidden/hid-g4/trials.csv"),
    list(label = "hid-g7", csv = "/tests/hidden/hid-g7/trials.csv"))) {
  outdir <- file.path("/tmp", paste0("wf_", case$label))
  unlink(outdir, recursive = TRUE)
  r <- tryCatch(run_fit(case$csv, outdir), error = function(e) NULL)
  if (is.null(r) || r$status != 0) {
    add_failure(sprintf("%s: fit.R failed: %s", case$label,
                        if (!is.null(r)) r$log else "crashed"))
    next
  }
  tbl <- read_csv_trials(case$csv)
  if (!is.null(tbl))
    check_summary_vs_rates(file.path(outdir, "summary.json"), tbl, case$label)
  hh <- tryCatch(readLines(file.path(outdir, "hier_model.stan"), n = 1, warn = FALSE),
                 error = function(e) NULL)
  if (is.null(hh)) add_failure(sprintf("%s: run did not write hier_model.stan", case$label))
}

bad <- file.path("/tmp", "wf_bad.csv")
writeLines(c("batch,trials,germinated", "X1,100,50", "X2,80,200"), bad)
r <- tryCatch(run_fit(bad, "/tmp/wf_bad_out"), error = function(e) NULL)
if (!is.null(r) && r$status == 0)
  add_failure("fit.R accepted an invalid trial table (germinated > trials) with exit 0")

cat("verify failures:", if (length(failures)) failures else "none", "\n")
if (length(failures)) quit(status = 1) else quit(status = 0)
