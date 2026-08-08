function test_results = test_remaining_surrogates_closed_loop()
% TEST_REMAINING_SURROGATES_CLOSED_LOOP  Short closed-loop test for the
% surrogates NOT yet tested in full closed loop on this MATLAB version:
% SW-MLP and PINN-v2 (0/250 spikes in isolated inference benchmark —
% unlike TCN/LSTM, which showed catastrophic closed-loop spikes despite
% a clean isolated benchmark). GP-v2 is included too since it is already
% known feasible from prior R2024a runs (stage3_v2.txt) and provides a
% same-run reference point on this machine/version.
%
%   test_results = test_remaining_surrogates_closed_loop()
%
%   RATIONALE
%     test_tcn_lstm_closed_loop.m showed that isolated inference latency
%     (benchmark_surrogate_latency.m) is NOT a reliable predictor of
%     closed-loop SQP feasibility: TCN had 2/250 isolated spikes but
%     300/300 closed-loop spikes (mean 1173ms/step, max 7688ms/step).
%     This script checks whether SW-MLP and PINN-v2 — which showed 0/250
%     isolated spikes — hold up under the same real SQP+gradient
%     conditions, or suffer the same hidden gradient-tracing cost.
%
%   SCOPE
%     SW-MLP (V2), PINN-v2 (V2), GP-v2 (V2) only. Baseline, TCN, LSTM
%     already tested by test_tcn_lstm_closed_loop.m — not repeated here.
%
%   NOTE ON V2 HORIZON SETTINGS
%     stage3_design_controllers_v2.m docstring claims Np=20, Nc=6, but
%     the ACTUAL runtime print in the previous test showed Np=15, Nc=1
%     (from cfg.mpc2 in stage0_config.m) — the docstring is stale. This
%     script uses whatever cfg.mpc2 currently resolves to and PRINTS it,
%     so the true values used are always visible in the console output
%     rather than trusted from any comment.
%
%   OUTPUT
%     test_results  struct array (one per controller), same fields as
%     test_tcn_lstm_closed_loop.m. Saved to
%     test_remaining_surrogates_closed_loop_<timestamp>.mat

%% ── Configuration ────────────────────────────────────────────────────────
T_SIM        = 30;
V_MEAN       = 14;
WIND_SEED    = 2025;
SPIKE_MS     = 50;
TS_BUDGET_MS = 100;

fprintf('==========================================================\n');
fprintf('  REMAINING SURROGATES CLOSED-LOOP TEST (%ds, V=%dm/s)\n', T_SIM, V_MEAN);
fprintf('  MATLAB version: %s\n', version);
fprintf('==========================================================\n\n');

%% ── Load config, plant params, models ───────────────────────────────────
cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;   % sf_baseline.m uses p.dt internally

V2 = load('stage2_models_v2.mat');

models_v2.llnfm   = V2.mdl_llnfm;
models_v2.tcn     = V2.mdl_tcn;
models_v2.swmlp   = V2.mdl_swmlp;
models_v2.gp_v2   = V2.mdl_gp_v2;
models_v2.pinn_v2 = V2.mdl_pinn_v2;
controllers_v2 = stage3_design_controllers_v2(p, models_v2, cfg);

fprintf('\n  ACTUAL V2 horizon settings used: Np=%d  Nc=%d  Ts=%.2f\n', ...
    cfg.mpc2.Np, cfg.mpc2.Nc, cfg.mpc2.Ts);
fprintf('  (Note: stage3_design_controllers_v2.m docstring says Np=20,\n');
fprintf('   Nc=6 — verify which is correct for the paper against this\n');
fprintf('   printed value, not the docstring.)\n\n');

%% ── Wind profile ─────────────────────────────────────────────────────────
N_steps = round(T_SIM / cfg.mpc.Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, cfg.mpc.Ts, WIND_SEED);

%% ── Define test cases ────────────────────────────────────────────────────
test_cases = struct('name', {}, 'nlobj', {}, 'kind', {}, 'seq_len', {});
test_cases(end+1) = struct('name','SW-MLP (V2)','nlobj',controllers_v2.swmlp, ...
    'kind','swmlp','seq_len',V2.mdl_swmlp.seq_len);
test_cases(end+1) = struct('name','PINN-v2 (V2)','nlobj',controllers_v2.pinn_v2, ...
    'kind','pinn_v2','seq_len',0);
test_cases(end+1) = struct('name','GP-v2 (V2)','nlobj',controllers_v2.gp_v2, ...
    'kind','gp_v2','seq_len',0);

%% ── Run each controller ──────────────────────────────────────────────────
test_results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_spikes_50ms', {}, 'n_spikes_100ms', {}, 'max_iter_hits', {}, ...
    'rmse_omega_rpm', {});

omega_ref_radps = 12.1 * pi/30;
kappa_default   = cfg.mpc.kappa;

for c = 1:numel(test_cases)
    tc = test_cases(c);
    fprintf('\n--- Running %s (%d steps) ---\n', tc.name, N_steps);

    x  = [p.omega_r; 0];
    mv = 0;
    omega_hist = zeros(N_steps,1);
    cpu_ms     = zeros(N_steps,1);
    max_iter_hits = 0;

    if tc.seq_len > 0
        seq_buf = repmat([x(1), x(2), V_wind(1), mv], tc.seq_len, 1);
    end

    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);

        switch tc.kind
            case 'swmlp'
                models_v2.swmlp.seq_buf = seq_buf;
                options.Parameters = {Vk, models_v2.swmlp};
                t0 = tic;
                [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
                cpu_ms(k) = toc(t0) * 1000;
                seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];

            case 'pinn_v2'
                options.Parameters = {Vk, models_v2.pinn_v2};
                t0 = tic;
                [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
                cpu_ms(k) = toc(t0) * 1000;

            case 'gp_v2'
                options.Parameters = {Vk, models_v2.gp_v2, omega_ref_radps, kappa_default};
                t0 = tic;
                [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
                cpu_ms(k) = toc(t0) * 1000;
        end

        if isfield(info, 'ExitFlag') && info.ExitFlag <= 0
            max_iter_hits = max_iter_hits + 1;
        end

        x = wt_step(x, mv(1), Vk, p, cfg.mpc.Ts);
        omega_hist(k) = x(1) * 30/pi;

        if mod(k, 50) == 0
            fprintf('  step %d/%d  cpu=%.1fms  omega=%.2f rpm\n', ...
                k, N_steps, cpu_ms(k), omega_hist(k));
        end
    end

    r.name           = tc.name;
    r.cpu_ms         = cpu_ms;
    r.max_cpu_ms     = max(cpu_ms);
    r.n_spikes_50ms  = sum(cpu_ms > SPIKE_MS);
    r.n_spikes_100ms = sum(cpu_ms > TS_BUDGET_MS);
    r.max_iter_hits  = max_iter_hits;
    r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    test_results(end+1) = r; %#ok<AGROW>

    fprintf(['  DONE: mean=%.1fms  max=%.1fms  spikes(>50ms)=%d/%d  ' ...
             'overruns(>100ms budget)=%d/%d  RMSE=%.3f rpm\n'], ...
        mean(cpu_ms), r.max_cpu_ms, r.n_spikes_50ms, N_steps, ...
        r.n_spikes_100ms, N_steps, r.rmse_omega_rpm);
end

%% ── Summary ───────────────────────────────────────────────────────────────
fprintf('\n============================================================\n');
fprintf('  REMAINING SURROGATES — CLOSED-LOOP SUMMARY (%ds, MATLAB %s)\n', T_SIM, version);
fprintf('============================================================\n');
fprintf('%-14s %10s %10s %14s %10s\n', ...
    'Controller', 'Mean(ms)', 'Max(ms)', 'Overruns(>Ts)', 'RMSE(rpm)');
fprintf('------------------------------------------------------------\n');
for k = 1:numel(test_results)
    r = test_results(k);
    fprintf('%-14s %10.1f %10.1f %14d %10.3f\n', ...
        r.name, mean(r.cpu_ms), r.max_cpu_ms, r.n_spikes_100ms, r.rmse_omega_rpm);
end
fprintf('============================================================\n');
fprintf(['Reference from test_tcn_lstm_closed_loop.m (this machine):\n' ...
         '  TCN:  mean=1173.5ms  max=7688.2ms  overruns=300/300\n' ...
         '  If SW-MLP/PINN-v2 show near-zero overruns here, that is\n' ...
         '  evidence their isolated-benchmark cleanliness DOES carry\n' ...
         '  over to full closed-loop SQP, unlike TCN/LSTM.\n']);

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
outfile = sprintf('test_remaining_surrogates_closed_loop_%s.mat', ts);
save(outfile, 'test_results', 'T_SIM', 'V_MEAN', 'WIND_SEED');
fprintf('\nResults saved to %s\n', outfile);

end
