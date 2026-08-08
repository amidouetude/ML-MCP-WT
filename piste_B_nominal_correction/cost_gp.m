function J = cost_gp(X, U, e, data, V, mdl, omega_ref, kappa, Q, Q2, R)
% COST_GP  Custom MPC cost for GP-MPC with uncertainty penalisation
%
%   J = cost_gp(X, U, e, data, V, mdl, omega_ref, kappa, Q, Q2, R)
%
%   Replaces the standard nlmpc quadratic cost with a custom function
%   that adds a GP predictive uncertainty penalty (Gap-1 contribution):
%
%     J = sum_k [ Q*(omega(k) - omega_ref)^2
%               + Q2*beta(k)^2
%               + R*(Delta_u(k))^2
%               + kappa*sigma(k)^2 ]
%
%   API NOTE — R2024a
%     data.Weights does NOT exist in R2024a's internal nlmpc data struct
%     (confirmed by diagnostic: fieldnames(data) lists Ts, CurrentStates,
%     LastMV, References, PredictionHorizon, etc. — no Weights field).
%
%   FIX [reproducibility review, P0.1] — Q/Q2/R were previously
%   HARDCODED here to match stage0_config.m's mpc.Q/mpc.R values, a
%   documented but fragile source of silent mismatch: changing
%   cfg.mpc.Q or cfg.mpc.R without also editing this file would make
%   reported results diverge silently from the actual code behaviour.
%   Q/Q2/R are now passed in as explicit parameters (like V, mdl,
%   omega_ref, kappa already were), read directly from cfg.mpc at the
%   controller-construction call site — see
%   stage3_design_controllers_v2.m and any script building a GP-v2
%   controller for the required options.Parameters ordering.
%
%   INPUTS (nlmpc passes these automatically)
%     X          [Np+1 x 2]  predicted state trajectory
%     U          [Np x 1]    predicted input trajectory
%     e          slack variable (not used)
%     data       nlmpc internal data struct (Weights NOT available here)
%     V          wind speed [m/s]   (parameter 1)
%     mdl        GP model struct     (parameter 2)
%     omega_ref  rated speed reference [rad/s] (parameter 3)
%     kappa      uncertainty penalty weight    (parameter 4)
%     Q          omega tracking weight         (parameter 5) [ADDED]
%     Q2         beta regulation weight        (parameter 6) [ADDED]
%     R          pitch rate weight             (parameter 7) [ADDED]
%
%   NumberOfParameters = 7 (was 4 before this fix — sf_gp.m's
%   NumberOfParameters and options.Parameters call sites MUST be
%   updated to match; sf_gp.m ignores Q/Q2/R just as it already
%   ignored omega_ref/kappa, purely to satisfy nlmpc's shared-
%   parameter-count requirement between StateFcn and CustomCostFcn.)

Np = size(X, 1) - 1;

J = 0;
for k = 1:Np
    % Tracking cost: omega error
    J = J + Q  * (X(k+1, 1) - omega_ref)^2;

    % Regulation cost: beta deviation
    J = J + Q2 * X(k+1, 2)^2;

    % Control rate cost: Delta_u (skip k=1: u_prev not in U)
    if k > 1
        J = J + R * (U(k, 1) - U(k-1, 1))^2;
    end

    % GP uncertainty penalty: kappa * sigma^2
    feat  = [X(k+1, 1), X(k+1, 2), V, U(min(k, size(U,1)), 1)];
    featn = (feat - mdl.xmu) ./ mdl.xsig;
    [~, so] = predict(mdl.gp_o, featn);
    J = J + kappa * so^2;
end
end
