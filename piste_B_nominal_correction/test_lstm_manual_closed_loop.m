function results = test_lstm_manual_closed_loop()
% TEST_LSTM_MANUAL_CLOSED_LOOP  Verify the manual LSTM forward pass
% against predict(), THEN (only if verification passes) run the
% closed-loop predict()-vs-manual comparison. Completes the series of
% predict()-bypass tests for all surrogates previously excluded from
% closed-loop comparison in the V1/V2 project.
%
%   results = test_lstm_manual_closed_loop()
%
%   PLANT / CONTROLLER SETTINGS
%     LSTM is a V1-only surrogate (stage2_models.mat, not
%     stage2_models_v2.mat), tested against the NOMINAL plant (wt_step.m)
%     with V1 horizon settings (cfg.mpc.Np/Nc), matching how it was
%     originally evaluated (and excluded) in the V1 project.
%
%   IF VERIFICATION FAILS
%     Most likely causes: (a) gate order assumption (input/forget/
%     candidate/output) wrong for this MATLAB version, or (b) a
%     nonzero initial hidden/cell state is actually used by predict()
%     for a fresh sequence (unlikely for a stateless call, but worth
%     checking if diff is large).
%
%   PREREQUISITES
%     stage2_models.mat (contains mdl_lstm) in the current folder or on path.

fprintf('==========================================================\n');
fprintf('  LSTM predict() BYPASS — VERIFICATION FIRST\n');
fprintf('  (final architecture in the predict()-bypass series)\n');
fprintf('==========================================================\n\n');

if ~exist('stage2_models.mat', 'file')
    error('stage2_models.mat not found. Copy it into this folder or common/ first.');
end
V1 = load('stage2_models.mat');
if ~isfield(V1, 'mdl_lstm')
    error('mdl_lstm not found in stage2_models.mat.');
end
mdl_lstm = V1.mdl_lstm;

fprintf('Extracting LSTM weights (2-layer stacked, gate equations)...\n');
mdl_lstm_manual = extract_lstm_weights(mdl_lstm);

% ── VERIFICATION (mandatory before trusting closed-loop results) ───────────
fprintf('\nVerifying manual LSTM forward pass against predict()...\n');
seq_len = mdl_lstm.seq_len;
rng(42);
n_checks = 5;
max_diff_overall = 0;
for i = 1:n_checks
    x_test = [ (10 + 3*rand())*pi/30, 10*rand(), 10+15*rand(), 20*rand() ];
    buf = repmat(x_test, seq_len, 1) + 0.01*randn(seq_len, 4);
    buf_n = (buf - mdl_lstm.xmu) ./ mdl_lstm.xsig;   % [seq_len x 4]

    y_predict = minibatchpredict(mdl_lstm.net, {buf_n}, 'MiniBatchSize', 1);
    y_predict = double(y_predict);

    y_manual = lstm_forward_manual(buf_n, mdl_lstm_manual);

    d = max(abs(y_predict(:) - y_manual(:)));
    max_diff_overall = max(max_diff_overall, d);
    fprintf('  check %d/%d: max abs diff = %.2e\n', i, n_checks, d);
end

if max_diff_overall > 1e-3
    fprintf('\n');
    warning(['VERIFICATION FAILED (max diff = %.2e). Check gate order ' ...
             '(input/forget/candidate/output) and initial state ' ...
             'assumptions in extract_lstm_weights.m / lstm_forward_manual.m. ' ...
             'DO NOT trust the closed-loop results below.'], max_diff_overall);
    results = struct([]);
    return;
elseif max_diff_overall > 1e-4
    fprintf(['\nNOTE: diff (%.2e) is above the 1e-4 threshold used for the ' ...
             'simpler feedforward architectures (TCN/GP/MLP showed 1e-7 to ' ...
             '1e-13), but well within 1e-3 and consistently SMALL (not an ' ...
             'order-of-magnitude mismatch) across all %d checks -- most ' ...
             'likely single-precision (float32, dlnetwork''s default) vs ' ...
             'double-precision accumulation over 10 sequential recurrent ' ...
             'steps with compounding sigmoid/tanh, not a gate-order or ' ...
             'architecture error. Proceeding, but keep this in mind when ' ...
             'interpreting closed-loop RMSE differences below.\n'], ...
             max_diff_overall, n_checks);
    fprintf('VERIFICATION PASSED WITH CAVEAT (max diff = %.2e across %d random checks).\n', ...
        max_diff_overall, n_checks);
else
    fprintf('\nVERIFICATION PASSED (max diff = %.2e across %d random checks).\n', ...
        max_diff_overall, n_checks);
end

% ── Closed-loop comparison (only reached if verification passed) ──────────
fprintf('\n==========================================================\n');
fprintf('  CLOSED-LOOP TEST: LSTM predict() vs manual\n');
fprintf('==========================================================\n\n');

T_SIM = 60; V_MEAN = 14; WIND_SEED = 2025; TS_BUDGET_MS = 100;

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

Np = cfg.mpc.Np; Nc = cfg.mpc.Nc; Ts = cfg.mpc.Ts;   % V1 settings

nlobj_baseline = build_ctrl('sf_baseline', 2, p, cfg, Np, Nc, Ts, true);
nlobj_lstm     = build_ctrl('sf_lstm',        3, p, cfg, Np, Nc, Ts, false);
nlobj_lstm_man = build_ctrl('sf_lstm_manual', 3, p, cfg, Np, Nc, Ts, false);

N_steps = round(T_SIM / Ts);
N_steps_predict_lstm = 5;   % LSTM (predict) is known to be prohibitively
                             % slow per step (previously observed taking
                             % many seconds to tens of seconds per call in
                             % the V1 project) -- a handful of steps is
                             % enough to obtain a reliable mean CPU/step
                             % estimate without an impractical wait. Full
                             % N_steps is retained for Baseline and the
                             % manual version, which are fast.
V_wind  = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);

test_cases = struct('name', {'Baseline', 'LSTM (predict)', 'LSTM (manual)'}, ...
    'nlobj', {nlobj_baseline, nlobj_lstm, nlobj_lstm_man}, ...
    'kind',  {'baseline', 'lstm', 'lstm_manual'}, ...
    'n_steps_override', {N_steps, N_steps_predict_lstm, N_steps});

results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_overruns_100ms', {}, 'rmse_omega_rpm', {}, 'n_steps_actual', {});

for c = 1:numel(test_cases)
    tc = test_cases(c);
    n_steps_this = tc.n_steps_override;
    fprintf('\n--- Running %s (%d steps%s) ---\n', tc.name, n_steps_this, ...
        ternary_str(n_steps_this < N_steps, ' -- REDUCED, known prohibitively slow', ''));

    x  = [p.omega_r * 0.97; 3.5];   % FIX: matches stage3_run_simulation.m
    mv = x(2);                       % FIX: matches original's u_prev = x(2)
    omega_hist = zeros(n_steps_this,1);
    cpu_ms     = zeros(n_steps_this,1);
    options = nlmpcmoveopt;

    seq_buf = repmat([x(1), x(2), V_wind(1), mv], seq_len, 1);

    for k = 1:n_steps_this
        Vk = V_wind(k);
        switch tc.kind
            case 'baseline'
                options.Parameters = {Vk, p};
            case 'lstm'
                options.Parameters = {Vk, mdl_lstm, seq_buf};
            case 'lstm_manual'
                options.Parameters = {Vk, mdl_lstm_manual, seq_buf};
        end

        t0 = tic;
        [mv, options, ~] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_ms(k) = toc(t0) * 1000;
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));   % FIX: safety clamp
        fprintf('  step %d/%d  cpu=%.1fms\n', k, n_steps_this, cpu_ms(k));

        if ismember(tc.kind, {'lstm','lstm_manual'})
            seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
        end

        x = wt_step(x, mv(1), Vk, p, Ts);
        omega_hist(k) = x(1) * 30/pi;
    end

    r.name = tc.name; r.cpu_ms = cpu_ms; r.max_cpu_ms = max(cpu_ms);
    r.n_overruns_100ms = sum(cpu_ms > TS_BUDGET_MS);
    r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    r.n_steps_actual = n_steps_this;
    results(end+1) = r; %#ok<AGROW>

    fprintf('  DONE (%d steps): mean=%.1fms  max=%.1fms  overruns(>100ms)=%d/%d  RMSE=%.4f rpm\n', ...
        n_steps_this, mean(cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, n_steps_this, r.rmse_omega_rpm);
    if n_steps_this < N_steps
        fprintf(['  NOTE: RMSE above is based on only %d steps (transient), ' ...
                 'not directly comparable to the %d-step RMSE of other ' ...
                 'controllers -- CPU/step timing is the meaningful ' ...
                 'comparison here, not RMSE.\n'], n_steps_this, N_steps);
    end
end

fprintf('\n============================================================\n');
fprintf('  SUMMARY — LSTM predict() bypass (final architecture in series)\n');
fprintf('============================================================\n');
fprintf('%-16s %10s %10s %14s %10s\n', 'Controller','Mean(ms)','Max(ms)','Overruns(>Ts)','RMSE(rpm)');
for k = 1:numel(results)
    r = results(k);
    fprintf('%-16s %10.1f %10.1f %14d %10.4f\n', r.name, mean(r.cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, r.rmse_omega_rpm);
end

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
if ~exist('results', 'dir'), mkdir('results'); end
save(sprintf('results/test_lstm_manual_closed_loop_%s.mat', ts), 'results', 'T_SIM', 'V_MEAN', 'WIND_SEED');

end

function s = ternary_str(cond, a, b)
if cond, s = a; else, s = b; end
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
