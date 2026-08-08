function controllers = stage3_design_controllers(p, models, cfg)
% STAGE3_DESIGN_CONTROLLERS  Create all 5 nlmpc() objects
%
%   controllers = stage3_design_controllers(p, models, cfg)
%
%   INPUTS
%     p       turbine parameter struct (from get_wt_params, with p.dt added)
%     models  struct with fields: llnfm, lstm, gp, pinn
%     cfg     stage0_config() struct
%
%   OUTPUT
%     controllers struct with fields: baseline, llnfm, lstm, gp, pinn
%
%   PARAMETER PASSING (R2024a confirmed)
%     nlmpc with NumberOfParameters=N passes N parameters to BOTH
%     StateFcn and CustomCostFcn in the same order.
%     sf_gp uses only p1=V and p2=mdl; p3=omega_ref, p4=kappa, p5=Q,
%     p6=Q2, p7=R are passed but ignored by sf_gp (no error in MATLAB)
%     -- Q/Q2/R [ADDED, P0.1 fix] are used by cost_gp.m only, replacing
%     that file's previously hardcoded weights.
%
%   CONTROLLER SIGNATURES
%     Baseline : sf_baseline(x, u, V, p)          → N_params=2
%     LLNFM    : sf_llnfm(x, u, V, mdl)           → N_params=2
%     LSTM     : sf_lstm(x, u, V, mdl, seq_buf)   → N_params=3
%     GP       : sf_gp(x, u, V, mdl, omega_r, k, Q, Q2, R) → N_params=7
%     PINN     : sf_pinn(x, u, V, mdl)            → N_params=2
%
%   OMEGA BOUNDS — TWO DISTINCT SETS (CRITICAL)
%     Baseline uses wt_step.m (the true physical plant) directly — no
%     surrogate involved — so it is bound by p.omega_mpc_min_physics,
%     a defense-in-depth floor related to the Region II/III torque law.
%
%     The 4 surrogate controllers (LLNFM, LSTM, GP, PINN) are bound by
%     p.omega_mpc_min_surrogate / p.omega_mpc_max_surrogate — the Stage 1
%     training domain with safety margin. This is REQUIRED, not optional:
%     observed failure mode without it — LLNFM-MPC pushed omega to 7.55
%     rpm (training domain: [10.28, 13.31] rpm) while pitch saturated at
%     25 deg, consistent with a surrogate that had lost sensitivity to
%     the true state once its input was clamped at the FIS range boundary
%     (clamp_to_fis in sf_llnfm.m masks the symptom, not the cause).
%     Using the physics-based bound for surrogates would not prevent this,
%     since it does not reflect what the surrogate has actually learned.

nx = 2;  ny = 2;  nu = 1;
Np = cfg.mpc.Np;
Nc = cfg.mpc.Nc;
Ts = cfg.mpc.Ts;
Q  = cfg.mpc.Q;
R  = cfg.mpc.R;

fprintf('  Designing 5 nlmpc() controllers (Np=%d, Nc=%d, Ts=%.2f)...\n', ...
        Np, Nc, Ts);
fprintf('    omega bound (Baseline, physics)  : [%.2f, %.2f] rpm\n', ...
        p.omega_mpc_min_physics*30/pi, p.omega_max*30/pi);
fprintf('    omega bound (surrogates, domain) : [%.2f, %.2f] rpm\n', ...
        p.omega_mpc_min_surrogate*30/pi, p.omega_mpc_max_surrogate*30/pi);

% ── Helper: apply common settings (omega bound is a parameter) ───────────────
    function nlobj = apply_common(nlobj, n_params, omega_min_bound, omega_max_bound)
        nlobj.Ts                = Ts;
        nlobj.PredictionHorizon = Np;
        nlobj.ControlHorizon    = Nc;

        % Output weights: [omega tracking, beta regulation]
        nlobj.Weights.OutputVariables          = [Q, 0.01];
        nlobj.Weights.ManipulatedVariablesRate = R;

        % State (output) constraints — bound depends on controller type
        % (physics-based for Baseline, training-domain for surrogates)
        nlobj.OV(1).Min = omega_min_bound;
        nlobj.OV(1).Max = omega_max_bound;
        nlobj.OV(2).Min = p.beta_cp_min;
        nlobj.OV(2).Max = p.beta_cp_max;

        % Input constraints: pitch angle and rate
        nlobj.MV(1).Min     = p.beta_cp_min;
        nlobj.MV(1).Max     = p.beta_cp_max;
        nlobj.MV(1).RateMin = -p.dbeta_max * Ts;
        nlobj.MV(1).RateMax =  p.dbeta_max * Ts;

        nlobj.Model.NumberOfParameters = n_params;

        % ── Solver options — bound computation time per step ──────────────────
        % CRITICAL FIX: default MaxIterations=400 allowed the SQP solver to
        % run up to 20+ seconds per step when constraints were difficult to
        % satisfy (observed: LLNFM-MPC reached 20624 ms/step at k=480).
        % Each SQP iteration calls the surrogate state function multiple
        % times (for cost AND constraint gradients), making 400 iterations
        % prohibitively expensive with ML surrogates vs. the analytical
        % baseline model. Real-time MPC must have a bounded worst-case
        % computation time; returning a sub-optimal-but-feasible solution
        % within budget is preferable to an unbounded search for the optimum.
        nlobj.Optimization.SolverOptions.MaxIterations         = 30;
        nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
        nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
        nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
        nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;
    end

% ── 1. Baseline MPC — physics-based omega bound ───────────────────────────────
fprintf('    [1/5] Baseline MPC ...\n');
nlobj_base = nlmpc(nx, ny, nu);
nlobj_base.Model.StateFcn = 'sf_baseline';
nlobj_base = apply_common(nlobj_base, 2, ...
    p.omega_mpc_min_physics, p.omega_max);   % params: {V, p}
controllers.baseline = nlobj_base;

% ── 2. LLNFM-MPC — surrogate training-domain bound ───────────────────────────
fprintf('    [2/5] LLNFM-MPC ...\n');
nlobj_llnfm = nlmpc(nx, ny, nu);
nlobj_llnfm.Model.StateFcn = 'sf_llnfm';
nlobj_llnfm = apply_common(nlobj_llnfm, 2, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);  % params: {V, mdl}
controllers.llnfm = nlobj_llnfm;

% ── 3. LSTM-MPC — surrogate training-domain bound ────────────────────────────
fprintf('    [3/5] LSTM-MPC ...\n');
nlobj_lstm = nlmpc(nx, ny, nu);
nlobj_lstm.Model.StateFcn = 'sf_lstm';
nlobj_lstm = apply_common(nlobj_lstm, 3, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);  % params: {V, mdl, seq_buf}
controllers.lstm = nlobj_lstm;

% ── 4. GP-MPC — surrogate training-domain bound ──────────────────────────────
fprintf('    [4/5] GP-MPC ...\n');
nlobj_gp = nlmpc(nx, ny, nu);
nlobj_gp.Model.StateFcn          = 'sf_gp';
nlobj_gp.Optimization.CustomCostFcn       = 'cost_gp';
nlobj_gp.Optimization.ReplaceStandardCost = true;
% Suppress "Slack variable unused" warning: assign a small weight to e
% so nlmpc knows we are aware of it. Does not affect cost behaviour since
% cost_gp ignores e by design (no soft constraints in this formulation).
nlobj_gp.Optimization.CustomCostFcn = 'cost_gp';
nlobj_gp = apply_common(nlobj_gp, 7, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);
    % params: {V, mdl, omega_ref, kappa, Q, Q2, R}
    % [UPDATED -- P0.1 fix: cost_gp.m no longer hardcodes Q/Q2/R;
    % NumberOfParameters grew from 4 to 7 to match. Whichever script
    % calls nlmpcmove for this controller must now pass
    % options.Parameters = {V, mdl, omega_ref, kappa, cfg.mpc.Q, 0.01,
    % cfg.mpc.R} -- see cost_gp.m header for the full rationale.
controllers.gp = nlobj_gp;

% ── 5. PINN-MPC — surrogate training-domain bound ────────────────────────────
fprintf('    [5/5] PINN-MPC ...\n');
nlobj_pinn = nlmpc(nx, ny, nu);
nlobj_pinn.Model.StateFcn = 'sf_pinn';
nlobj_pinn = apply_common(nlobj_pinn, 2, ...
    p.omega_mpc_min_surrogate, p.omega_mpc_max_surrogate);  % params: {V, mdl}
controllers.pinn = nlobj_pinn;

fprintf('  All 5 controllers designed.\n');
end 