function D = e5_nn_data(runs, run_mask, family, L, nrm, c5)
%E5_NN_DATA  Training or selection arrays of a network family, in single precision for the GPU
%(framework_decisions.compute, E5 l.27; amendment_3.D2_scaling, D3_training_samples; amendment_4.A9,
%A10, A11).
%
%   D = e5_nn_data(runs, run_mask, family, L, nrm)          MLP, C1, C2, C3
%   D = e5_nn_data(runs, run_mask, family, L, nrm, c5)      C5
%
%   runs, run_mask   e5_load_runs (or e5_synthetic_runs) and a logical mask over runs (e5_partition)
%   family           'MLP', 'C1', 'C2', 'C3' or 'C5'; L the history of C1, C2, C3 (not used otherwise)
%   c5               C5 only: struct with fields rows (e5_rows of kind 'current' on the same runs and
%                    mask), Y and keep (e5_c5_targets on those rows, computed once, A11)
%   D.X              single: 'CB' 4 x N (MLP, C5), 'CB' 4L x N (C1, layout 'window', lag 0 first),
%                    'CBT' 4 x N x L (C2, layout 'window_seq'), 'CBT' 4 x N x (L + 1) (C3, layout
%                    'sequence'); D.fmt the format
%   D.Y              single 2 x N: normalised Delta x (MLP, C1, C2, C3), scaled residual (C5)
%   D.rows           N x 2 [run, k] of the rows kept; D.n_excluded rows removed by D7 (C5), else 0
%   Refuses (error) for an unknown family, for C5 without c5 or with c5.rows different from the rows
%   of the mask, and if a value of D.X or D.Y is not finite (C5: after the exclusion).

switch family
    case {'MLP', 'C5'}
        kind = 'current';  layout = 'current';  n_lag = 1;
    case 'C1'
        kind = 'window';   layout = 'window';   n_lag = L;
    case 'C2'
        kind = 'window';   layout = 'window_seq';  n_lag = L;
    case 'C3'
        kind = 'sequence'; layout = 'sequence'; n_lag = L;
    otherwise
        error('e5_nn_data:family', 'Unknown family %s (MLP, C1, C2, C3 or C5).', family);
end
rows = e5_rows(runs, run_mask, kind, n_lag);
[F, Y] = e5_features(runs, rows, layout, n_lag, nrm, 'single');
D.n_excluded = 0;
if strcmp(family, 'C5')
    if nargin < 6 || ~isstruct(c5) || ~all(isfield(c5, {'rows', 'Y', 'keep'})) || ~isequal(c5.rows, rows)
        error('e5_nn_data:c5', 'C5 needs the targets of e5_c5_targets on the rows of this mask (A11).');
    end
    keep = logical(c5.keep(:));
    F = F(keep, :);
    Y = single(c5.Y(keep, :));
    rows = rows(keep, :);
    D.n_excluded = nnz(~keep);
end
switch layout
    case {'current', 'window'}
        D.X = F';
        D.fmt = 'CB';
    otherwise
        D.X = F;
        D.fmt = 'CBT';
end
D.Y = Y';
D.rows = rows;
D.family = family;
D.L = L;
if ~all(isfinite(D.X(:))) || ~all(isfinite(D.Y(:)))
    error('e5_nn_data:finite', 'A value of the %s arrays is not finite.', family);
end
end
