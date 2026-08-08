function metrics = compute_extended_metrics(y_true, y_pred)
% COMPUTE_EXTENDED_METRICS  Compute RMSE, MAE, and R² for a set of
% predictions, for use alongside (not instead of) the RMSE reported
% throughout this project (reproducibility review, P2.1).
%
%   metrics = compute_extended_metrics(y_true, y_pred)
%
%   INPUTS
%     y_true, y_pred   [N x D] matrices, same shape (e.g. D=2 for
%                      [omega, beta] predictions)
%
%   OUTPUT  metrics struct, one row per column of y_true/y_pred:
%     rmse   [1 x D]  root mean squared error (same metric used
%                     throughout this project's tables)
%     mae    [1 x D]  mean absolute error
%     r2     [1 x D]  coefficient of determination,
%                     1 - SS_res/SS_tot
%
%   USAGE NOTE — RETROACTIVE APPLICATION NOT POSSIBLE
%     This function was added after most of this project's results
%     were generated and reported as RMSE-only in console output and
%     the paper's tables. Computing MAE/R² for those already-reported
%     numbers is NOT possible without access to the original raw
%     prediction arrays (only the aggregate RMSE was logged, not the
%     underlying per-sample predictions/targets). This function is
%     provided so that FUTURE evaluation runs (e.g. any Stage 2/3
%     re-run, or new surrogates added later) can report all three
%     metrics together going forward, rather than requiring a second
%     retroactive fix of this kind.

D = size(y_true, 2);
metrics.rmse = zeros(1, D);
metrics.mae  = zeros(1, D);
metrics.r2   = zeros(1, D);

for d = 1:D
    err = y_pred(:,d) - y_true(:,d);
    metrics.rmse(d) = sqrt(mean(err.^2));
    metrics.mae(d)  = mean(abs(err));

    ss_res = sum(err.^2);
    ss_tot = sum((y_true(:,d) - mean(y_true(:,d))).^2);
    if ss_tot > 0
        metrics.r2(d) = 1 - ss_res/ss_tot;
    else
        metrics.r2(d) = NaN;   % undefined if y_true is constant
    end
end

end
