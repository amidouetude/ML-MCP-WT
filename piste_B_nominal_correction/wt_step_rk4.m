function x_next = wt_step_rk4(x, u, V, p, dt)
% WT_STEP_RK4  Classical 4th-order Runge-Kutta integration of the SAME
% continuous-time plant dynamics as wt_step.m (explicit Euler), for the
% Euler-vs-RK4 sensitivity check requested in the reproducibility
% review (P1.2).
%
%   x_next = wt_step_rk4(x, u, V, p, dt)
%
%   PURPOSE
%     wt_step.m integrates the rotor/pitch ODEs with a single explicit
%     Euler step per call (dt=0.1s). This function integrates the exact
%     same continuous-time right-hand side with classical RK4, to test
%     whether the reported closed-loop results are sensitive to the
%     choice of numerical integration scheme, or whether Euler's local
%     truncation error at this dt is negligible for this plant.
%
%   USAGE IN THIS SENSITIVITY TEST
%     Only the SIMULATED "true" plant is replaced with this RK4
%     integrator; the MPC's internal predictive model (used inside
%     nlmpcmove's cost/constraint evaluation) is left as the original
%     Euler-based wt_step.m/sf_baseline.m, unchanged. This isolates the
%     question "does the plant's own numerical integration scheme
%     matter for closed-loop tracking accuracy", independent of any
%     model-mismatch question between predictor and plant (which
%     wt_step_true.m addresses separately, for a different purpose).
%
%   IMPLEMENTATION NOTE ON PITCH-RATE SATURATION
%     The pitch actuator rate limit (p.dbeta_max) is applied inside
%     rotor_ode_rhs() at every RK4 evaluation (4 times per step: k1-k4),
%     versus once per step in wt_step.m's single Euler evaluation. This
%     is a documented consequence of saturating a continuous-time
%     right-hand side re-used across RK4's four stages, not a
%     discrepancy to be hidden; its effect on closed-loop results is
%     part of what this sensitivity test is designed to reveal.
%
%   INPUTS/OUTPUTS: identical convention to wt_step.m.

f = @(xx) rotor_ode_rhs(xx, u, V, p);

k1 = f(x);
k2 = f(x + dt/2 * k1);
k3 = f(x + dt/2 * k2);
k4 = f(x + dt   * k3);

x_next = x + (dt/6) * (k1 + 2*k2 + 2*k3 + k4);

x_next(1) = max(p.omega_min, min(p.omega_max,    x_next(1)));
x_next(2) = max(p.beta_cp_min, min(p.beta_cp_max, x_next(2)));

end


function dxdt = rotor_ode_rhs(x, u, V, p)
% Continuous-time right-hand side, IDENTICAL physics to wt_step.m
% (same torque switching, same Br damping term, same pitch actuator
% saturation), extracted here as a pure function of state so it can be
% evaluated at RK4's four intermediate stages.

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

dbeta_dt = (u - beta) / p.tau_beta;
dbeta_dt = max(-p.dbeta_max, min(p.dbeta_max, dbeta_dt));

dxdt = [domega_dt; dbeta_dt];

end
