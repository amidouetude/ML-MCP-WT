function test_gp_fix_smoke()
% TEST_GP_FIX_SMOKE  Minimal smoke test for the P0.1 fix (cost_gp.m
% Q/Q2/R no longer hardcoded). Builds the GP (V1) and GP-v2 (V2)
% controllers and performs ONE single nlmpcmove call each -- NOT a
% full closed-loop simulation -- to confirm there is no "wrong number
% of parameters" error or other construction-time failure introduced
% by the NumberOfParameters=4->7 change.
%
%   test_gp_fix_smoke()
%
%   This does NOT verify closed-loop behavior or numerical results --
%   only that the fix does not break controller construction or a
%   single solver call. No lengthy re-run of Stage 3, Monte Carlo, or
%   any sensitivity check is needed for this fix (see
%   docs/experiment_log.md for the rationale: Q/Q2/R values themselves
%   are unchanged, only how they reach cost_gp.m).

fprintf('==========================================================\n');
fprintf('  SMOKE TEST: P0.1 fix (cost_gp.m Q/Q2/R parameterization)\n');
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

omega_ref_radps = p.omega_r;
kappa_default   = cfg.mpc.kappa;

% ── Test 1: GP (V1) ──────────────────────────────────────────────────────────
fprintf('--- Test 1: GP (V1) controller ---\n');
try
    if ~isfile('stage2_models.mat')
        error('stage2_models.mat not found.');
    end
    V1 = load('stage2_models.mat');
    models_v1.llnfm = V1.mdl_llnfm;
    models_v1.lstm  = V1.mdl_lstm;
    models_v1.gp    = V1.mdl_gp;
    models_v1.pinn  = V1.mdl_pinn;
    controllers_v1 = stage3_design_controllers(p, models_v1, cfg);
    fprintf('  Controller construction: OK\n');

    x  = [p.omega_r * 0.97; 3.5];
    mv = x(2);
    options = nlmpcmoveopt;
    options.Parameters = {14, V1.mdl_gp, omega_ref_radps, kappa_default, ...
                           cfg.mpc.Q, 0.01, cfg.mpc.R};
    [mv_out, ~, info] = nlmpcmove(controllers_v1.gp, x, mv, [p.omega_r,0], [], options);
    fprintf('  Single nlmpcmove call: OK (mv=%.3f, ExitFlag=%d)\n', mv_out, info.ExitFlag);
    fprintf('  *** TEST 1 PASSED ***\n\n');
catch ME
    fprintf('  *** TEST 1 FAILED ***\n');
    fprintf('  Error: %s\n\n', ME.message);
end

% ── Test 2: GP-v2 (V2) ────────────────────────────────────────────────────────
fprintf('--- Test 2: GP-v2 (V2) controller ---\n');
try
    if ~isfile('stage2_models_v2.mat')
        error('stage2_models_v2.mat not found.');
    end
    V2 = load('stage2_models_v2.mat');
    models_v2.llnfm   = V2.mdl_llnfm;
    models_v2.tcn     = V2.mdl_tcn;
    models_v2.swmlp   = V2.mdl_swmlp;
    models_v2.gp_v2   = V2.mdl_gp_v2;
    models_v2.pinn_v2 = V2.mdl_pinn_v2;
    controllers_v2 = stage3_design_controllers_v2(p, models_v2, cfg);
    fprintf('  Controller construction: OK\n');

    x  = [p.omega_r * 0.97; 3.5];
    mv = x(2);
    options = nlmpcmoveopt;
    options.Parameters = {14, V2.mdl_gp_v2, omega_ref_radps, kappa_default, ...
                           cfg.mpc.Q, 0.01, cfg.mpc.R};
    [mv_out, ~, info] = nlmpcmove(controllers_v2.gp_v2, x, mv, [p.omega_r,0], [], options);
    fprintf('  Single nlmpcmove call: OK (mv=%.3f, ExitFlag=%d)\n', mv_out, info.ExitFlag);
    fprintf('  *** TEST 2 PASSED ***\n\n');
catch ME
    fprintf('  *** TEST 2 FAILED ***\n');
    fprintf('  Error: %s\n\n', ME.message);
end

fprintf('============================================================\n');
fprintf('  Smoke test complete. If both tests PASSED, the P0.1 fix is\n');
fprintf('  confirmed structurally sound -- no re-run of Stage 3, Monte\n');
fprintf('  Carlo, or sensitivity checks is required for this fix alone.\n');
fprintf('============================================================\n');

end
