# /app/target.R
# Target density for the benchmark: an unnormalized, log-concave probability
# density on the interval [-4, 4] (a standard Normal restricted to [-4,4]).
#
# log_fun(x)   : the log of the (unnormalized) target density. Outside the
#                support, the density is 0 so the log is -Inf.
# log_deriv(x) : the first derivative of log_fun(x).
#
# Both functions are vectorizable (they must accept a numeric vector and
# return a numeric vector of the same length).

log_fun <- function(x) {
  ifelse(abs(x) > 4, -Inf, -0.5 * x * x)
}

log_deriv <- function(x) {
  -x
}