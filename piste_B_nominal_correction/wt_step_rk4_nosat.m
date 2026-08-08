function x_next = wt_step_rk4_nosat(x, u, V, p, dt)
% WT_STEP_RK4_NOSAT  RK4 integration variant with a SINGLE, post-hoc
% pitch-rate saturation applied once per full step (matching Euler's
% semantics in wt_step.m), rather than 4 times per substage as in
% wt_step_rk4.m.
%
%   x_next = wt_step_rk4_nosat(x, u, V, p, dt)
%
%   PURPOSE — isolates the cause of the pitch-activity discrepancy
%   found by run_sensitivity_rk4.m: RK4 (substage-saturated) showed
%   372.5 -> 172.0 deg cumulative pitch activity vs Euler, a 54%
%   reduction, despite near-identical RMSE (0.19% difference). The
%   hypothesis is that saturating the pitch RATE at each of RK4's four
%   internal stages effectively smooths/limits pitch movement more
%   than intended, relative to Euler's single per-step saturation. This
%   function tests that hypothesis directly by using an UNSATURATED
%   pitch-rate derivative inside the RK4 stages, then applying ONE
%   equivalent saturation to the resulting step-level pitch change --
%   the same semantic as Euler's single clamp.
%
%   If THIS variant's pitch activity matches Euler's closely (unlike
%   wt_step_rk4.m's 172.0 deg), the substage-saturation hypothesis is
%   confirmed as the cause. If it does not, some other RK4-specific
%   effect is responsible and the hypothesis is rejected.

f = @(xx) rotor_ode_rhs_unsaturated_pitch(xx, u, V, p);

k1 = f(x);
k2 = f(x + dt/2 * k1);
k3 = f(x + dt/2 * k2);
k4 = f(x + dt   * k3);

x_next_raw = x + (dt/6) * (k1 + 2*k2 + 2*k3 + k4);

% ── Single, post-hoc pitch-rate saturation over the FULL step ──────────────
%    (equivalent semantics to Euler's one clamp per step)
d_omega = x_next_raw(1) - x(1);   % unaffected by pitch saturation choice
d_beta_raw = x_next_raw(2) - x(2);
max_d_beta = p.dbeta_max * dt;
d_beta_clamped = max(-max_d_beta, min(max_d_beta, d_beta_raw));

x_next = [x(1) + d_omega; x(2) + d_beta_clamped];

x_next(1) = max(p.omega_min, min(p.omega_max,    x_next(1)));
x_next(2) = max(p.beta_cp_min, min(p.beta_cp_max, x_next(2)));

end


function dxdt = rotor_ode_rhs_unsaturated_pitch(x, u, V, p)
% Identical to wt_step_rk4.m's rotor_ode_rhs(), EXCEPT the pitch-rate
% derivative is NOT saturated here (saturation is applied once, post-hoc,
% to the combined step in wt_step_rk4_nosat() above).

omega = max(p.omega_min, x(1));
beta  = max(p.beta_cp_min, min(p.beta_cp_max, x(2)));
V     = max(0.5, V);

lambda = p.R * omega / V;
Cp = cp_lambda_beta(lambda, beta);
Ta = 0.5 * p.rho * p.A_rotor * Cp * V^3 / omega;

if omega < p.omega_r
    Tg_lss = p.K_opt * omega^2;
else
    Tg_lss = p.N_gear * p.Tg_rated;
end

domega_dt = (Ta - Tg_lss - p.Br*omega) / p.J;
dbeta_dt  = (u - beta) / p.tau_beta;   % UNSATURATED here, by design

dxdt = [domega_dt; dbeta_dt];

end
