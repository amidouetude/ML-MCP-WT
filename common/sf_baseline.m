function xnext = sf_baseline(x, u, V, p)
% SF_BASELINE  Linearised state function for Baseline MPC
%
%   xnext = sf_baseline(x, u, V, p)
%
%   Called by nlmpc with NumberOfParameters = 2:
%     p1 = V    hub-height wind speed [m/s]  (scalar)
%     p2 = p    turbine parameter struct from get_wt_params()
%
%   STATE   x = [omega_r (rad/s);  beta (deg)]
%   INPUT   u = [beta_cmd (deg)]
%
%   Uses the same physics as wt_step.m (Euler forward integration).
%   This is the ground-truth model used as the MPC internal model for
%   the baseline controller — no ML surrogate involved.
%
%   NOTE: p.dt must be set to MPC sample time Ts before use.
%         p_local = p; p_local.dt = cfg.mpc.Ts;

omega = max(p.omega_min, x(1));
beta  = max(p.beta_cp_min, min(p.beta_cp_max, x(2)));
V     = max(0.5, V);

lambda = p.R * omega / V;
Cp     = cp_lambda_beta(lambda, beta);
Ta     = 0.5 * p.rho * p.A_rotor * Cp * V^3 / omega;

domega_dt = (Ta - p.N_gear*p.Tg_rated - p.Br*omega) / p.J;

dbeta_dt  = (u(1) - beta) / p.tau_beta;
dbeta_dt  = max(-p.dbeta_max, min(p.dbeta_max, dbeta_dt));

xnext = [omega + domega_dt * p.dt;
         beta  + dbeta_dt  * p.dt];

xnext(1) = max(p.omega_min,   min(p.omega_max,    xnext(1)));
xnext(2) = max(p.beta_cp_min, min(p.beta_cp_max,  xnext(2)));
end
