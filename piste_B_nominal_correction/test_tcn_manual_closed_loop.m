function results = test_tcn_manual_closed_loop()
% TEST_TCN_MANUAL_CLOSED_LOOP  Verify the manual TCN forward pass
% against predict(), THEN (only if verification passes) run the
% closed-loop predict()-vs-manual comparison. This is the most
% architecturally complex manual bypass attempted in this project
% (dilated causal convolutions + layer normalisation), so verification
% is checked explicitly before any closed-loop claim is made.
%
%   results = test_tcn_manual_closed_loop()
%
%   IF VERIFICATION FAILS
%     The layer-normalisation assumption in extract_tcn_weights.m /
%     tcn_forward_manual.m (per-channel-only normalisation at each
%     time step) is the most likely point of failure. If diff is large,
%     try joint channel+time normalisation instead (normalise over both
%     dimensions combined per sample) in layer_norm_channel().
%
%   PREREQUISITES
%     stage2_models_v2.mat (contains mdl_tcn) in the current folder or
%     on path.

fprintf('==========================================================\n');
fprintf('  TCN predict() BYPASS — VERIFICATION FIRST\n');
fprintf('==========================================================\n\n');

if ~exist('stage2_models_v2.mat', 'file')
    error('stage2_models_v2.mat not found. Copy it into this folder or common/ first.');
end
V2 = load('stage2_models_v2.mat');
mdl_tcn = V2.mdl_tcn;

fprintf('Extracting TCN weights (dilated causal conv + layer norm + FC)...\n');
mdl_tcn_manual = extract_tcn_weights(mdl_tcn);

% ── VERIFICATION (mandatory before trusting closed-loop results) ───────────
fprintf('\nVerifying manual TCN forward pass against predict()...\n');
seq_len = mdl_tcn.seq_len;
rng(42);
n_checks = 5;
max_diff_overall = 0;
for i = 1:n_checks
    x_test = [ (10 + 3*rand())*pi/30, 10*rand(), 10+15*rand(), 20*rand() ];
    buf = repmat(x_test, seq_len, 1) + 0.01*randn(seq_len, 4);  % slight variation per row
    buf_n = (buf - mdl_tcn.xmu) ./ mdl_tcn.xsig;

    X_ctb_dl = dlarray(reshape(buf_n', 4, seq_len, 1), 'CTB');
    y_predict = extractdata(predict(mdl_tcn.net, X_ctb_dl));
    y_predict = reshape(y_predict, 1, 2);

    y_manual = tcn_forward_manual(buf_n', mdl_tcn_manual);

    d = max(abs(y_predict(:) - y_manual(:)));
    max_diff_overall = max(max_diff_overall, d);
    fprintf('  check %d/%d: max abs diff = %.2e\n', i, n_checks, d);
end

if max_diff_overall > 1e-4
    fprintf('\n');
    warning(['VERIFICATION FAILED (max diff = %.2e). The layer-normalisation ' ...
             'assumption (per-channel-only) is likely wrong for this network. ' ...
             'DO NOT trust the closed-loop results below -- try joint ' ...
             'channel+time normalisation in layer_norm_channel() instead, ' ...
             'or inspect mdl_tcn.net.Layers for the ln1/ln2/ln3 ' ...
             '"OperationDimension" property directly if available in this ' ...
             'MATLAB version.'], max_diff_overall);
    results = struct([]);
    return;
else
    fprintf('\nVERIFICATION PASSED (max diff = %.2e across %d random checks).\n', ...
        max_diff_overall, n_checks);
end

% ── Closed-loop comparison (only reached if verification passed) ──────────
fprintf('\n==========================================================\n');
fprintf('  CLOSED-LOOP TEST: TCN predict() vs manual\n');
fprintf('==========================================================\n\n');

T_SIM = 60; V_MEAN = 14; WIND_SEED = 2025; TS_BUDGET_MS = 100;

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc; Ts = cfg.mpc2.Ts;

nlobj_baseline = build_ctrl('sf_baseline', 2, p, cfg, Np, Nc, Ts, true);
nlobj_tcn      = build_ctrl('sf_tcn',        2, p, cfg, Np, Nc, Ts, false);
nlobj_tcn_man  = build_ctrl('sf_tcn_manual', 2, p, cfg, Np, Nc, Ts, false);

N_steps = round(T_SIM / Ts);
V_wind  = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);

test_cases = struct('name', {'Baseline', 'TCN (predict)', 'TCN (manual)'}, ...
    'nlobj', {nlobj_baseline, nlobj_tcn, nlobj_tcn_man}, ...
    'kind',  {'baseline', 'tcn', 'tcn_manual'});

results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_overruns_100ms', {}, 'rmse_omega_rpm', {});

for c = 1:numel(test_cases)
    tc = test_cases(c);
    fprintf('\n--- Running %s (%d steps) ---\n', tc.name, N_steps);

    x  = [p.omega_r * 0.97; 3.5];   % FIX: matches stage3_run_simulation.m
    mv = x(2);                       % FIX: matches original's u_prev = x(2)
    omega_hist = zeros(N_steps,1);
    cpu_ms     = zeros(N_steps,1);
    options = nlmpcmoveopt;

    seq_buf = repmat([x(1), x(2), V_wind(1), mv], mdl_tcn.seq_len, 1);

    for k = 1:N_steps
        Vk = V_wind(k);
        switch tc.kind
            case 'baseline'
                options.Parameters = {Vk, p};
            case 'tcn'
                mdl_tcn.seq_buf = seq_buf;
                options.Parameters = {Vk, mdl_tcn};
            case 'tcn_manual'
                mdl_tcn_manual.seq_buf = seq_buf;
                options.Parameters = {Vk, mdl_tcn_manual};
        end

        t0 = tic;
        [mv, options, ~] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_ms(k) = toc(t0) * 1000;
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));   % FIX: safety clamp

        if ismember(tc.kind, {'tcn','tcn_manual'})
            seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
        end

        x = wt_step(x, mv(1), Vk, p, Ts);
        omega_hist(k) = x(1) * 30/pi;

        if mod(k, 100) == 0
            fprintf('  step %d/%d  cpu=%.1fms  omega=%.2f rpm\n', k, N_steps, cpu_ms(k), omega_hist(k));
        end
    end

    r.name = tc.name; r.cpu_ms = cpu_ms; r.max_cpu_ms = max(cpu_ms);
    r.n_overruns_100ms = sum(cpu_ms > TS_BUDGET_MS);
    r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    results(end+1) = r; %#ok<AGROW>

    fprintf('  DONE: mean=%.1fms  max=%.1fms  overruns(>100ms)=%d/%d  RMSE=%.4f rpm\n', ...
        mean(cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, N_steps, r.rmse_omega_rpm);
end

fprintf('\n============================================================\n');
fprintf('  SUMMARY — TCN predict() bypass\n');
fprintf('============================================================\n');
fprintf('%-16s %10s %10s %14s %10s\n', 'Controller','Mean(ms)','Max(ms)','Overruns(>Ts)','RMSE(rpm)');
for k = 1:numel(results)
    r = results(k);
    fprintf('%-16s %10.1f %10.1f %14d %10.4f\n', r.name, mean(r.cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, r.rmse_omega_rpm);
end

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
if ~exist('results', 'dir'), mkdir('results'); end
save(sprintf('results/test_tcn_manual_closed_loop_%s.mat', ts), 'results', 'T_SIM', 'V_MEAN', 'WIND_SEED');

end

function nlobj = build_ctrl(stateFcnName, nParams, p, cfg, Np, Nc, Ts, isBaseline)
nlobj = nlmpc(2, 2, 1);
nlobj.Model.StateFcn = stateFcnName;
nlobj.Model.NumberOfParameters = nParams;
nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
if isBaseline
    nlobj.OV(1).Min = p.omega_mpc_min_physics; nlobj.OV(1).Max = p.omega_max;
else
    nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
end
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
nlobj.Optimization.SolverOptions.MaxIterations = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance = 1e-4;
end
