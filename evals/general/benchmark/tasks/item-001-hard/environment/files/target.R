# /app/target.R
# Two unnormalized, log-concave target densities used by this benchmark.
# Each target is described by a log density, its derivative, and support
# bounds. All log_* functions are vectorizable.

# ---- Target T1: standard Normal restricted to [-4, 4] ----
log_fun1  <- function(x) ifelse(abs(x) > 4, -Inf, -0.5 * x * x)
log_deriv1 <- function(x) -x
LO1 <- -4
HI1 <-  4

# ---- Target T2: Laplace (location 0, scale b = 0.8) restricted to [-6, 6] ----
log_fun2 <- function(x) {
  ifelse(abs(x) > 6, -Inf, -abs(x) / 0.8 - log(1.6))
}
log_deriv2 <- function(x) {
  ifelse(x < 0, 1 / 0.8, ifelse(x > 0, -1 / 0.8, 0))
}
LO2 <- -6
HI2 <-  6