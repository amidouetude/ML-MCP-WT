function results = test_gp_residual_manual_closed_loop()
% TEST_GP_RESIDUAL_MANUAL_CLOSED_LOOP  Generalization test: does
% bypassing predict() also resolve the SQP-cost catastrophe for a
% Gaussian Process (RegressionGP object), as it did for the small MLP
% in test_residual_manual_closed_loop.m?
%
%   results = test_gp_residual_manual_closed_loop()
%
%   COMPARISON
%     (1) Nominal-only              -- sf_baseline
%     (2) Nominal+GP (predict)      -- sf_gp_residual_predict
%     (3) Nominal+GP (manual)       -- sf_gp_residual_manual, hand-
%         written Matern 5/2 kernel formula, no predict() call
%
%   PREREQUISITES
%     stage2_gp_residual_model.mat must exist (run
%     stage2_train_gp_residual() first).

T_SIM  = 60;
V_MEAN = 14;
WIND_SEED = 2025;
TS_BUDGET_MS = 100;

fprintf('==========================================================\n');
fprintf('  GENERALIZATION TEST: does the predict() bypass work for GP too?\n');
fprintf('  (%ds, V=%dm/s)\n', T_SIM, V_MEAN);
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

if ~exist('stage2_gp_residual_model.mat', 'file')
    error('stage2_gp_residual_model.mat not found. Run stage2_train_gp_residual() first.');
end
S = load('stage2_gp_residual_model.mat');
mdl_gp = S.mdl;

fprintf('Extracting raw GP parameters (bypassing predict() at simulation time)...\n');
mdl_gp_manual = extract_gp_weights(mdl_gp);
fprintf('\n');

nlobj_nominal = nlmpc(2, 2, 1);
nlobj_nominal.Model.StateFcn = 'sf_baseline';
nlobj_nominal.Model.NumberOfParameters = 2;
nlobj_nominal = apply_common_settings_gp(nlobj_nominal, p, cfg);

nlobj_gp_predict = nlmpc(2, 2, 1);
nlobj_gp_predict.Model.StateFcn = 'sf_gp_residual_predict';
nlobj_gp_predict.Model.NumberOfParameters = 4;
nlobj_gp_predict = apply_common_settings_gp(nlobj_gp_predict, p, cfg);

nlobj_gp_manual = nlmpc(2, 2, 1);
nlobj_gp_manual.Model.StateFcn = 'sf_gp_residual_manual';
nlobj_gp_manual.Model.NumberOfParameters = 4;
nlobj_gp_manual = apply_common_settings_gp(nlobj_gp_manual, p, cfg);

N_steps = round(T_SIM / cfg.mpc.Ts);
V_wind  = kaimal_wind(V_MEAN, T_SIM, cfg.mpc.Ts, WIND_SEED);

test_cases = struct( ...
    'name',  {'Nominal-only', 'Nominal+GP (predict)', 'Nominal+GP (manual)'}, ...
    'nlobj', {nlobj_nominal, nlobj_gp_predict, nlobj_gp_manual}, ...
    'kind',  {'nominal', 'gp_predict', 'gp_manual'});

results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_overruns_100ms', {}, 'rmse_omega_rpm', {});

for c = 1:numel(test_cases)
    tc = test_cases(c);
    fprintf('\n--- Running %s vs TRUE plant (%d steps) ---\n', tc.name, N_steps);

    x  = [p.omega_r * 0.97; 3.5];   % FIX: matches stage3_run_simulation.m
    mv = x(2);                       % FIX: matches original's u_prev = x(2)
    omega_hist = zeros(N_steps,1);
    cpu_ms     = zeros(N_steps,1);
    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);
        switch tc.kind
            case 'nominal'
                options.Parameters = {Vk, p};
            case 'gp_predict'
                options.Parameters = {Vk, mdl_gp, p, cfg.mpc.Ts};
            case 'gp_manual'
                options.Parameters = {Vk, mdl_gp_manual, p, cfg.mpc.Ts};
        end

        t0 = tic;
        [mv, options, ~] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_ms(k) = toc(t0) * 1000;
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));   % FIX: safety clamp

        x = wt_step_true(x, mv(1), Vk, p, cfg.mpc.Ts);
        omega_hist(k) = x(1) * 30/pi;

        if mod(k, 100) == 0
            fprintf('  step %d/%d  cpu=%.1fms  omega=%.2f rpm\n', ...
                k, N_steps, cpu_ms(k), omega_hist(k));
        end
    end

    r.name            = tc.name;
    r.cpu_ms          = cpu_ms;
    r.max_cpu_ms       = max(cpu_ms);
    r.n_overruns_100ms = sum(cpu_ms > TS_BUDGET_MS);
    r.rmse_omega_rpm   = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    results(end+1) = r; %#ok<AGROW>

    fprintf('  DONE: mean=%.1fms  max=%.1fms  overruns(>100ms)=%d/%d  RMSE=%.4f rpm\n', ...
        mean(cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, N_steps, r.rmse_omega_rpm);
end

fprintf('\n============================================================\n');
fprintf('  SUMMARY — Does the predict() bypass generalize to GP?\n');
fprintf('============================================================\n');
fprintf('%-24s %10s %10s %14s %10s\n', ...
    'Controller', 'Mean(ms)', 'Max(ms)', 'Overruns(>Ts)', 'RMSE(rpm)');
for k = 1:numel(results)
    r = results(k);
    fprintf('%-24s %10.1f %10.1f %14d %10.4f\n', ...
        r.name, mean(r.cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, r.rmse_omega_rpm);
end
fprintf('============================================================\n');
fprintf(['Reference from the MLP case (test_residual_manual_closed_loop.m):\n' ...
    '  predict(): mean=1265.2ms/step | manual: mean=19.2ms/step (~65x speedup)\n' ...
    'If "Nominal+GP (manual)" here shows a comparable speedup over\n' ...
    '"Nominal+GP (predict)", this CONFIRMS the predict() bottleneck\n' ...
    'generalizes across surrogate types (neural network AND Gaussian\n' ...
    'Process), not just network-based architectures.\n']);

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
if ~exist('results', 'dir'), mkdir('results'); end
outfile = sprintf('results/test_gp_residual_manual_closed_loop_%s.mat', ts);
save(outfile, 'results', 'T_SIM', 'V_MEAN', 'WIND_SEED');
fprintf('\nResults saved to %s\n', outfile);

end


function nlobj = apply_common_settings_gp(nlobj, p, cfg)
nlobj.Ts                = cfg.mpc.Ts;
nlobj.PredictionHorizon = cfg.mpc.Np;
nlobj.ControlHorizon    = cfg.mpc.Nc;
nlobj.Weights.OutputVariables          = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
nlobj.OV(1).Min = p.omega_mpc_min_physics;
nlobj.OV(1).Max = p.omega_max;
nlobj.OV(2).Min = p.beta_cp_min;
nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min     = p.beta_cp_min;
nlobj.MV(1).Max     = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max * cfg.mpc.Ts;
nlobj.MV(1).RateMax =  p.dbeta_max * cfg.mpc.Ts;
nlobj.Optimization.SolverOptions.MaxIterations          = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;
end
