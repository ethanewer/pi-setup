data {
  int<lower=1> N;
  int<lower=1> G;
  int<lower=1, upper=G> g[N];
  vector[N] x;
  vector[N] y;
}
transformed data {
  real<lower=0> delta;
  delta = 1e-9;     // jitter for GP covariance cholesky stability
}
parameters {
  real<lower=0> rho;
  real<lower=0> alpha;
  real<lower=0> sigma;
  real b0;
  real<lower=0> tau;
  vector[G] b_g;
  vector[N] eta;
}
transformed parameters {
  matrix[N, N] K;
  vector[N] mu;
  for (i in 1:N)
    for (j in 1:N)
      K[i, j] = alpha * alpha * exp(-0.5 * square((x[i] - x[j]) / rho))
                + (i == j ? delta : 0.0);
  mu = b_g[g] + eta;
}
model {
  rho ~ inv_gamma(5, 5);
  alpha ~ normal(0, 1);
  sigma ~ normal(0, 1);
  tau ~ normal(0, 0.5);
  b0 ~ normal(0, 1);
  b_g ~ normal(b0, tau);
  eta ~ multi_normal(rep_vector(0, N), K);
  y ~ normal(mu, sigma);
}
generated quantities {
  vector[N] y_rep;
  for (i in 1:N)
    y_rep[i] = normal_rng(mu[i], sigma);
}