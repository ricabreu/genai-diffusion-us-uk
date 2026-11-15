// Study 4 (Chapter 7): logistic (M2) and Gompertz (M3) adoption curves with
// the same measurement model and partial pooling as bass_family.stan.
//   M2 logistic:  F(t) = m / (1 + exp(-r (t - b)))   (r = rate, b = midpoint, months)
//   M3 Gompertz:  F(t) = m exp(-b exp(-r t))          (r = rate, b = displacement)
// Both are evaluated in closed form at the observation times. The launch
// condition enters as an observation (series "anchor"), as in the Bass family.
// Data names match bass_family.stan; unused entries are ignored.

functions {
  real sig_F(real t, real r, real b, real m, int model_code) {
    if (model_code == 2) {
      return m * inv_logit(r * (t - b));
    }
    return m * exp(-b * exp(-r * t));
  }
}

data {
  int<lower=1> N;
  int<lower=1> C;
  int<lower=1> S;
  array[N] int<lower=1, upper=C> country;
  array[N] int<lower=1, upper=S> series;
  vector<lower=0>[N] t;
  vector[N] y;
  vector<lower=0>[N] se;
  vector<lower=0, upper=1>[N] post_break;
  array[S] int<lower=0, upper=1> is_ref;
  array[S] int<lower=0, upper=1> fix_kappa;
  vector[S] lambda_mu;
  vector<lower=0>[S] lambda_sd;
  int<lower=2, upper=3> model_code;

  real logitm_mu;
  real<lower=0> logitm_sd;
  real<lower=0> tau_sd;
  real logkappa_mu;
  real<lower=0> logkappa_sd;
  real<lower=0> delta_sd;

  int<lower=0> NF;
  array[NF] int<lower=1, upper=C> f_country;
  array[NF] int<lower=0, upper=S> f_series;
  vector<lower=0>[NF] f_t;
  vector<lower=0, upper=1>[NF] f_post_break;
  vector<lower=0>[NF] f_se;
}

transformed data {
  // logistic: midpoint b in months; Gompertz: log displacement
  real loc_mu = (model_code == 2) ? 24 : log(3);
  real loc_sd = (model_code == 2) ? 18 : 1;
  real loc_tau_sd = (model_code == 2) ? 6 : 0.5;
}

parameters {
  real mu_logr;
  real<lower=0> tau_logr;
  vector[C] z_r;
  real mu_loc;
  real<lower=0> tau_loc;
  vector[C] z_l;
  real mu_logitm;
  real<lower=0> tau_logitm;
  vector[C] z_m;
  vector<lower=0>[S] lambda_raw;
  vector[S] delta;
  vector[S] log_kappa;
}

transformed parameters {
  vector<lower=0>[C] r = exp(mu_logr + tau_logr * z_r);
  vector[C] loc = mu_loc + tau_loc * z_l;
  vector<lower=0, upper=1>[C] m = inv_logit(mu_logitm + tau_logitm * z_m);
  vector[C] b;
  vector[S] lambda;
  vector<lower=0>[S] kappa;
  vector[N] mu;
  for (c in 1:C) {
    b[c] = (model_code == 2) ? loc[c] : exp(loc[c]);
  }
  for (s in 1:S) {
    lambda[s] = is_ref[s] ? 1.0 : lambda_raw[s];
    kappa[s] = fix_kappa[s] ? 1.0 : exp(log_kappa[s]);
  }
  for (n in 1:N) {
    mu[n] = lambda[series[n]] * sig_F(t[n], r[country[n]], b[country[n]], m[country[n]], model_code)
            + delta[series[n]] * post_break[n];
  }
}

model {
  mu_logr ~ normal(log(0.1), 1);
  tau_logr ~ normal(0, tau_sd);
  z_r ~ std_normal();
  mu_loc ~ normal(loc_mu, loc_sd);
  tau_loc ~ normal(0, loc_tau_sd);
  z_l ~ std_normal();
  mu_logitm ~ normal(logitm_mu, logitm_sd);
  tau_logitm ~ normal(0, tau_sd);
  z_m ~ std_normal();
  lambda_raw ~ normal(lambda_mu, lambda_sd);
  delta ~ normal(0, delta_sd);
  log_kappa ~ normal(logkappa_mu, logkappa_sd);
  y ~ normal(mu, kappa[series] .* se);
}

generated quantities {
  vector[N] log_lik;
  vector[N] y_rep;
  vector[NF] F_fore;
  vector[NF] y_fore;
  for (n in 1:N) {
    real sd_n = kappa[series[n]] * se[n];
    log_lik[n] = normal_lpdf(y[n] | mu[n], sd_n);
    y_rep[n] = normal_rng(mu[n], sd_n);
  }
  for (f in 1:NF) {
    real Ff = sig_F(f_t[f], r[f_country[f]], b[f_country[f]], m[f_country[f]], model_code);
    F_fore[f] = Ff;
    if (f_series[f] == 0) {
      y_fore[f] = Ff;
    } else {
      y_fore[f] = normal_rng(lambda[f_series[f]] * Ff + delta[f_series[f]] * f_post_break[f],
                             kappa[f_series[f]] * f_se[f]);
    }
  }
}
