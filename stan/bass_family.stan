// Study 4 (Chapter 7): Bass-family diffusion models with a measurement model
// for several survey series, estimated jointly for C countries with partial
// pooling of the diffusion parameters (hierarchical Bayes).
//
// Latent curve F_c(t) (share of the target population that has ever used a
// generative AI tool), t in months since 1 Dec 2022, F_c(0) = 0:
//   dF/dt = (p + q(t) F/m(t)) (m(t) - F) x(t)
// Model codes (data `model_code`):
//   0 = pure external influence (q = 0)            M0
//   1 = Bass (Bass, 1969)                          M1
//   4 = generalised Bass, x(t) = exp(shocks * beta) M4
//   5 = time-varying imitation, q(t) = q (F/m)^alpha M5
//   6 = dynamic market potential, m(t) = m * ceiling(t) M6
// The ODE is integrated on a monthly grid with K Heun (RK2) substeps per month;
// observations are read off the grid by linear interpolation.
//
// Measurement model (Section 7.3.6):
//   y_n ~ Normal(lambda_s F_c(t_n) + delta_s * post_break_n, kappa_s * se_n)

functions {
  real hazard_rate(real F, real p, real q, real m, real alpha, real x, int model_code) {
    real share = fmin(fmax(F / m, 1e-9), 1.0);
    real qt;
    if (model_code == 0) {
      qt = 0;
    } else if (model_code == 5) {
      qt = q * pow(share, alpha);
    } else {
      qt = q;
    }
    return (p + qt * share) * fmax(m - F, 0) * x;
  }

  vector bass_path(int G, int K, real p, real q, real m, real alpha, int model_code,
                   vector ceil_c, matrix shocks_c, vector beta) {
    vector[G + 1] F;
    real h = 1.0 / K;
    real Fc = 0;
    F[1] = 0;
    for (g in 1:G) {
      real mt = (model_code == 6) ? m * ceil_c[g] : m;
      real xt = 1;
      if (model_code == 4 && cols(shocks_c) > 0) {
        xt = exp(shocks_c[g] * beta);
      }
      for (k in 1:K) {
        real k1 = hazard_rate(Fc, p, q, mt, alpha, xt, model_code);
        real k2 = hazard_rate(Fc + h * k1, p, q, mt, alpha, xt, model_code);
        Fc = Fc + 0.5 * h * (k1 + k2);
      }
      F[g + 1] = Fc;
    }
    return F;
  }
}

data {
  int<lower=1> N;                              // observations
  int<lower=1> C;                              // countries
  int<lower=1> S;                              // series
  array[N] int<lower=1, upper=C> country;
  array[N] int<lower=1, upper=S> series;
  vector<lower=0>[N] t;                        // months since t0
  array[N] int<lower=0> g0;                    // floor(t)
  vector<lower=0, upper=1>[N] gw;              // t - floor(t)
  vector[N] y;                                 // estimate (proportion)
  vector<lower=0>[N] se;                       // sampling SE
  vector<lower=0, upper=1>[N] post_break;      // 1 after a documented change of method
  array[S] int<lower=0, upper=1> is_ref;       // lambda fixed at 1
  array[N] int<lower=0, upper=1> is_lb;        // 1: y is a lower bound of the latent value (censored)
  array[S] int<lower=0, upper=1> fix_kappa;    // kappa fixed at 1 (launch anchor)
  vector[S] lambda_mu;
  vector<lower=0>[S] lambda_sd;

  int<lower=1> G;                              // grid length in months
  int<lower=1> K;                              // substeps per month
  int<lower=0, upper=6> model_code;
  int<lower=0> J;                              // number of shock types
  array[C] matrix[G, J] shocks;                // shock covariates at the start of each month
  array[C] vector<lower=0, upper=1>[G] ceiling; // ceiling share for M6

  // priors
  real logp_mu;
  real<lower=0> logp_sd;
  real logq_mu;
  real<lower=0> logq_sd;
  real logitm_mu;
  real<lower=0> logitm_sd;
  real<lower=0> tau_sd;
  real logkappa_mu;
  real<lower=0> logkappa_sd;
  real<lower=0> delta_sd;

  // forecasts (f_series = 0: latent F; otherwise the series index)
  int<lower=0> NF;
  array[NF] int<lower=1, upper=C> f_country;
  array[NF] int<lower=0, upper=S> f_series;
  vector<lower=0>[NF] f_t;
  array[NF] int<lower=0> f_g0;
  vector<lower=0, upper=1>[NF] f_gw;
  vector<lower=0, upper=1>[NF] f_post_break;
  vector<lower=0>[NF] f_se;
}

transformed data {
  int has_q = (model_code == 0) ? 0 : 1;
}

parameters {
  real mu_logp;
  real<lower=0> tau_logp;
  vector[C] z_p;
  array[has_q] real mu_logq;                   // absent in M0
  array[has_q] real<lower=0> tau_logq;
  vector[has_q ? C : 0] z_q;
  real mu_logitm;
  real<lower=0> tau_logitm;
  vector[C] z_m;
  array[model_code == 5 ? 1 : 0] real<lower=0> alpha;   // M5 only
  vector[model_code == 4 ? J : 0] beta;                 // M4 only
  vector<lower=0>[S] lambda_raw;
  vector[S] delta;
  vector[S] log_kappa;
}

transformed parameters {
  vector<lower=0>[C] p = exp(mu_logp + tau_logp * z_p);
  vector<lower=0>[C] q = has_q ? exp(mu_logq[1] + tau_logq[1] * z_q) : rep_vector(0, C);
  real alpha_v = (model_code == 5) ? alpha[1] : 0;
  vector[J] beta_v = (model_code == 4) ? beta : rep_vector(0, J);
  vector<lower=0, upper=1>[C] m = inv_logit(mu_logitm + tau_logitm * z_m);
  vector[S] lambda;
  vector<lower=0>[S] kappa;
  array[C] vector[G + 1] Fg;
  vector[N] mu;
  for (s in 1:S) {
    lambda[s] = is_ref[s] ? 1.0 : lambda_raw[s];
    kappa[s] = fix_kappa[s] ? 1.0 : exp(log_kappa[s]);
  }
  for (c in 1:C) {
    Fg[c] = bass_path(G, K, p[c], q[c], m[c], alpha_v, model_code, ceiling[c], shocks[c], beta_v);
  }
  for (n in 1:N) {
    real Fn = (1 - gw[n]) * Fg[country[n]][g0[n] + 1] + gw[n] * Fg[country[n]][g0[n] + 2];
    mu[n] = lambda[series[n]] * Fn + delta[series[n]] * post_break[n];
  }
}

model {
  mu_logp ~ normal(logp_mu, logp_sd);
  mu_logq ~ normal(logq_mu, logq_sd);
  tau_logq ~ normal(0, tau_sd);
  z_q ~ std_normal();
  mu_logitm ~ normal(logitm_mu, logitm_sd);
  tau_logp ~ normal(0, tau_sd);
  tau_logitm ~ normal(0, tau_sd);
  z_p ~ std_normal();
  z_m ~ std_normal();
  alpha ~ normal(0, 1);
  beta ~ normal(0, 0.3);
  lambda_raw ~ normal(lambda_mu, lambda_sd);
  delta ~ normal(0, delta_sd);
  log_kappa ~ normal(logkappa_mu, logkappa_sd);
  {
    vector[N] sdv = kappa[series] .* se;
    for (n in 1:N) {
      if (is_lb[n] == 1) {
        target += normal_lccdf(y[n] | mu[n], sdv[n]);   // latent value at least y (Table 7.8, discontinuance check)
      } else {
        target += normal_lpdf(y[n] | mu[n], sdv[n]);
      }
    }
  }
}

generated quantities {
  vector[N] log_lik;
  vector[N] y_rep;
  vector[C] p_annual = 12 * p;
  vector[C] q_annual = 12 * q;
  vector[C] t_peak;                            // months; classic Bass only
  vector[NF] F_fore;
  vector[NF] y_fore;
  for (n in 1:N) {
    real sd_n = kappa[series[n]] * se[n];
    log_lik[n] = is_lb[n] == 1 ? normal_lccdf(y[n] | mu[n], sd_n) : normal_lpdf(y[n] | mu[n], sd_n);
    y_rep[n] = normal_rng(mu[n], sd_n);
  }
  for (c in 1:C) {
    t_peak[c] = (model_code == 1 && q[c] > p[c]) ? log(q[c] / p[c]) / (p[c] + q[c]) : not_a_number();
  }
  for (f in 1:NF) {
    real Ff = (1 - f_gw[f]) * Fg[f_country[f]][f_g0[f] + 1] + f_gw[f] * Fg[f_country[f]][f_g0[f] + 2];
    F_fore[f] = Ff;
    if (f_series[f] == 0) {
      y_fore[f] = Ff;
    } else {
      y_fore[f] = normal_rng(lambda[f_series[f]] * Ff + delta[f_series[f]] * f_post_break[f],
                             kappa[f_series[f]] * f_se[f]);
    }
  }
}
