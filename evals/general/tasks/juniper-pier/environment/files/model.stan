data {
  int<lower=0> n;
  vector[n] x;              // tension (kN)
  vector[n] y;              // elongation (%)
}
parameters {
  real alpha;               // intercept
  real beta;                // slope on tension
  real<lower=0> sigma;      // residual scale
}
model {
  alpha ~ normal(0, 5);
  beta ~ normal(0, 5);
  sigma ~ cauchy(0, 2);
  y ~ normal(alpha + beta * x, sigma);
}