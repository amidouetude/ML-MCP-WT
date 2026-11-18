function [Y_hat, Phi] = e5_lolimot_predict(Lm, Ft)
%E5_LOLIMOT_PREDICT  Training-side prediction of C4 on a set of rows: one call of e5_llm_core per
%row, the function of the manual model (e5_model, case C4), so that the training uses no other
%computation of the model output (supervisor review of 18/11/2026).
%
%   [Y_hat, Phi] = e5_lolimot_predict(Lm, Ft)
%
%   Lm      struct of C4 (e5_llm_core)
%   Ft      n_r x N normalised regressors, one column per row (the transpose of F of e5_features)
%   Y_hat   2 x N normalised outputs; Phi m x N validity functions (only if requested)

n_cols = size(Ft, 2);
Y_hat = zeros(2, n_cols);
if nargout > 1
    Phi = zeros(Lm.m, n_cols);
    for n = 1:n_cols
        [Y_hat(:, n), Phi(:, n)] = e5_llm_core(Lm, Ft(:, n));
    end
else
    for n = 1:n_cols
        Y_hat(:, n) = e5_llm_core(Lm, Ft(:, n));
    end
end
end
