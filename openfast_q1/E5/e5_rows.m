function rows = e5_rows(runs, run_mask, kind, L)
%E5_ROWS  One-step training or evaluation rows of a family kind (amendment_3.D3_training_samples;
%data.history.rule, E5 l.77: history from the same run only and from t >= 60 s, which every row of
%the Ts0p050 tables satisfies).
%
%   rows = e5_rows(runs, run_mask, kind, L)
%
%   runs      e5_load_runs; run_mask  logical mask over runs (e5_partition)
%   kind      'current'   MLP, C5, C6 and C4 with L = 1: rows k = 1 .. n (L not used)
%             'window'    C1, C2 and C4: regressor of the L samples k - L + 1 .. k: rows k = L .. n
%             'sequence'  C3: warm-up on k - L .. k - 1, then the step at k: rows k = L + 1 .. n
%   rows      m x 2 [run index into runs, k], runs in increasing order, k increasing within a run
%
%   Every row k satisfies k <= n, so the target DX(k, :) = x_{k+1} - x_k is defined (e5_load_runs).

if ~islogical(run_mask) || numel(run_mask) ~= numel(runs)
    error('e5_rows:mask', 'run_mask must be a logical mask over runs.');
end
switch kind
    case 'current'
        first_k = 1;
    case 'window'
        check_L(L);
        first_k = L;
    case 'sequence'
        check_L(L);
        first_k = L + 1;
    otherwise
        error('e5_rows:kind', 'kind must be ''current'', ''window'' or ''sequence''.');
end
run_list = find(run_mask(:))';
counts = zeros(1, numel(run_list));
for q = 1:numel(run_list)
    counts(q) = max(size(runs(run_list(q)).X, 1) - first_k + 1, 0);
end
rows = zeros(sum(counts), 2);
pos = 0;
for q = 1:numel(run_list)
    k_run = (first_k:size(runs(run_list(q)).X, 1))';
    rows(pos + (1:counts(q)), :) = [repmat(run_list(q), counts(q), 1), k_run];
    pos = pos + counts(q);
end
end

function check_L(L)
if ~(isscalar(L) && isnumeric(L) && L >= 1 && L == round(L))
    error('e5_rows:L', 'L must be a positive integer.');
end
end
