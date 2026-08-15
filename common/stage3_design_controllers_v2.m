function controllers = stage3_design_controllers_v2(p, models, cfg)
% STAGE3_DESIGN_CONTROLLERS_V2  Create all nlmpc() objects for V2
%
%   controllers = stage3_design_controllers_v2(p, models, cfg)
%
%   INPUTS
%     p       turbine parameter struct (from get_wt_params, with p.dt added)
%     models  struct with fields: llnfm, tcn, swmlp, gp_v2, pinn_v2
%     cfg     stage0_config() struct  (uses cfg.mpc2 for V2 settings)
%
%   OUTPUT
%     controllers struct with fields: baseline, llnfm, tcn, swmlp, gp_v2, pinn_v2
%
%   V2 MPC CHANGES vs V1
%     Np = 20  (extended horizon, 2s vs 1s in V1)
%     Nc = 6   (extended control horizon)
%     All solver options identical (MaxIterations=30, tol=1e-4)
%
%   CONTROLLER SIGNATURES
%     Baseline : sf_baseline(x, u, V, p)         N_params=2
%     LLNFM    : sf_llnfm(x, u, V, mdl)          N_params=2
%     TCN      : sf_tcn(x, u, V, mdl)            N_params=2  (buf in mdl)
%     SW-MLP   : sf_swmlp(x, u, V, mdl)          N_params=2  (buf in mdl)
%     GP-v2    : sf_gp(x, u, V, mdl, omega_r, k, Q, Q2, R) N_params=7
%     PINN-v2  : sf_pinn(x, u, V, mdl)           N_params=2
%
%   NOTE ON TCN AND SW-MLP BUFFER
%     Unlike V1 LSTM which passed seq_buf as a 3rd parameter
%     (NumberOfParameters=3), V2 TCN and SW-MLP embed the buffer
%     inside mdl.seq_buf. This keeps NumberOfParameters=2 for all
%     single-output surrogates, simplifying controller management.
%     The buffer in mdl is initialised and updated externally by
%     stage3_run_simulation_v2 before each nlmpcmove call.
%
%   OMEGA BOUNDS
%     Same two-tier strategy as V1:
%       Baseline : omega_mpc_min_physics    (defense-in-depth)
%       Surrogates: omega_mpc_min_surrogate (training domain + 0.5rpm margin)

nx = 2;  ny = 2;  nu = 1;
Np = cfg.mpc2.Np;   % 15
Nc = cfg.mpc2.Nc;   % 4 (unified with V1, item 2.5)
Ts = cfg.mpc2.Ts;   % 0.1
Q  = cfg.mpc2.Q;    % 100
R  = cfg.mpc2.R;    % 0.5

fprintf('  Designing 6 nlmpc() V2 controllers (Np=%d, Nc=%d, Ts=%.2f)...\n', ...
        Np, Nc, Ts);
fprintf('    omega bound (Baseline, physics)  : [%.2f, %.2f] rpm\n', ...
        p.omega_mpc_min_physics*30/pi, p.omega_max*30/pi);
fprintf('    omega bound (surrogates, domain) : [%.2f, %.2f] rpm\n', ...
        p.omega_mpc_min_surrogate*30/pi, p.omega_mpc_max_surrogate*30/pi);

% ── Helper: apply common settings ─────────────────────────────────────────────
    function nlobj = apply_common(nlobj, n_params, omega_min_b, omega_max_b)
        nlobj.Ts                = Ts;
        nlobj.PredictionHorizon = Np;
        nlobj.ControlHorizon    = Nc;
        nlobj.Weights.OutputVariables          = [Q, 0.01];
        nlobj.Weights.ManipulatedVariablesRate = R;

        % State constraints
        nlobj.OV(1).Min = omega_min_b;
        nlobj.OV(1).Max = omega_max_b;
        nlobj.OV(2).Min = p.beta_cp_min;
        nlobj.OV(2).Max = p.beta_cp_max;

        % Input constraints
        nlobj.MV(1).Min     = p.beta_cp_min;
        nlobj.MV(1).Max     = p.beta_cp_max;
        nlobj.MV(1).RateMin = -p.dbeta_max * Ts;
        nlobj.MV(1).RateMax =  p.dbeta_max * Ts;

        nlobj.Model.NumberOfParameters = n_params;

        % Solver options — bounded computation time per step
        nlobj.Optimization.SolverOptions.MaxIterations          = 30;
        nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
        nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
        nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
        nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;
    end

% ── 1. Baseline MPC ───────────────────────────────────────────────────────────
fprintf('    [1/6] Baseline MPC ...\n');
nlobj_base = nlmpc(nx, ny, nu);
nlobj_base.Model.StateFcn = 'sf_baseline';
nlobj_base = apply_common(nlobj_base, 2, ...
    p.omega_mpc_min_physics, p.omega_max);
controllers.baseline = nlobj_base;

% ── 2. LLNFM-MPC ──────────────────────────────────────────────────────────────
fprintf('    [2/6] LLNFM-MPC ...\n');
nlobj_llnfm = nlmpc(nx, ny, nu);
nlobj_llnfm.Model.StateFcn = 'sf_llnfm';
nlobj_llnfm = apply_common(nlobj_llnfm, 2, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);
controllers.llnfm = nlobj_llnfm;

% ── 3. TCN-MPC ────────────────────────────────────────────────────────────────
fprintf('    [3/6] TCN-MPC ...\n');
nlobj_tcn = nlmpc(nx, ny, nu);
nlobj_tcn.Model.StateFcn = 'sf_tcn';
nlobj_tcn = apply_common(nlobj_tcn, 2, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);
controllers.tcn = nlobj_tcn;

% ── 4. SW-MLP-MPC ─────────────────────────────────────────────────────────────
fprintf('    [4/6] SW-MLP-MPC ...\n');
nlobj_swmlp = nlmpc(nx, ny, nu);
nlobj_swmlp.Model.StateFcn = 'sf_swmlp';
nlobj_swmlp = apply_common(nlobj_swmlp, 2, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);
controllers.swmlp = nlobj_swmlp;

% ── 5. GP-v2-MPC ──────────────────────────────────────────────────────────────
fprintf('    [5/6] GP-v2-MPC (Matern52 + calibrated uncertainty) ...\n');
nlobj_gp_v2 = nlmpc(nx, ny, nu);
nlobj_gp_v2.Model.StateFcn             = 'sf_gp';
nlobj_gp_v2.Optimization.CustomCostFcn = 'cost_gp';
nlobj_gp_v2.Optimization.ReplaceStandardCost = true;
nlobj_gp_v2 = apply_common(nlobj_gp_v2, 7, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);
    % params: {V, mdl, omega_ref, kappa, Q, Q2, R}
    % [UPDATED -- P0.1 fix: cost_gp.m no longer hardcodes Q/Q2/R;
    % NumberOfParameters grew from 4 to 7 to match. Whichever script
    % calls nlmpcmove for this controller must now pass
    % options.Parameters = {V, mdl, omega_ref, kappa, cfg.mpc.Q, 0.01,
    % cfg.mpc.R} -- see cost_gp.m header for the full rationale.
controllers.gp_v2 = nlobj_gp_v2;

% ── 6. PINN-v2-MPC ────────────────────────────────────────────────────────────
fprintf('    [6/6] PINN-v2-MPC (softplus differentiable Cp) ...\n');
nlobj_pinn_v2 = nlmpc(nx, ny, nu);
nlobj_pinn_v2.Model.StateFcn = 'sf_pinn';
nlobj_pinn_v2 = apply_common(nlobj_pinn_v2, 2, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);
controllers.pinn_v2 = nlobj_pinn_v2;

fprintf('  All 6 V2 controllers designed.\n');
end
