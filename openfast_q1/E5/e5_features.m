function [F, Y] = e5_features(runs, rows, layout, L, nrm, cls)
%E5_FEATURES  Normalised inputs and normalised one-step targets of the rows of e5_rows
%(amendment_3.D2_scaling and D3_training_samples).
%
%   [F, Y] = e5_features(runs, rows, layout, L, nrm, cls)
%
%   rows     e5_rows; nrm  e5_normalisation; cls  'double' or 'single' (class of F and Y)
%   Every input sample s = [omega_r; omega_f; u; d] is normalised as (s - nrm.mu)./nrm.sd, the same
%   per variable at every lag. Y = (DX(k, :) - nrm.mux')./nrm.sdx' (m x 2), the target of the MLP,
%   C1, C2, C3, C4 and C6 (the C5 residual target is e5_c5_targets).
%   layout   'current'     F m x 4: sample k (rows of kind 'current')
%            'window'      F m x 4L: [s_k; s_{k-1}; ...; s_{k-L+1}] stacked lag 0 first, the
%                          regressor order of f_win (o8_model_synthetic.m l.254-256)
%            'window_seq'  F 4 x m x L ('CBT'): s_{k-L+1} .. s_k, oldest first, the column order of
%                          r2seq (o8_model_synthetic.m l.274-277), for the TCN (rows of kind 'window')
%            'sequence'    F 4 x m x (L + 1) ('CBT'): s_{k-L} .. s_k, oldest first, for the LSTM
%                          (rows of kind 'sequence'); the loss is taken on the output at s_k
%   Refuses (error) if a row needs a sample before the first row of its run.

if ~any(strcmp(cls, {'double', 'single'}))
    error('e5_features:class', 'cls must be ''double'' or ''single''.');
end
n_rows = size(rows, 1);
switch layout
    case 'current'
        lags = 0;
    case {'window', 'window_seq'}
        lags = 0:L - 1;
    case 'sequence'
        lags = 0:L;
    otherwise
        error('e5_features:layout', 'Unknown layout %s.', layout);
end
switch layout
    case 'current'
        F = zeros(n_rows, 4, cls);
    case 'window'
        F = zeros(n_rows, 4*L, cls);
    case 'window_seq'
        F = zeros(4, n_rows, L, cls);
    otherwise
        F = zeros(4, n_rows, L + 1, cls);
end
Y = zeros(n_rows, 2, cls);
run_list = unique(rows(:, 1))';
for r = run_list
    sel = find(rows(:, 1) == r);
    k_sel = rows(sel, 2);
    if min(k_sel) - max(lags) < 1
        error('e5_features:history', 'A row of run %s needs a sample before t = %g s.', runs(r).id, runs(r).t(1));
    end
    xn = (runs(r).X - nrm.mu')./nrm.sd';
    Y(sel, :) = cast((runs(r).DX(k_sel, :) - nrm.mux')./nrm.sdx', cls);
    switch layout
        case 'current'
            F(sel, :) = cast(xn(k_sel, :), cls);
        case 'window'
            for j = lags
                F(sel, 4*j + (1:4)) = cast(xn(k_sel - j, :), cls);
            end
        case 'window_seq'
            for j = 1:L
                F(:, sel, j) = cast(xn(k_sel - L + j, :)', cls);
            end
        otherwise
            for j = 0:L
                F(:, sel, j + 1) = cast(xn(k_sel - L + j, :)', cls);
            end
    end
end
end
