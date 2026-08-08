function x_next = wt_step_true(x, u, V, p, dt)
% WT_STEP_TRUE  "True" plant for the Piste B (nominal + residual
% correction) experiment. Identical to wt_step.m EXCEPT for one
% additional, DELIBERATELY UNMODELED term: a nonlinear (quadratic)
% aerodynamic/mechanical damping component that the nominal model
% (wt_step.m) does not know about.
%
%   x_next = wt_step_true(x, u, V, p, dt)
%
%   PURPOSE
%     wt_step.m is also the model that GENERATED stage1_data.mat — so
%     a residual network trained against wt_step.m's own output would
%     trivially learn to predict zero (no genuine model-plant mismatch
%     to correct). This function stands in for "the real turbine",
%     with an unmodeled nonlinearity the nominal model cannot capture,
%     so that Piste B's nominal+correction structure has a genuine
%     correction to learn — consistent with the Aswani et al. (2013)
%     "provably safe learning-based MPC" structure surveyed in the
%     literature review (nominal model + learned correction term,
%     under bounded-deviation assumptions).
%
%   UNMODELED TERM — CALIBRATION NOTE (corrected)
%     An earlier version of this file calibrated c2 relative to Br
%     (the linear damping coefficient). This was a scaling error:
%     Br*omega_r is itself only ~7900 N.m, already negligible next to
%     the dominant aerodynamic/generator torques (~1e6 N.m scale), so
%     5% of an already-negligible term produced a residual far too
%     small to be learnable or to matter for closed-loop tracking
%     (confirmed empirically: mean|residual| ~ 1e-6, effectively zero).
%     c2 is now calibrated as a fraction of the RATED LSS TORQUE
%     (N_gear*Tg_rated, ~3.95e6 N.m), which is the dominant term in the
%     torque balance -- giving a residual of comparable order to a few
%     percent of rated torque, large enough to be both learnable and
%     closed-loop-relevant, while still small enough that the nominal
%     model remains a reasonable starting point (Aswani et al. 2013's
%     bounded-deviation assumption).
%
% Chosen so that at omega = omega_rated, the unmodeled term
% c2*omega_r^2 equals ~3% of the rated LSS torque (N_gear*Tg_rated).
frac_of_rated_torque = 0.03;
c2 = frac_of_rated_torque * (p.N_gear * p.Tg_rated) / max(p.omega_r^2, 1e-6);

% ── Input guards (identical to wt_step.m) ────────────────────────────────────
omega = max(p.omega_min, x(1));
beta  = max(p.beta_cp_min, min(p.beta_cp_max, x(2)));
V     = max(0.5, V);

% ── Tip-speed ratio and aerodynamic power coefficient ───────────────────────
lambda = p.R * omega / V;
Cp = cp_lambda_beta(lambda, beta);

% ── Aerodynamic torque [N.m] ─────────────────────────────────────────────────
Ta = 0.5 * p.rho * p.A_rotor * Cp * V^3 / omega;

% ── Generator torque on low-speed shaft [N.m] — Region II/III switching ─────
if omega < p.omega_r
    Tg_lss = p.K_opt * omega^2;
else
    Tg_lss = p.N_gear * p.Tg_rated;
end

% ── Rotor angular acceleration, WITH unmodeled nonlinear damping ────────────
domega_dt = (Ta - Tg_lss - p.Br*omega - c2*omega^2*sign(omega)) / p.J;

% ── Pitch actuator (identical to wt_step.m) ──────────────────────────────────
dbeta_dt = (u - beta) / p.tau_beta;
dbeta_dt = max(-p.dbeta_max, min(p.dbeta_max, dbeta_dt));

% ── Euler forward integration ─────────────────────────────────────────────────
x_next = [omega + domega_dt * dt;
          beta  + dbeta_dt  * dt];

x_next(1) = max(p.omega_min, min(p.omega_max,    x_next(1)));
x_next(2) = max(p.beta_cp_min, min(p.beta_cp_max, x_next(2)));

end