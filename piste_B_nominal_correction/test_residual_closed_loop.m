function results = test_residual_closed_loop()
% TEST_RESIDUAL_CLOSED_LOOP  Closed-loop comparison for Piste B:
% Nominal-only MPC (sf_baseline, i.e. wt_step.m with no correction)
% versus Nominal+Correction MPC (sf_residual), BOTH controlling the
% TRUE plant (wt_step_true.m, with its unmodeled nonlinear damping
% term). This tests two things simultaneously:
%
%   (1) SCIENTIFIC QUESTION: does the learned correction improve
%       tracking of a plant with genuine unmodeled dynamics, relative
%       to the nominal model alone?
%   (2) FEASIBILITY QUESTION: does this small-network structure avoid
%       the systematic SQP non-convergence found in
%       test_gp_jacobian_closed_loop.m (max_iter_hits = 300/300 there)?
%
%   results = test_residual_closed_loop()
%
%   PREREQUISITES
%     common/ on path: get_wt_params.m, wt_step.m, kaimal_wind.m,
%     stage0_config.m, cp_lambda_beta.m
%     piste_B_nominal_correction/ on path: wt_step_true.m, sf_residual.m,
%     stage3_design_controllers_residual.m, stage2_residual_model.mat
%     (run stage1_generate_residual_data.m + stage2_train_residual.m first)

T_SIM  = 60;    % seconds
V_MEAN = 14;    % m/s
WIND_SEED = 2025;
SPIKE_MS = 50;
TS_BUDGET_MS = 100;

fprintf('==========================================================\n');
fprintf('  PISTE B — CLOSED-LOOP TEST: Nominal vs Nominal+Correction\n');
fprintf('  (both controlling the TRUE plant, %ds, V=%dm/s)\n', T_SIM, V_MEAN);
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;   % sf_baseline.m uses p.dt internally

if ~exist('stage2_residual_model.mat', 'file')
    error('stage2_residual_model.mat not found. Run stage2_train_residual() first.');
end
S = load('stage2_residual_model.mat');
mdl_residual = S.mdl;

% Build Nominal-only controller directly (equivalent to the original
% Baseline design, but constructed explicitly here for clarity of
% exactly what is being compared)
nlobj_nominal = nlmpc(2, 2, 1);
nlobj_nominal.Model.StateFcn = 'sf_baseline';
nlobj_nominal.Model.NumberOfParameters = 2; % V, p
nlobj_nominal.Ts                = cfg.mpc.Ts;
nlobj_nominal.PredictionHorizon = cfg.mpc.Np;
nlobj_nominal.ControlHorizon    = cfg.mpc.Nc;
nlobj_nominal.Weights.OutputVariables          = [cfg.mpc.Q, 0.01];
nlobj_nominal.Weights.ManipulatedVariablesRate = cfg.mpc.R;
nlobj_nominal.OV(1).Min = p.omega_mpc_min_physics;
nlobj_nominal.OV(1).Max = p.omega_max;
nlobj_nominal.OV(2).Min = p.beta_cp_min;
nlobj_nominal.OV(2).Max = p.beta_cp_max;
nlobj_nominal.MV(1).Min     = p.beta_cp_min;
nlobj_nominal.MV(1).Max     = p.beta_cp_max;
nlobj_nominal.MV(1).RateMin = -p.dbeta_max * cfg.mpc.Ts;
nlobj_nominal.MV(1).RateMax =  p.dbeta_max * cfg.mpc.Ts;
nlobj_nominal.Optimization.SolverOptions.MaxIterations          = 30;
nlobj_nominal.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj_nominal.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
nlobj_nominal.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
nlobj_nominal.Optimization.SolverOptions.StepTolerance          = 1e-4;

nlobj_residual = stage3_design_controllers_residual(p, mdl_residual, cfg);

N_steps = round(T_SIM / cfg.mpc.Ts);
V_wind  = kaimal_wind(V_MEAN, T_SIM, cfg.mpc.Ts, WIND_SEED);

test_cases = struct('name', {'Nominal-only', 'Nominal+Correction'}, ...
                     'nlobj', {nlobj_nominal, nlobj_residual}, ...
                     'is_residual', {false, true});

results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_spikes_50ms', {}, 'n_overruns_100ms', {}, 'max_iter_hits', {}, ...
    'rmse_omega_rpm', {});

for c = 1:numel(test_cases)
    tc = test_cases(c);
    fprintf('\n--- Running %s vs TRUE plant (%d steps) ---\n', tc.name, N_steps);

    x  = [p.omega_r; 0];
    mv = 0;
    omega_hist = zeros(N_steps,1);
    cpu_ms     = zeros(N_steps,1);
    max_iter_hits = 0;
    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);

        if tc.is_residual
            options.Parameters = {Vk, mdl_residual, p, cfg.mpc.Ts};
        else
            options.Parameters = {Vk, p};
        end

        t0 = tic;
        [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_ms(k) = toc(t0) * 1000;

        if isfield(info, 'ExitFlag') && info.ExitFlag <= 0
            max_iter_hits = max_iter_hits + 1;
        end

        % Advance the TRUE plant (both controllers are evaluated
        % against the same true, imperfectly-modeled system)
        x = wt_step_true(x, mv(1), Vk, p, cfg.mpc.Ts);
        omega_hist(k) = x(1) * 30/pi;

        if mod(k, 100) == 0
            fprintf('  step %d/%d  cpu=%.1fms  omega=%.2f rpm\n', ...
                k, N_steps, cpu_ms(k), omega_hist(k));
        end
    end

    r.name             = tc.name;
    r.cpu_ms           = cpu_ms;
    r.max_cpu_ms        = max(cpu_ms);
    r.n_spikes_50ms     = sum(cpu_ms > SPIKE_MS);
    r.n_overruns_100ms  = sum(cpu_ms > TS_BUDGET_MS);
    r.max_iter_hits     = max_iter_hits;
    r.rmse_omega_rpm    = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    results(end+1) = r; %#ok<AGROW>

    fprintf(['  DONE: mean=%.1fms  max=%.1fms  overruns(>100ms)=%d/%d  ' ...
              'solver-non-convergence=%d/%d  RMSE=%.4f rpm\n'], ...
        mean(cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, N_steps, ...
        max_iter_hits, N_steps, r.rmse_omega_rpm);
end

fprintf('\n============================================================\n');
fprintf('  PISTE B SUMMARY — Nominal vs Nominal+Correction (TRUE plant)\n');
fprintf('============================================================\n');
fprintf('%-20s %10s %10s %14s %16s %10s\n', ...
    'Controller', 'Mean(ms)', 'Max(ms)', 'Overruns(>Ts)', 'Non-converge', 'RMSE(rpm)');
for k = 1:numel(results)
    r = results(k);
    fprintf('%-20s %10.1f %10.1f %14d %16d %10.4f\n', ...
        r.name, mean(r.cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, ...
        r.max_iter_hits, r.rmse_omega_rpm);
end
fprintf('============================================================\n');
fprintf(['Interpretation guide:\n' ...
    '  - If Non-converge is near 0 for Nominal+Correction (vs 300/300\n' ...
    '    found for GP-v2 in test_gp_jacobian_closed_loop.m), this\n' ...
    '    supports the hypothesis that a SMALL network resolves the SQP\n' ...
    '    convergence issue where a large one did not.\n' ...
    '  - If RMSE(Nominal+Correction) < RMSE(Nominal-only), the learned\n' ...
    '    correction genuinely improves tracking of the unmodeled\n' ...
    '    dynamics in wt_step_true.m.\n']);

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
outfile = sprintf('results/test_residual_closed_loop_%s.mat', ts);
if ~exist('results', 'dir'), mkdir('results'); end
save(outfile, 'results', 'T_SIM', 'V_MEAN', 'WIND_SEED');
fprintf('\nResults saved to %s\n', outfile);

end
