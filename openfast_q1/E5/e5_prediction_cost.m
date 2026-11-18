function C = e5_prediction_cost(runs, run_mask, model, S)
%E5_PREDICTION_COST  Prediction cost per call of a model, offline, double precision on the CPU
%(evaluation_offline.cost, E5 l.121; amendment_3.D13_prediction_cost). No timing is presented as a
%capability.
%
%   C = e5_prediction_cost(runs, run_mask, model, S)
%
%   Candidate rows: the rows k >= S.l_max + 1 of the selected runs (the selection subset in the
%   campaign), in the order of e5_rows. rng(S.cost_seed, 'twister'), then randperm without
%   replacement draws S.cost_calls of them (reading R4 of P1); the state of the global stream is
%   restored on exit. For each drawn row: z0 = model.init(x_k, hist) (not timed), then one call
%   [z1, aux] = model.step(z0, u_k, d_k) timed with tic/toc. The first call is excluded.
%   The thread count is the one of the session, set by the caller (D13: as the campaign).
%   C.times      S.cost_calls x 1 times (s), the first included
%   C.rows       S.cost_calls x 2 [run index, k] of the drawn rows
%   C.n, C.mean, C.median, C.p95 (nearest rank), C.max   over calls 2 .. S.cost_calls
%   C.threads    maxNumCompThreads at the time of the measurement

cand = e5_rows(runs, run_mask, 'window', S.l_max + 1);
if size(cand, 1) < S.cost_calls
    error('e5_prediction_cost:rows', 'Only %d candidate rows, %d calls requested.', size(cand, 1), S.cost_calls);
end
rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
rng(S.cost_seed, 'twister');
pick = randperm(size(cand, 1), S.cost_calls);
C.rows = cand(pick, :);
C.times = zeros(S.cost_calls, 1);
for i_call = 1:S.cost_calls
    run_k = runs(C.rows(i_call, 1));
    k = C.rows(i_call, 2);
    z0 = run_k.X(k, 1:2)';
    z0 = model.init(z0, run_k.X(k - S.l_max:k - 1, :));
    u_k = run_k.X(k, 3);
    d_k = run_k.X(k, 4);
    t_call = tic;
    [~, ~] = model.step(z0, u_k, d_k);
    C.times(i_call) = toc(t_call);
end
kept = sort(C.times(2:end));
C.n = numel(kept);
C.mean = mean(kept);
C.median = median(kept);
C.p95 = kept(ceil(0.95*C.n));
C.max = kept(end);
C.threads = maxNumCompThreads;
delete(restore_rng);
end
