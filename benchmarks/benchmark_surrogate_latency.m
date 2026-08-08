function results = benchmark_surrogate_latency()
% BENCHMARK_SURROGATE_LATENCY  Isolate per-call inference latency of each
% ML surrogate state function, replicating how nlmpc's SQP solver calls
% them repeatedly with varying inputs during a single control step.
%
%   results = benchmark_surrogate_latency()
%
%   PURPOSE
%     In R2024a, TCN/SW-MLP/PINN-v2/LSTM state functions showed
%     non-deterministic JIT recompilation spikes when called repeatedly
%     inside nlmpc's SQP solve (documented in stage3_v2.txt / journal
%     draft: TCN up to 2572 ms/call, SW-MLP up to 468 ms/call, PINN-v2
%     up to 420 ms/call, LSTM ~180 ms/call isolated). This script isolates
%     ONLY the state-function call cost, OUTSIDE of nlmpc, on the CURRENT
%     MATLAB version, so we can check whether the same spikes reproduce
%     without paying for a full Stage 3 closed-loop re-run.
%
%   METHODOLOGY
%     1. Load stage2_models.mat (V1) and stage2_models_v2.mat (V2).
%     2. For each surrogate, build a "warm-up" call (any JIT/trace
%        compilation happens here) — timed separately, NOT counted in
%        the main statistics.
%     3. Call the state function N_CALLS times with DIFFERENT random
%        inputs each time (drawn from the Stage 1 training domain),
%        mimicking nlmpc's SQP solver evaluating the state function at a
%        DIFFERENT predicted state/input pair at every iteration and
%        every horizon step — this varying-input pattern is what
%        triggers retracing in R2024a, as opposed to calling the same
%        input repeatedly (which would just hit a cache).
%     4. Record wall-clock time per call (tic/toc); report min/median/
%        mean/p95/max, and flag calls exceeding SPIKE_THRESHOLD_MS.
%
%   OUTPUTS
%     results  struct array, one entry per surrogate, with fields:
%       name, warmup_ms, times_ms (1xN_CALLS), min_ms, median_ms,
%       mean_ms, p95_ms, max_ms, n_spikes, spike_threshold_ms
%     Also saved to benchmark_surrogate_latency_<timestamp>.mat and
%     printed as a summary table.
%
%   PREREQUISITES
%     Run from the project folder containing:
%       stage2_models.mat, stage2_models_v2.mat
%       sf_llnfm.m, sf_lstm.m, sf_gp.m, sf_pinn.m, sf_tcn.m, sf_swmlp.m
%     Confirmed variable names (from stage2_main_v2.m and direct
%     inspection of stage2_models_v2.mat):
%       V2: mdl_persist, mdl_linear, mdl_llnfm, mdl_tcn, mdl_swmlp,
%           mdl_gp_v2, mdl_pinn_v2
%       V1: mdl_llnfm, mdl_lstm, mdl_gp, mdl_pinn (mdl_persist, mdl_linear)
%
%   NOTE ON seq_buf (TCN, SW-MLP, LSTM)
%     mdl_tcn and mdl_swmlp do NOT carry mdl.seq_buf in the saved .mat —
%     per sf_tcn.m/sf_swmlp.m header comments, this buffer is initialised
%     and updated externally by stage3_run_simulation_v2. This script
%     initialises a plausible seq_buf here so the state functions can be
%     called in isolation. sf_lstm.m instead takes seq_buf as an explicit
%     3rd argument (NumberOfParameters=3 in V1), passed directly rather
%     than embedded in mdl.

%% ── Configuration ────────────────────────────────────────────────────────
N_CALLS             = 250;   % matches documented worst-case SQP evals/step
SPIKE_THRESHOLD_MS  = 50;    % ms; for Ts=0.1s (100ms), a call this size
                              % already eats half the per-step budget
rng(7);                       % reproducible random test points

% Domain bounds for generating realistic random test inputs
% [omega_r (rpm), beta (deg), V (m/s), u_cmd (deg)] — from stage1_validate.txt
omega_range = [8.0, 13.31];
beta_range  = [0.0, 25.0];
V_range     = [7.85, 25.0];
u_range     = [0.0, 25.0];

gen_input = @() [ ...
    (omega_range(1) + diff(omega_range)*rand()) * pi/30, ... % rad/s
    beta_range(1)  + diff(beta_range)*rand(), ...            % deg
    V_range(1)     + diff(V_range)*rand(), ...                % m/s
    u_range(1)     + diff(u_range)*rand() ];                  % deg

%% ── Load models ───────────────────────────────────────────────────────────
fprintf('Loading Stage 2 V1 and V2 models...\n');
if ~exist('stage2_models.mat', 'file')
    error('stage2_models.mat not found in current folder.');
end
if ~exist('stage2_models_v2.mat', 'file')
    error('stage2_models_v2.mat not found in current folder.');
end
V1 = load('stage2_models.mat');
V2 = load('stage2_models_v2.mat');

omega_ref_radps = 12.1 * pi/30;  % rated speed, for sf_gp's unused params
kappa_default   = 0.8;

% Buffer format: [seq_len x 4] = [omega_r, beta, V_wind, u_cmd], chronological
make_seq_buf = @(seq_len) repmat(gen_input(), seq_len, 1);

%% ── Define surrogates to benchmark ───────────────────────────────────────
% Each call_fcn takes NO arguments and performs ONE full state-function
% call with a freshly generated random input (input generation is cheap
% relative to inference, so including it does not bias the comparison).
surrogates = struct('name', {}, 'call_fcn', {});

if isfield(V1, 'mdl_llnfm')
    mdl = V1.mdl_llnfm;
    surrogates(end+1) = struct('name', 'LLNFM (V1)', 'call_fcn', ...
        @() call_2p(@sf_llnfm, gen_input(), mdl));
end

if isfield(V1, 'mdl_lstm')
    mdl = V1.mdl_lstm;
    seq_len = 10;  % ml.lstm.seq_len in stage0_config.m
    buf0 = make_seq_buf(seq_len);
    surrogates(end+1) = struct('name', 'LSTM (V1)', 'call_fcn', ...
        @() call_lstm(mdl, buf0, gen_input()));
else
    warning('mdl_lstm not found in stage2_models.mat — skipping LSTM.');
end

if isfield(V1, 'mdl_gp')
    mdl = V1.mdl_gp;
    surrogates(end+1) = struct('name', 'GP (V1)', 'call_fcn', ...
        @() call_gp(mdl, omega_ref_radps, kappa_default, gen_input()));
end

if isfield(V1, 'mdl_pinn')
    mdl = V1.mdl_pinn;
    surrogates(end+1) = struct('name', 'PINN (V1)', 'call_fcn', ...
        @() call_2p(@sf_pinn, gen_input(), mdl));
end

if isfield(V2, 'mdl_tcn')
    mdl = V2.mdl_tcn;
    mdl.seq_buf = make_seq_buf(mdl.seq_len);
    surrogates(end+1) = struct('name', 'TCN (V2)', 'call_fcn', ...
        @() call_2p(@sf_tcn, gen_input(), mdl));
end

if isfield(V2, 'mdl_swmlp')
    mdl = V2.mdl_swmlp;
    mdl.seq_buf = make_seq_buf(mdl.seq_len);
    surrogates(end+1) = struct('name', 'SW-MLP (V2)', 'call_fcn', ...
        @() call_2p(@sf_swmlp, gen_input(), mdl));
end

if isfield(V2, 'mdl_gp_v2')
    mdl = V2.mdl_gp_v2;
    surrogates(end+1) = struct('name', 'GP-v2 (V2)', 'call_fcn', ...
        @() call_gp(mdl, omega_ref_radps, kappa_default, gen_input()));
end

if isfield(V2, 'mdl_pinn_v2')
    mdl = V2.mdl_pinn_v2;
    % sf_pinn.m is used for both PINN (V1) and PINN-v2 (V2) — only mdl.net differs
    surrogates(end+1) = struct('name', 'PINN-v2 (V2)', 'call_fcn', ...
        @() call_2p(@sf_pinn, gen_input(), mdl));
end

if isempty(surrogates)
    error('No surrogate models found — check stage2_models.mat / stage2_models_v2.mat contents.');
end

%% ── Benchmark loop ────────────────────────────────────────────────────────
results = struct('name', {}, 'warmup_ms', {}, 'times_ms', {}, ...
    'min_ms', {}, 'median_ms', {}, 'mean_ms', {}, 'p95_ms', {}, ...
    'max_ms', {}, 'n_spikes', {}, 'spike_threshold_ms', {});

for k = 1:numel(surrogates)
    name = surrogates(k).name;
    fcn  = surrogates(k).call_fcn;
    fprintf('\n[%d/%d] Benchmarking %s ...\n', k, numel(surrogates), name);

    % ── Warm-up call (not counted in statistics) ──────────────────────────
    t0 = tic;
    try
        xnext = fcn(); %#ok<NASGU>
    catch ME
        warning('Warm-up call failed for %s: %s', name, ME.message);
        continue;
    end
    warmup_ms = toc(t0) * 1000;
    fprintf('    Warm-up call: %.2f ms\n', warmup_ms);

    % ── Timed calls with DIFFERENT random inputs each time ────────────────
    times_ms = zeros(1, N_CALLS);
    for i = 1:N_CALLS
        t = tic;
        xnext = fcn(); %#ok<NASGU>
        times_ms(i) = toc(t) * 1000;
    end

    % ── Statistics ─────────────────────────────────────────────────────────
    r.name               = name;
    r.warmup_ms          = warmup_ms;
    r.times_ms           = times_ms;
    r.min_ms             = min(times_ms);
    r.median_ms          = median(times_ms);
    r.mean_ms            = mean(times_ms);
    r.p95_ms             = prctile(times_ms, 95);
    r.max_ms             = max(times_ms);
    r.n_spikes           = sum(times_ms > SPIKE_THRESHOLD_MS);
    r.spike_threshold_ms = SPIKE_THRESHOLD_MS;
    results(end+1) = r; %#ok<AGROW>

    fprintf(['    min=%.2fms  median=%.2fms  mean=%.2fms  p95=%.2fms  ' ...
              'max=%.2fms  spikes(>%.0fms)=%d/%d\n'], ...
        r.min_ms, r.median_ms, r.mean_ms, r.p95_ms, r.max_ms, ...
        SPIKE_THRESHOLD_MS, r.n_spikes, N_CALLS);
end

%% ── Summary table ────────────────────────────────────────────────────────
fprintf('\n============================================================\n');
fprintf('  SURROGATE LATENCY BENCHMARK SUMMARY\n');
fprintf('  MATLAB version: %s\n', version);
fprintf('============================================================\n');
fprintf('%-14s %8s %8s %8s %8s %8s %10s\n', ...
    'Model', 'Warmup', 'Min', 'Median', 'P95', 'Max', 'Spikes');
fprintf('%-14s %8s %8s %8s %8s %8s %10s\n', ...
    '', '(ms)', '(ms)', '(ms)', '(ms)', '(ms)', sprintf('(>%dms)', SPIKE_THRESHOLD_MS));
fprintf('------------------------------------------------------------\n');
for k = 1:numel(results)
    r = results(k);
    fprintf('%-14s %8.2f %8.2f %8.2f %8.2f %8.2f %6d/%-3d\n', ...
        r.name, r.warmup_ms, r.min_ms, r.median_ms, r.p95_ms, r.max_ms, ...
        r.n_spikes, N_CALLS);
end
fprintf('============================================================\n');
fprintf(['Reference (R2024a, documented in stage3_v2.txt / stage3_design\n' ...
         '_controllers.txt): TCN up to 2572 ms/call, SW-MLP up to 468 ms/\n' ...
         'call, PINN-v2 up to 420 ms/call, LSTM ~180 ms/call isolated.\n']);
fprintf(['Compare max_ms / n_spikes above against these R2024a figures.\n' ...
         'If spikes are gone (max_ms comparable to median_ms, n_spikes=0),\n' ...
         'this is evidence the R2024a-specific JIT/dlarray issue does not\n' ...
         'reproduce on this MATLAB version.\n']);

%% ── Save results ──────────────────────────────────────────────────────────
ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
outfile = sprintf('benchmark_surrogate_latency_%s.mat', ts);
save(outfile, 'results', 'N_CALLS', 'SPIKE_THRESHOLD_MS');
fprintf('\nResults saved to %s\n', outfile);

end


% ============================================================================
% Local helper functions — split a 4-element [omega,beta,V,u] input vector
% into the (x, u, V) arguments expected by each sf_*.m state function.
% ============================================================================

function xnext = call_2p(sf_handle, inp, mdl)
% For sf_llnfm, sf_pinn, sf_tcn, sf_swmlp — all have signature (x,u,V,mdl)
x = [inp(1), inp(2)];
u = inp(4);
V = inp(3);
xnext = sf_handle(x, u, V, mdl);
end

function xnext = call_gp(mdl, omega_ref, kappa, inp)
% sf_gp has signature (x,u,V,mdl,omega_ref,kappa)
x = [inp(1), inp(2)];
u = inp(4);
V = inp(3);
xnext = sf_gp(x, u, V, mdl, omega_ref, kappa);
end

function xnext = call_lstm(mdl, seq_buf, inp)
% sf_lstm has signature (x,u,V,mdl,seq_buf)
x = [inp(1), inp(2)];
u = inp(4);
V = inp(3);
xnext = sf_lstm(x, u, V, mdl, seq_buf);
end
