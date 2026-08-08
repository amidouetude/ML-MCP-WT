function [mdl_persist, mdl_linear] = stage2_train_baselines(data)
% STAGE2_TRAIN_BASELINES  Naive reference models for ML benchmark
%
%   [mdl_persist, mdl_linear] = stage2_train_baselines(data)
%
%   Trains two naive baselines that define the lower bound of useful
%   predictive performance. Any ML model that does not outperform the
%   Linear ARX baseline does not justify its added complexity.
%
%   MODEL 1 — Persistence:  x(k+1) = x(k)
%     No parameters. RMSE measures the typical one-step state change.
%     Expected RMSE ≈ std(delta_x) from Stage 1 validation output.
%
%   MODEL 2 — Linear ARX:  x(k+1) = theta * [x(k); V(k); u(k); 1]
%     Ordinary least squares via backslash operator.
%     Captures all linear dynamics. Non-linear models must beat this.
%
%   RELATIVE IMPROVEMENT METRIC (for paper)
%     gain_pct = (RMSE_linear - RMSE_model) / RMSE_linear * 100  [%]
%
%   INPUTS
%     data   struct from stage1_generate_data
%
%   OUTPUTS
%     mdl_persist   persistence model struct
%     mdl_linear    linear ARX model struct
%
%   Both structs contain: name, rmse_tr, rmse_val, rmse_te, train_time
%   Linear ARX also contains: theta (coefficient matrix [5 x 2])

fprintf('  [Baselines]  Persistence + Linear ARX ...\n');

X_tr  = data.X_in(data.idx_train,:);
Y_tr  = data.X_out(data.idx_train,:);
X_val = data.X_in(data.idx_val,:);
Y_val = data.X_out(data.idx_val,:);
X_te  = data.X_in(data.idx_test,:);
Y_te  = data.X_out(data.idx_test,:);

%% ── MODEL 1: Persistence ─────────────────────────────────────────────────────
tic;
% Prediction: x(k+1) = x(k) — use current state as prediction
% X_in(:,1:2) = [omega, beta] = current state
Yhat_tr_p  = X_tr(:,  1:2);
Yhat_val_p = X_val(:, 1:2);
Yhat_te_p  = X_te(:,  1:2);

mdl_persist.name      = 'Persistence';
mdl_persist.rmse_tr   = sqrt(mean((Yhat_tr_p  - Y_tr ).^2));
mdl_persist.rmse_val  = sqrt(mean((Yhat_val_p - Y_val).^2));
mdl_persist.rmse_te   = sqrt(mean((Yhat_te_p  - Y_te ).^2));
mdl_persist.train_time = toc;
mdl_persist.sigma_te  = [0, 0];

fprintf('    Persistence  RMSE test: omega=%.5f rad/s  beta=%.4f deg\n', ...
        mdl_persist.rmse_te(1), mdl_persist.rmse_te(2));

%% ── MODEL 2: Linear ARX ──────────────────────────────────────────────────────
tic;
% Design matrix: [omega, beta, V_wind, u_cmd, 1]  (intercept included)
% Solve: Y_tr = Phi_tr * theta  via least squares (backslash)
Phi_tr  = [X_tr,  ones(size(X_tr,  1), 1)];   % [N_tr  x 5]
Phi_val = [X_val, ones(size(X_val, 1), 1)];   % [N_val x 5]
Phi_te  = [X_te,  ones(size(X_te,  1), 1)];   % [N_te  x 5]

theta = Phi_tr \ Y_tr;   % [5 x 2] — backslash: numerically stable OLS

Yhat_tr_l  = Phi_tr  * theta;
Yhat_val_l = Phi_val * theta;
Yhat_te_l  = Phi_te  * theta;

mdl_linear.name       = 'Linear';
mdl_linear.theta      = theta;
mdl_linear.rmse_tr    = sqrt(mean((Yhat_tr_l  - Y_tr ).^2));
mdl_linear.rmse_val   = sqrt(mean((Yhat_val_l - Y_val).^2));
mdl_linear.rmse_te    = sqrt(mean((Yhat_te_l  - Y_te ).^2));
mdl_linear.train_time = toc;
mdl_linear.sigma_te   = [0, 0];

fprintf('    Linear ARX   RMSE test: omega=%.5f rad/s  beta=%.4f deg\n', ...
        mdl_linear.rmse_te(1), mdl_linear.rmse_te(2));

% Print learned coefficients for physical interpretability
fprintf('\n    Linear ARX coefficients:\n');
fprintf('    %-12s  %12s  %12s\n', 'Feature', 'omega_next', 'beta_next');
fprintf('    %s\n', repmat('-', 1, 40));
feats = {'omega_r', 'beta', 'V_wind', 'u_cmd', 'intercept'};
for i = 1:5
    fprintf('    %-12s  %12.6f  %12.6f\n', feats{i}, theta(i,1), theta(i,2));
end
fprintf('\n');
end
