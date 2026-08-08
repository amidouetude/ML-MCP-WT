function [A, B] = sf_gp_jacobian(x, u, V, mdl, omega_ref, kappa)
% SF_GP_JACOBIAN  State Jacobian for GP-MPC (Jacobian.StateFcn)
%
%   [A, B] = sf_gp_jacobian(x, u, V, mdl, omega_ref, kappa)
%
%   Provides nlmpc with dF/dx (A, 2x2) and dF/du (B, 2x1) for the GP
%   state function sf_gp.m, computed by CENTRAL FINITE DIFFERENCES on
%   sf_gp() itself, evaluated ONCE per call in a small local batch.
%
%   WHY THIS SHOULD HELP EVEN THOUGH IT IS "JUST" FINITE DIFFERENCES
%     Without ANY user-supplied Jacobian.StateFcn, fmincon must estimate
%     the constraint gradient by perturbing EVERY decision variable in
%     the FULL prediction trajectory and re-evaluating the ENTIRE
%     nonlinear constraint function (all Np horizon steps) for each
%     perturbation direction — this is what appeared as "stateEvolution"
%     in the earlier error stack trace. That is O(n_decision_vars) full
%     trajectory re-evaluations PER SQP ITERATION.
%
%     By supplying ANY Jacobian.StateFcn (even one computed via finite
%     differences locally, as here), nlmpc instead calls this function
%     directly at each horizon step to get dF/dx and dF/du in closed
%     form (from nlmpc's perspective), removing the combinatorial
%     multiplication entirely. The finite-difference cost here is fixed
%     and small: 3 extra sf_gp() calls (perturb omega, perturb beta,
%     perturb u), independent of horizon length or number of SQP
%     iterations elsewhere in the solve.
%
%   INPUTS   same as sf_gp.m: x=[omega;beta], u=pitch cmd, V=wind speed,
%            mdl, omega_ref, kappa (last two unused here, kept for
%            NumberOfParameters consistency with sf_gp/cost_gp)
%
%   OUTPUTS
%     A  [2x2]  d(xnext)/d(x),   xnext = [omega_next; beta_next]
%     B  [2x1]  d(xnext)/d(u)
%
%   NOTE — CustomCostFcn Jacobian NOT provided here
%     cost_gp.m also re-queries predict(mdl.gp_o,...) at every horizon
%     step for the uncertainty penalty term. If this script's test shows
%     only partial improvement, the next step is an analogous
%     cost_gp_jacobian.m for Jacobian.CustomCostFcn — deferred until we
%     see whether the StateFcn Jacobian alone is sufficient, to keep
%     this experiment isolated and interpretable.

h_omega = 1e-4;   % rad/s, small perturbation for omega
h_beta  = 1e-3;   % deg,   small perturbation for beta
h_u     = 1e-3;   % deg,   small perturbation for pitch command

x = x(:);

% ── Nominal not needed for central differences, but kept for reference ──────
% xnext0 = sf_gp(x, u, V, mdl, omega_ref, kappa);

% ── Perturb omega (x(1)) ──────────────────────────────────────────────────
xp = x; xp(1) = xp(1) + h_omega;
xm = x; xm(1) = xm(1) - h_omega;
fp = sf_gp(xp, u, V, mdl, omega_ref, kappa);
fm = sf_gp(xm, u, V, mdl, omega_ref, kappa);
dF_domega = (fp - fm) / (2*h_omega);   % [2x1]

% ── Perturb beta (x(2)) ───────────────────────────────────────────────────
xp = x; xp(2) = xp(2) + h_beta;
xm = x; xm(2) = xm(2) - h_beta;
fp = sf_gp(xp, u, V, mdl, omega_ref, kappa);
fm = sf_gp(xm, u, V, mdl, omega_ref, kappa);
dF_dbeta = (fp - fm) / (2*h_beta);     % [2x1]

% ── Perturb u ─────────────────────────────────────────────────────────────
up = u + h_u;
um = u - h_u;
fp = sf_gp(x, up, V, mdl, omega_ref, kappa);
fm = sf_gp(x, um, V, mdl, omega_ref, kappa);
dF_du = (fp - fm) / (2*h_u);           % [2x1]

A = [dF_domega, dF_dbeta];   % [2x2]
B = dF_du;                   % [2x1]

end
