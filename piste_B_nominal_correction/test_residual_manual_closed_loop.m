function results = test_residual_manual_closed_loop()
% TEST_RESIDUAL_MANUAL_CLOSED_LOOP  Definitive test: is predict() ITSELF
% the structural cause of the catastrophic per-step SQP cost seen with
% every predict()-based surrogate in this project so far (TCN, LSTM,
% SW-MLP, PINN-v2, GP-v2, and the 130-parameter residual network)?
%
%   results = test_residual_manual_closed_loop()
%
%   COMPARISON
%     (1) Nominal-only        -- sf_baseline, no learned component
%     (2) Nominal+Correction  -- sf_residual, correction via predict()
%     (3) Nominal+Correction (manual) -- sf_residual_manual, correction
%         via hand-written matrix multiplication, NEVER calling
%         predict() or touching a dlnetwork/dlarray object
%
%   If (3) shows per-step CPU comparable to (1) [~20ms] rather than (2)
%   [~1150ms, from test_residual_closed_loop.m], this confirms predict()
%   itself -- not network size -- as the structural bottleneck.
%
%   NOTE ON "solver-non-convergence" METRIC
%     Renamed here to "MaxIter reached" for clarity: with
%     MaxIterations=30 (a deliberate hard cap on worst-case computation
%     time, not a budget expected to reach full optimality), ExitFlag<=0
%     is EXPECTED at essentially every step for EVERY controller,
%     including the fast, well-behaved Nominal-only baseline (confirmed
%     in test_residual_closed_loop.m: 600/600 for Nominal-only despite
%     18ms/step and correct tracking). This metric is retained for
%     completeness but should NOT be read as a failure indicator on its
%     own -- CPU time and RMSE are the metrics that matter here.
%
%   PREREQUISITES
%     stage2_residual_model.mat must exist (run stage2_train_residual()
%     first).

T_SIM  = 60;
V_MEAN = 14;
WIND_SEED = 2025;
TS_BUDGET_MS = 100;

fprintf('==========================================================\n');
fprintf('  DEFINITIVE TEST: is predict() itself the bottleneck?\n');
fprintf('  (%ds, V=%dm/s)\n', T_SIM, V_MEAN);
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

if ~exist('stage2_residual_model.mat', 'file')
    error('stage2_residual_model.mat not found. Run stage2_train_residual() first.');
end
S = load('stage2_residual_model.mat');
mdl_residual = S.mdl;

fprintf('Extracting raw weight matrices (bypassing predict() at simulation time)...\n');
mdl_manual = extract_residual_weights(mdl_residual);
fprintf('\n');

% ── Build the three controllers ──────────────────────────────────────────────
nlobj_nominal = nlmpc(2, 2, 1);
nlobj_nominal.Model.StateFcn = 'sf_baseline';
nlobj_nominal.Model.NumberOfParameters = 2;
nlobj_nominal = apply_common_settings(nlobj_nominal, p, cfg);

nlobj_residual = stage3_design_controllers_residual(p, mdl_residual, cfg);

nlobj_residual_manual = nlmpc(2, 2, 1);
nlobj_residual_manual.Model.StateFcn = 'sf_residual_manual';
nlobj_residual_manual.Model.NumberOfParameters = 4;
nlobj_residual_manual = apply_common_settings(nlobj_residual_manual, p, cfg);

N_steps = round(T_SIM / cfg.mpc.Ts);
V_wind  = kaimal_wind(V_MEAN, T_SIM, cfg.mpc.Ts, WIND_SEED);

test_cases = struct( ...
    'name',  {'Nominal-only', 'Nominal+Correction (predict)', 'Nominal+Correction (manual)'}, ...
    'nlobj', {nlobj_nominal, nlobj_residual, nlobj_residual_manual}, ...
    'kind',  {'nominal', 'residual_predict', 'residual_manual'});

results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_overruns_100ms', {}, 'maxiter_reached', {}, 'rmse_omega_rpm', {});

for c = 1:numel(test_cases)
    tc = test_cases(c);
    fprintf('\n--- Running %s vs TRUE plant (%d steps) ---\n', tc.name, N_steps);

    x  = [p.omega_r * 0.97; 3.5];   % FIX: matches stage3_run_simulation.m
    mv = x(2);                       % FIX: matches original's u_prev = x(2)
    omega_hist = zeros(N_steps,1);
    cpu_ms     = zeros(N_steps,1);
    maxiter_reached = 0;
    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);
        switch tc.kind
            case 'nominal'
                options.Parameters = {Vk, p};
            case 'residual_predict'
                options.Parameters = {Vk, mdl_residual, p, cfg.mpc.Ts};
            case 'residual_manual'
                options.Parameters = {Vk, mdl_manual, p, cfg.mpc.Ts};
        end

        t0 = tic;
        [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_ms(k) = toc(t0) * 1000;
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));   % FIX: safety clamp

        if isfield(info, 'ExitFlag') && info.ExitFlag <= 0
            maxiter_reached = maxiter_reached + 1;
        end

        x = wt_step_true(x, mv(1), Vk, p, cfg.mpc.Ts);
        omega_hist(k) = x(1) * 30/pi;

        if mod(k, 100) == 0
            fprintf('  step %d/%d  cpu=%.1fms  omega=%.2f rpm\n', ...
                k, N_steps, cpu_ms(k), omega_hist(k));
        end
    end

    r.name              = tc.name;
    r.cpu_ms            = cpu_ms;
    r.max_cpu_ms         = max(cpu_ms);
    r.n_overruns_100ms   = sum(cpu_ms > TS_BUDGET_MS);
    r.maxiter_reached    = maxiter_reached;
    r.rmse_omega_rpm     = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    results(end+1) = r; %#ok<AGROW>

    fprintf('  DONE: mean=%.1fms  max=%.1fms  overruns(>100ms)=%d/%d  RMSE=%.4f rpm\n', ...
        mean(cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, N_steps, r.rmse_omega_rpm);
end

fprintf('\n============================================================\n');
fprintf('  SUMMARY — Is predict() itself the bottleneck?\n');
fprintf('============================================================\n');
fprintf('%-32s %10s %10s %14s %10s\n', ...
    'Controller', 'Mean(ms)', 'Max(ms)', 'Overruns(>Ts)', 'RMSE(rpm)');
for k = 1:numel(results)
    r = results(k);
    fprintf('%-32s %10.1f %10.1f %14d %10.4f\n', ...
        r.name, mean(r.cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, r.rmse_omega_rpm);
end
fprintf('============================================================\n');
fprintf(['Interpretation:\n' ...
    '  - If "manual" mean CPU is close to Nominal-only (~20ms) rather\n' ...
    '    than "predict" mean CPU (~1150ms, same architecture), this\n' ...
    '    CONFIRMS predict() itself as the structural bottleneck --\n' ...
    '    independent of network size or dlnetwork vs other object types.\n' ...
    '  - "MaxIter reached" is expected near 100%% for ALL controllers\n' ...
    '    given MaxIterations=30 and is not a failure indicator alone\n' ...
    '    (see note in this function''s header).\n']);

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
if ~exist('results', 'dir'), mkdir('results'); end
outfile = sprintf('results/test_residual_manual_closed_loop_%s.mat', ts);
save(outfile, 'results', 'T_SIM', 'V_MEAN', 'WIND_SEED');
fprintf('\nResults saved to %s\n', outfile);

end


function nlobj = apply_common_settings(nlobj, p, cfg)
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
