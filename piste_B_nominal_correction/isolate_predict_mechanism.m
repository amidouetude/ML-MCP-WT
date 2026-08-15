function results = isolate_predict_mechanism()
% ISOLATE_PREDICT_MECHANISM  Isolate the mechanism behind predict()'s
% per-call overhead (reproducibility review, item 2.2). Tests the SAME
% trained network under 5 conditions to determine whether the overhead
% is caused by JIT/trace recompilation (input-dependent), dlarray
% object construction (per-call allocation), or predict()'s own
% dispatch/validation overhead (architecture-independent of input).
%
%   results = isolate_predict_mechanism()
%
%   CONDITIONS TESTED (TCN, representative dlarray-based architecture)
%     (1) IDENTICAL   -- predict() called 250x with the EXACT SAME input
%                        every time. If JIT/trace recompilation were the
%                        cause, this condition should be FAST after the
%                        first call (the trace is cached and reused for
%                        an identical input).
%     (2) RANDOMIZED  -- predict() called 250x with a freshly randomized
%                        input each time (matches SQP's actual usage
%                        pattern, probing different state/input pairs).
%                        If (1) and (2) show EQUAL cost, JIT/trace
%                        recompilation is NOT the mechanism (a cached
%                        trace would make (1) faster than (2)).
%     (3) BATCH       -- predict() called ONCE on a batch of 250 stacked
%                        randomized inputs, cost divided by 250 for a
%                        per-call-equivalent. Isolates whether per-call
%                        dispatch overhead (amortized away in a single
%                        batched call) is the cost driver.
%     (4) PRE_BUILT   -- predict() called 250x with a randomized input,
%                        but the dlarray object is pre-allocated ONCE
%                        outside the timed loop and only its VALUES are
%                        updated in place each call (isolates dlarray
%                        object CONSTRUCTION cost from predict() itself).
%     (5) MANUAL      -- the verified manual forward pass (no predict(),
%                        no dlarray at all), the established baseline.
%
%   INTERPRETATION LOGIC
%     If cost(1) approx= cost(2): recompilation is NOT the mechanism
%     If cost(3)/250 << cost(2): per-call dispatch overhead IS a major
%       driver (amortized away when batched)
%     If cost(4) approx= cost(2): dlarray construction is NOT the driver
%       (cost persists even with a pre-built object)
%     cost(5) is the floor -- whatever gap remains between the fastest
%     predict()-based condition and (5) is predict()'s own irreducible
%     dispatch/validation overhead.
%
%   OUTPUT
%     results/isolate_predict_mechanism_results.txt

fprintf('==========================================================\n');
fprintf('  ISOLATING THE predict() OVERHEAD MECHANISM (item 2.2)\n');
fprintf('  Architecture: TCN (representative dlarray-based surrogate)\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'isolate_predict_mechanism_results.txt');

V2 = load('stage2_models_v2.mat');
mdl_tcn = V2.mdl_tcn;
net = mdl_tcn.net;
seq_len = mdl_tcn.seq_len;
xmu = mdl_tcn.xmu; xsig = mdl_tcn.xsig;

N_CALLS = 250;
rng(7);   % fixed seed for the randomized conditions, for reproducibility

% ── Helper: build one randomized normalized input window [seq_len x 4] ──────
gen_input = @() (rand(seq_len,4) .* [5, 25, 20, 25] - [0, 0, 0, 0] + ...
                 [8*pi/30, 0, 5, 0] - xmu) ./ xsig;

% ── Condition 1: IDENTICAL input repeated ───────────────────────────────────
fprintf('--- Condition 1: IDENTICAL input repeated ---\n');
x_fixed = gen_input();
X_dl_fixed = dlarray(reshape(x_fixed', 4, seq_len, 1), 'CTB');
t1 = zeros(N_CALLS,1);
for i = 1:N_CALLS
    t0 = tic;
    y = predict(net, X_dl_fixed);
    t1(i) = toc(t0)*1000;
end
fprintf('  median=%.3fms  mean=%.3fms  max=%.3fms\n', median(t1), mean(t1), max(t1));

% ── Condition 2: RANDOMIZED input each call ─────────────────────────────────
fprintf('--- Condition 2: RANDOMIZED input each call ---\n');
t2 = zeros(N_CALLS,1);
for i = 1:N_CALLS
    x_i = gen_input();
    X_dl = dlarray(reshape(x_i', 4, seq_len, 1), 'CTB');
    t0 = tic;
    y = predict(net, X_dl);
    t2(i) = toc(t0)*1000;
end
fprintf('  median=%.3fms  mean=%.3fms  max=%.3fms\n', median(t2), mean(t2), max(t2));

% ── Condition 3: BATCH (single call, 250 stacked inputs) ────────────────────
fprintf('--- Condition 3: BATCH (one call, 250 stacked inputs) ---\n');
X_batch = zeros(4, seq_len, N_CALLS);
for i = 1:N_CALLS
    x_i = gen_input();
    X_batch(:,:,i) = x_i';
end
X_dl_batch = dlarray(X_batch, 'CTB');
t0 = tic;
y_batch = predict(net, X_dl_batch);
t3_total = toc(t0)*1000;
t3_per_call = t3_total / N_CALLS;
fprintf('  total=%.3fms for %d calls -> per-call equivalent=%.4fms\n', t3_total, N_CALLS, t3_per_call);

% ── Condition 4: PRE_BUILT dlarray object, values updated in place ─────────
fprintf('--- Condition 4: PRE-BUILT dlarray, values updated in place ---\n');
X_dl_prebuilt = dlarray(zeros(4, seq_len, 1), 'CTB');
t4 = zeros(N_CALLS,1);
for i = 1:N_CALLS
    x_i = gen_input();
    vals = x_i';   % [4 x seq_len]
    X_dl_prebuilt(:) = vals(:);   % linear-index update, avoids CTB
    % 3-D paren-assignment ambiguity that crashed the original version
    t0 = tic;
    y = predict(net, X_dl_prebuilt);
    t4(i) = toc(t0)*1000;
end
fprintf('  median=%.3fms  mean=%.3fms  max=%.3fms\n', median(t4), mean(t4), max(t4));

% ── Condition 5: MANUAL forward pass (verified, no predict()) ──────────────
fprintf('--- Condition 5: MANUAL forward pass (no predict()) ---\n');
mdl_manual = extract_tcn_weights(mdl_tcn);
t5 = zeros(N_CALLS,1);
for i = 1:N_CALLS
    x_i = gen_input();
    t0 = tic;
    y = tcn_forward_manual(x_i', mdl_manual);
    t5(i) = toc(t0)*1000;
end
fprintf('  median=%.3fms  mean=%.3fms  max=%.3fms\n', median(t5), mean(t5), max(t5));

% ── Interpretation ────────────────────────────────────────────────────────
fprintf('\n============================================================\n');
fprintf('  SUMMARY (median ms per call)\n');
fprintf('============================================================\n');
fprintf('(1) Identical input repeated : %.3f ms\n', median(t1));
fprintf('(2) Randomized input         : %.3f ms\n', median(t2));
fprintf('(3) Batch (per-call equiv.)  : %.4f ms\n', t3_per_call);
fprintf('(4) Pre-built dlarray object : %.3f ms\n', median(t4));
fprintf('(5) Manual forward pass      : %.3f ms\n', median(t5));
fprintf('============================================================\n');

ratio_12 = median(t2)/median(t1);
fprintf('\n(2)/(1) ratio = %.2f  ', ratio_12);
if ratio_12 < 1.3 && ratio_12 > 0.7
    fprintf('-> (1) and (2) are approximately EQUAL:\n');
    fprintf('   JIT/trace recompilation is NOT the mechanism (a cached\n');
    fprintf('   trace for identical inputs would make (1) meaningfully\n');
    fprintf('   faster than (2), which is not observed).\n');
else
    fprintf('-> (1) and (2) DIFFER meaningfully:\n');
    fprintf('   consistent with input-dependent recompilation/caching.\n');
end

ratio_23 = median(t2)/t3_per_call;
fprintf('\n(2)/(3) ratio = %.1f  ', ratio_23);
if ratio_23 > 3
    fprintf('-> batching amortizes most of the cost:\n');
    fprintf('   per-CALL dispatch/validation overhead is a major driver.\n');
else
    fprintf('-> batching does not amortize much cost:\n');
    fprintf('   per-call dispatch overhead is NOT the dominant driver.\n');
end

ratio_24 = median(t2)/median(t4);
fprintf('\n(2)/(4) ratio = %.2f  ', ratio_24);
if ratio_24 < 1.3 && ratio_24 > 0.7
    fprintf('-> pre-building the dlarray object does NOT help:\n');
    fprintf('   dlarray construction is NOT the mechanism; the cost is\n');
    fprintf('   inside predict() itself.\n');
else
    fprintf('-> pre-building the dlarray object DOES help:\n');
    fprintf('   dlarray construction is a meaningful contributor.\n');
end

fprintf('\nFloor (manual, condition 5): %.3f ms\n', median(t5));
fprintf('Irreducible predict()-vs-manual gap: %.3f ms (%.1fx)\n', ...
    median(t2)-median(t5), median(t2)/median(t5));

% ── Write results file ───────────────────────────────────────────────────────
fid = fopen(txt_path, 'w');
fprintf(fid, 'ISOLATING THE predict() OVERHEAD MECHANISM (item 2.2)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, 'Architecture: TCN, N_calls=%d, MATLAB %s\n', N_CALLS, version);
fprintf(fid, '================================================\n\n');
fprintf(fid, 'condition_1_identical_median_ms = %.4f\n', median(t1));
fprintf(fid, 'condition_2_randomized_median_ms = %.4f\n', median(t2));
fprintf(fid, 'condition_3_batch_percall_ms = %.4f\n', t3_per_call);
fprintf(fid, 'condition_4_prebuilt_median_ms = %.4f\n', median(t4));
fprintf(fid, 'condition_5_manual_median_ms = %.4f\n', median(t5));
fprintf(fid, '\nratio_2_over_1 = %.3f\n', ratio_12);
fprintf(fid, 'ratio_2_over_3 = %.3f\n', ratio_23);
fprintf(fid, 'ratio_2_over_4 = %.3f\n', ratio_24);
fprintf(fid, 'ratio_2_over_5 = %.3f\n', median(t2)/median(t5));
fclose(fid);
fprintf('\nWrote %s\n', txt_path);

results.t1 = t1; results.t2 = t2; results.t3_per_call = t3_per_call;
results.t4 = t4; results.t5 = t5;

end
