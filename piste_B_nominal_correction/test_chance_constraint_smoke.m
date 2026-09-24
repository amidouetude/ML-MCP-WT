function test_chance_constraint_smoke()
% TEST_CHANCE_CONSTRAINT_SMOKE  Does replacing cost_gp.m's withdrawn
% kappa*sigma^2 cost-additive uncertainty penalty with a deterministic
% chance CONSTRAINT (ineqcon_gp_chance.m) resolve the structural
% ExitFlag<0 infeasibility documented in docs/experiment_log.md
% (2026-08-13 entry: GP-v2 100% infeasible at every Nc in {1,2,4};
% verify_gp_frozen_actuator.m: 1200/1200 steps infeasible, mv frozen
% at 3.500 deg)?
%
%   test_chance_constraint_smoke()
%
%   Test 1: single nlmpcmove call (mirrors test_gp_fix_smoke.m Test 2).
%   Test 2: 60s closed loop at constant V=14 m/s (matches the exact
%   Nc-sweep/frozen-actuator diagnostic convention: Ts=0.1s, T=60s ->
%   600 steps), logging ExitFlag and pitch activity, so the result is
%   directly comparable to the documented "600/600" and "1200/1200"
%   infeasibility counts for cost_gp.m.

fprintf('==========================================================\n');
fprintf('  SMOKE TEST: chance-constrained GP-v2 (replaces cost_gp.m)\n');
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc2.Ts;

V2 = load('stage2_models_v2.mat');
mdl = V2.mdl_gp_v2;

cc.z_alpha   = 1.645;                        % 95% one-sided quantile
cc.omega_max = p.omega_mpc_max_surrogate;    % same envelope already used as OV bound
cc.omega_min = p.omega_mpc_min_surrogate;

% ── Build controller: standard quadratic cost (same convention as the
%    non-GP surrogate controllers in stage3_design_controllers_v2.m)
%    + the new chance constraint on top. NO CustomCostFcn -- this is
%    the key structural difference from the withdrawn cost_gp.m. ──────
Np = cfg.mpc2.Np;  Nc = cfg.mpc2.Nc;  Ts = cfg.mpc2.Ts;
Q  = cfg.mpc2.Q;    R  = cfg.mpc2.R;

nlobj = nlmpc(2, 2, 1);
nlobj.Model.StateFcn          = 'sf_gp_chance';
nlobj.Model.NumberOfParameters = 3;
nlobj.Ts                      = Ts;
nlobj.PredictionHorizon       = Np;
nlobj.ControlHorizon          = Nc;
nlobj.Weights.OutputVariables          = [Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = R;

nlobj.OV(1).Min = p.omega_mpc_min_surrogate;
nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
nlobj.OV(2).Min = p.beta_cp_min;
nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min     = p.beta_cp_min;
nlobj.MV(1).Max     = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max * Ts;
nlobj.MV(1).RateMax =  p.dbeta_max * Ts;

nlobj.Optimization.CustomIneqConFcn = 'ineqcon_gp_chance';

nlobj.Optimization.SolverOptions.MaxIterations          = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;

fprintf('Controller construction: OK\n\n');

% ── Test 1: single nlmpcmove call ─────────────────────────────────────
fprintf('--- Test 1: single nlmpcmove call ---\n');
try
    x  = [p.omega_r * 0.97; 3.5];
    mv = x(2);
    options = nlmpcmoveopt;
    options.Parameters = {14, mdl, cc};
    [mv_out, ~, info] = nlmpcmove(nlobj, x, mv, [p.omega_r, 0], [], options);
    fprintf('  Single nlmpcmove call: OK (mv=%.3f, ExitFlag=%d)\n', mv_out, info.ExitFlag);
    fprintf('  *** TEST 1 %s ***\n\n', ternary(info.ExitFlag > 0, 'PASSED', 'INFEASIBLE (ExitFlag<=0)'));
catch ME
    fprintf('  *** TEST 1 FAILED (error) ***\n  %s\n\n', ME.message);
end

% ── Test 2: 60s closed loop at V=14 m/s, matching the project's own
%    Nc-sweep/frozen-actuator diagnostic convention exactly ──────────
fprintf('--- Test 2: 60s closed loop, V=14 m/s (matches experiment_log.md convention) ---\n');
try
    V_const = 14;
    T_sim   = 60;
    N_sim   = round(T_sim / Ts);

    x      = [p.omega_r * 0.97; 3.5];
    u_prev = x(2);
    opt    = nlmpcmoveopt;

    exitflags = zeros(N_sim, 1);
    omega_log = zeros(N_sim, 1);
    beta_log  = zeros(N_sim, 1);
    u_log     = zeros(N_sim, 1);

    for k = 1:N_sim
        opt.Parameters = {V_const, mdl, cc};
        [u_opt, ~, info] = nlmpcmove(nlobj, x, u_prev, [p.omega_r, 0], [], opt);
        exitflags(k) = info.ExitFlag;

        u_opt  = max(p.beta_cp_min, min(p.beta_cp_max, u_opt));
        u_prev = u_opt;

        omega_log(k) = x(1);
        beta_log(k)  = x(2);
        u_log(k)     = u_opt;

        x = wt_step(x, u_opt, V_const, p, Ts);

        if mod(k, round(N_sim/5)) == 0
            fprintf('    %3.0f%%  omega=%.3f rpm  beta=%.2f deg  ExitFlag(last)=%d\n', ...
                    100*k/N_sim, x(1)*30/pi, x(2), info.ExitFlag);
        end
    end

    n_infeasible    = sum(exitflags <= 0);
    pitch_activity  = sum(abs(diff(beta_log)));
    mv_std          = std(u_log);
    rmse_omega_rpm  = sqrt(mean((omega_log - p.omega_r).^2)) * 30/pi;

    fprintf('\n  RESULT: n_infeasible = %d / %d steps\n', n_infeasible, N_sim);
    fprintf('          pitch_activity = %.2f deg   mv std = %.4f deg\n', pitch_activity, mv_std);
    fprintf('          RMSE(omega)    = %.4f rpm\n', rmse_omega_rpm);
    fprintf('  For comparison, cost_gp.m (withdrawn) showed 1200/1200 infeasible,\n');
    fprintf('  mv frozen at 3.500 deg (std=0.0000), RMSE=0.7235 rpm.\n');
    if n_infeasible == 0 && mv_std > 1e-6
        fprintf('  *** TEST 2 PASSED: constraint reformulation resolves the documented infeasibility ***\n\n');
    elseif n_infeasible < N_sim
        fprintf('  *** TEST 2 PARTIAL: infeasibility reduced but not eliminated -- needs further tuning ***\n\n');
    else
        fprintf('  *** TEST 2 STILL INFEASIBLE: constraint reformulation alone did not resolve it ***\n\n');
    end
catch ME
    fprintf('  *** TEST 2 FAILED (error) ***\n  %s\n\n', ME.message);
    for i = 1:numel(ME.stack)
        fprintf('    at %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
end

fprintf('============================================================\n');
fprintf('  Smoke test complete.\n');
fprintf('============================================================\n');
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end
