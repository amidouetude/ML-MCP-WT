function cineq = ineqcon_gp_chance(X, U, e, data, V, mdl, cc)
% INEQCON_GP_CHANCE  Deterministic chance-constraint reformulation of
% the withdrawn cost_gp.m uncertainty penalty (kappa*sigma^2).
%
%   cineq = ineqcon_gp_chance(X, U, e, data, V, mdl, cc)
%
%   BACKGROUND (see docs/experiment_log.md, entry 2026-08-13)
%     cost_gp.m's uncertainty-penalized cost (J += kappa*sigma^2 at
%     every predicted step) produces STRUCTURAL infeasibility
%     (ExitFlag<0) independent of Nc (tested at Nc=1,2,4, 600/600
%     infeasible at every value) and independent of the NREL physics
%     correction -- confirmed by verify_gp_frozen_actuator.m (mv frozen
%     at 3.500 deg, 1200/1200 steps infeasible). The experiment log's
%     own decision on this entry: "repairing this formulation ... would
%     need to address the cost structure itself (e.g. reformulating
%     kappa*sigma^2 as a tightened constraint rather than a
%     cost-additive term, per the Hewing et al. 2020
%     probabilistic-reachable-set approach ...)". This file is exactly
%     that reformulation, on the GP-v2 model already in this project.
%
%   WHAT THIS TESTS
%     Standard (non-custom) quadratic cost is kept -- same
%     Weights.OutputVariables/ManipulatedVariablesRate convention as
%     the baseline/LLNFM/TCN/SW-MLP/PINN-v2 controllers, all of which
%     do NOT show cost_gp.m's infeasibility. This function adds ONLY a
%     GP-uncertainty-aware inequality constraint on top: instead of
%     penalizing sigma in the cost, it tightens the omega band by
%     z_alpha*sigma at every predicted step -- the deterministic
%     equivalent of P(omega_min <= omega(k+j) <= omega_max) >= 1-alpha
%     under the GP's own Gaussian predictive distribution.
%
%   SCOPE CAVEAT -- read before reuse
%     This project's state vector is [omega; beta] only (collective
%     pitch, 2 states) -- there is no blade-root-moment state yet (that
%     extension, M_yg/M_zg via Coleman transform, is future work
%     described in the IPC-MPC-Surrogate proposal). This file
%     constrains the GP's predicted OMEGA excursion as a proof-of-
%     concept and direct, testable replacement for cost_gp.m's
%     kappa*sigma^2 term -- it is NOT yet the blade-moment chance
%     constraint M_pred + z*sigma_GP <= M_max described in the
%     proposal/chance-constraints-mpc.md. Extending this to a moment
%     state is straightforward once that state exists (same mu/sigma
%     pattern, different GP output and bound).
%
%   INPUTS (nlmpc passes X, U, e, data automatically)
%     X     [Np+1 x 2]  predicted state trajectory [omega, beta]
%     U     [?    x 1]  predicted input trajectory (Np or Np+1 rows;
%                        defensively indexed via min(k,size(U,1)),
%                        exactly matching cost_gp.m's own convention)
%     e     slack variable (not used)
%     data  nlmpc internal data struct (not used)
%     V     wind speed [m/s]                      (parameter 1)
%     mdl   trained GP model struct (gp_o, gp_b, xmu, xsig)  (parameter 2)
%     cc    struct with fields:                    (parameter 3)
%             .z_alpha    quantile z_{1-alpha}, e.g. 1.645 for 95%
%             .omega_max  upper bound [rad/s]
%             .omega_min  lower bound [rad/s]
%
%   OUTPUT
%     cineq  [2*Np x 1]  constraint values; nlmpc/fmincon requires
%            cineq <= 0 at a feasible point. Rows 1:Np are the upper
%            bound (omega_pred + z*sigma - omega_max), rows Np+1:2*Np
%            are the lower bound (omega_min - (omega_pred - z*sigma)).
%
%   NumberOfParameters = 3 (V, mdl, cc) -- must match sf_gp_chance.m
%   and the controller's Model.NumberOfParameters.
%
%   No custom Jacobian is supplied (nlmpc/fmincon falls back to its own
%   finite-difference approximation of this constraint). An analytic
%   Jacobian was investigated (Matern52 kernel, 'Constant' basis,
%   reconstructing K(Xactive,Xactive) from gp.ActiveSetVectors +
%   gp.KernelInformation.KernelParameters + gp.Sigma) -- the POSTERIOR
%   MEAN reproduces predict() to 1e-12 this way (same formula as
%   extract_gp_weights.m), but the reconstructed posterior VARIANCE did
%   not match predict()'s second output closely enough (~4.5e-3 abs
%   error, disproportionate to sd_pred's own ~0.005-0.01 range) despite
%   a Cholesky-based (not naive inv()) solve -- likely an internal
%   regularization/jitter detail of fitrgp's 'Exact' method not fully
%   reverse-engineered here. Rather than ship an unverified analytic
%   variance gradient, this function calls predict() directly (exact,
%   by construction) and leaves the Jacobian to finite differences.
%   Revisit if per-step solve time becomes the bottleneck (unlikely --
%   GP's own predict() overhead was already the smallest of all
%   surrogates tested in this project, ~7.8x bypass speedup vs.
%   34x-2844x for TCN/LSTM; see experiment_log.md, 2026-07-30 entry).

Np = size(X, 1) - 1;
upper = zeros(Np, 1);
lower = zeros(Np, 1);

for k = 1:Np
    feat  = [X(k, 1), X(k, 2), V, U(min(k, size(U,1)), 1)];
    featn = (feat - mdl.xmu) ./ mdl.xsig;
    [mu_o, sigma_o] = predict(mdl.gp_o, featn);

    upper(k) = (mu_o + cc.z_alpha * sigma_o) - cc.omega_max;
    lower(k) = cc.omega_min - (mu_o - cc.z_alpha * sigma_o);
end

cineq = [upper; lower];
end
