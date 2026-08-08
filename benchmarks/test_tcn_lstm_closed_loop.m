function test_results = test_tcn_lstm_closed_loop()
% TEST_TCN_LSTM_CLOSED_LOOP  Short closed-loop test isolating TCN and LSTM
% controllers, to check whether the residual JIT/tracing spikes found by
% benchmark_surrogate_latency.m (TCN: 2/250 calls >50ms, max 147.57ms;
% LSTM: 4/250 calls >50ms, max 321.82ms) actually disrupt the nlmpc SQP
% solve in closed loop, or are negligible in practice on this MATLAB
% version.
%
%   test_results = test_tcn_lstm_closed_loop()
%
%   RATIONALE
%     benchmark_surrogate_latency.m only measured isolated forward-pass
%     inference. The nlmpc SQP solver also needs gradients at every
%     iteration (dlgradient), which is documented as the more likely
%     source of JIT tracing cost. This script runs a SHORT (30s) closed
%     loop simulation to observe per-step CPU time under real SQP
%     conditions, without paying for the full 120s Stage 3 protocol.
%
%   SCOPE — TCN and LSTM ONLY
%     SW-MLP and PINN-v2 showed 0/250 spikes in the isolated benchmark
%     and are not retested here (time-constrained trial license).
%     Baseline is included as a fast reference for comparison.
%
%   ASSUMPTIONS — PLEASE VERIFY BEFORE RUNNING
%     wt_step(x,u,V,p,dt) and kaimal_wind(V_mean,T_sim,dt,seed) signatures
%     are now CONFIRMED from direct file review. Remaining assumption:
%     this script does NOT reproduce stage3_run_simulation_v2's exact
%     buffer-update order for TCN/SW-MLP (mdl.seq_buf update before vs.
%     after nlmpcmove) — verify against that file if you have it; a
%     mismatch there would affect surrogate accuracy only mildly, not
%     the timing measurements this test is designed to produce.
%
%   OUTPUT
%     test_results  struct array (one per controller) with fields:
%       name, cpu_ms (1xN_steps), max_cpu_ms, n_spikes_50ms,
%       n_spikes_100ms (exceeds Ts budget), max_iter_hits (solver
%       returned without converging), rmse_omega_rpm
%     Also saved to test_tcn_lstm_closed_loop_<timestamp>.mat

%% ── Configuration ────────────────────────────────────────────────────────
T_SIM      = 30;      % seconds — short test, not full 120s Stage 3 protocol
V_MEAN     = 14;       % m/s, matches Stage 3 V1/V2 reference condition
WIND_SEED  = 2025;     % matches stage0_config.m mpc.wind_seed
SPIKE_MS   = 50;       % same threshold as isolated benchmark
TS_BUDGET_MS = 100;    % Ts=0.1s -> a step exceeding this overruns real-time

fprintf('==========================================================\n');
fprintf('  TCN / LSTM CLOSED-LOOP SPIKE TEST (%ds, V=%dm/s)\n', T_SIM, V_MEAN);
fprintf('  MATLAB version: %s\n', version);
fprintf('==========================================================\n\n');

%% ── Load config, plant params, models ───────────────────────────────────
cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;   % sf_baseline.m uses p.dt internally (confirmed by error report)

V1 = load('stage2_models.mat');
V2 = load('stage2_models_v2.mat');

if ~isfield(V1, 'mdl_lstm')
    warning('mdl_lstm not found in stage2_models.mat — LSTM test skipped.');
end

%% ── Build controllers ────────────────────────────────────────────────────
% TCN: use V2 controller design (Np=20, Nc=6, per stage3_design_controllers_v2.m)
models_v2.llnfm   = V2.mdl_llnfm;
models_v2.tcn     = V2.mdl_tcn;
models_v2.swmlp   = V2.mdl_swmlp;
models_v2.gp_v2   = V2.mdl_gp_v2;
models_v2.pinn_v2 = V2.mdl_pinn_v2;
controllers_v2 = stage3_design_controllers_v2(p, models_v2, cfg);

% LSTM and Baseline: use V1 controller design (Np=10, Nc=4, per
% stage3_design_controllers.m)
models_v1.llnfm = V1.mdl_llnfm;
models_v1.lstm  = V1.mdl_lstm;
models_v1.gp    = V1.mdl_gp;
models_v1.pinn  = V1.mdl_pinn;
controllers_v1 = stage3_design_controllers(p, models_v1, cfg);

%% ── Wind profile (shared across all controllers) ────────────────────────
N_steps = round(T_SIM / cfg.mpc.Ts);
% kaimal_wind(V_mean, T_sim, dt, seed) -> V_t is [N x 1], N = round(T_sim/dt)
V_wind = kaimal_wind(V_MEAN, T_SIM, cfg.mpc.Ts, WIND_SEED);

%% ── Define test cases ────────────────────────────────────────────────────
test_cases = struct('name', {}, 'nlobj', {}, 'seq_len', {}, 'is_tcn', {}, 'is_lstm', {});
test_cases(end+1) = struct('name','Baseline','nlobj',controllers_v1.baseline, ...
    'seq_len',0,'is_tcn',false,'is_lstm',false);
if isfield(controllers_v2, 'tcn')
    test_cases(end+1) = struct('name','TCN (V2)','nlobj',controllers_v2.tcn, ...
        'seq_len',V2.mdl_tcn.seq_len,'is_tcn',true,'is_lstm',false);
end
if isfield(V1, 'mdl_lstm') && isfield(controllers_v1, 'lstm')
    test_cases(end+1) = struct('name','LSTM (V1)','nlobj',controllers_v1.lstm, ...
        'seq_len',10,'is_tcn',false,'is_lstm',true);
end

%% ── Run each controller ──────────────────────────────────────────────────
test_results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_spikes_50ms', {}, 'n_spikes_100ms', {}, 'max_iter_hits', {}, ...
    'rmse_omega_rpm', {});

for c = 1:numel(test_cases)
    tc = test_cases(c);
    fprintf('\n--- Running %s (%d steps) ---\n', tc.name, N_steps);

    x  = [p.omega_r; 0];         % initial state: [omega_r rad/s; beta deg]
    u  = 0;                       % initial pitch command
    mv = u;
    omega_hist = zeros(N_steps,1);
    cpu_ms     = zeros(N_steps,1);
    max_iter_hits = 0;

    % Sliding buffer for TCN/LSTM, initialised to steady-state repeat
    if tc.seq_len > 0
        seq_buf = repmat([x(1), x(2), V_wind(1), u], tc.seq_len, 1);
    end

    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);

        if tc.is_tcn
            % TCN buffer embedded in mdl — update before solve
            models_v2.tcn.seq_buf = seq_buf;
            options.Parameters = {Vk, models_v2.tcn};
            t0 = tic;
            [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
            cpu_ms(k) = toc(t0) * 1000;
            seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];

        elseif tc.is_lstm
            options.Parameters = {Vk, models_v1.lstm, seq_buf};
            t0 = tic;
            [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
            cpu_ms(k) = toc(t0) * 1000;
            seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];

        else % Baseline
            options.Parameters = {Vk, p};
            t0 = tic;
            [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
            cpu_ms(k) = toc(t0) * 1000;
        end

        if isfield(info, 'ExitFlag') && info.ExitFlag <= 0
            max_iter_hits = max_iter_hits + 1;
        end

        % Advance true plant one step — wt_step(x, u, V, p, dt), dt explicit
        x = wt_step(x, mv(1), Vk, p, cfg.mpc.Ts);
        omega_hist(k) = x(1) * 30/pi;  % rad/s -> rpm

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
fprintf('  CLOSED-LOOP SPIKE TEST SUMMARY (%ds, MATLAB %s)\n', T_SIM, version);
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
fprintf(['Reference (R2024a, stage3_v2.txt): TCN excluded from Stage 3 due\n' ...
         'to JIT spikes up to 2572 ms/call. Overruns(>Ts) above > 0 would\n' ...
         'indicate the same practical failure mode persists on this version;\n' ...
         '0 overruns with a low mean/max would support that the R2024a\n' ...
         'incompatibility is version-specific.\n']);

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
outfile = sprintf('test_tcn_lstm_closed_loop_%s.mat', ts);
save(outfile, 'test_results', 'T_SIM', 'V_MEAN', 'WIND_SEED');
fprintf('\nResults saved to %s\n', outfile);

end
