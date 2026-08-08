function mdl = stage2_train_gp(data, cfg)
% STAGE2_TRAIN_GP  Train Gaussian Process regressors for WT state prediction
%
%   mdl = stage2_train_gp(data, cfg)
%
%   Fits two independent GP models (omega_next, beta_next) using a
%   squared-exponential kernel. Hyperparameters are fixed (no optimisation)
%   to keep training tractable. The GP provides calibrated predictive
%   uncertainty sigma used in the GP-MPC cost function (Gap-1 contribution).
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config
%
%   OUTPUT  mdl struct fields:
%     gp_o         trained GP for omega_next
%     gp_b         trained GP for beta_next
%     xmu, xsig    input normalisation  (shared from data.norm)
%     ymu, ysig    output normalisation (shared from data.norm)
%     rmse_tr      [1x2] RMSE on training set
%     rmse_val     [1x2] RMSE on validation set
%     rmse_te      [1x2] RMSE on test set
%     sigma_te     [1x2] mean predictive std on test set [omega, beta]
%     train_time   total training time [s]
%     name         'GP'
%
%   NOTE ON SUBSAMPLING
%     GP training scales as O(N^3). A subset of N_sub points is used.
%     The subset is drawn from the TRAINING SET only, using the shared
%     normalisation. This is consistent with Stage 1 normalisation.
%
%   NOTE ON UNCERTAINTY
%     sigma from predict() is the predictive standard deviation.
%     It is used in cost_gp.m as: J_GP = J_MPC + kappa * sigma^2
%     With fixed hyperparameters, sigma reflects kernel structure, not
%     true posterior uncertainty. Documented as approximation in paper.

N_sub = cfg.ml.gp.N_sub;

fprintf('  [GP]  N_sub=%d  kernel=%s ...\n', N_sub, cfg.ml.gp.kernel);
tic;

% ── Shared normalisation from Stage 1 ────────────────────────────────────────
xmu  = data.norm.xmu;
xsig = data.norm.xsig;
ymu  = data.norm.ymu;
ysig = data.norm.ysig;

% ── Normalise using GLOBAL statistics ────────────────────────────────────────
%    GP subset is drawn from training set — normalisation applied consistently
X_tr_n  = (data.X_in(data.idx_train,:)  - xmu) ./ xsig;
Y_tr    =  data.X_out(data.idx_train,:);
X_val_n = (data.X_in(data.idx_val,:)    - xmu) ./ xsig;
X_te_n  = (data.X_in(data.idx_test,:)   - xmu) ./ xsig;

% ── Subsample from training set ───────────────────────────────────────────────
rng(1);
N_tr  = size(X_tr_n, 1);
idx_s = randperm(N_tr, min(N_sub, N_tr));
Xs_n  = X_tr_n(idx_s, :);
Ys    = Y_tr(idx_s, :);      % raw targets — fitrgp standardises internally

% ── Fit GP models ─────────────────────────────────────────────────────────────
fprintf('    GP 1/2: omega ...\n');
gp_o = fitrgp(Xs_n, Ys(:,1), ...
    'KernelFunction',          cfg.ml.gp.kernel, ...
    'Standardize',             true, ...
    'OptimizeHyperparameters', 'none');

fprintf('    GP 2/2: beta  ...\n');
gp_b = fitrgp(Xs_n, Ys(:,2), ...
    'KernelFunction',          cfg.ml.gp.kernel, ...
    'Standardize',             true, ...
    'OptimizeHyperparameters', 'none');

mdl.train_time = toc;

% ── Predict on all sets ───────────────────────────────────────────────────────
[po_tr,  ~]     = predict(gp_o, X_tr_n);
[pb_tr,  ~]     = predict(gp_b, X_tr_n);
[po_val, ~]     = predict(gp_o, X_val_n);
[pb_val, ~]     = predict(gp_b, X_val_n);
[po_te,  so_te] = predict(gp_o, X_te_n);
[pb_te,  sb_te] = predict(gp_b, X_te_n);

Y_tr_raw  = data.X_out(data.idx_train,:);
Y_val_raw = data.X_out(data.idx_val,:);
Y_te_raw  = data.X_out(data.idx_test,:);

mdl.rmse_tr  = sqrt(mean(([po_tr,  pb_tr]  - Y_tr_raw ).^2));
mdl.rmse_val = sqrt(mean(([po_val, pb_val] - Y_val_raw).^2));
mdl.rmse_te  = sqrt(mean(([po_te,  pb_te]  - Y_te_raw ).^2));
mdl.sigma_te = [mean(so_te), mean(sb_te)];

% ── Store ─────────────────────────────────────────────────────────────────────
mdl.gp_o = gp_o;
mdl.gp_b = gp_b;
mdl.xmu  = xmu;  mdl.xsig = xsig;
mdl.ymu  = ymu;  mdl.ysig = ysig;
mdl.name = 'GP';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(2));
fprintf('    Mean sigma_te : omega=%.5f  beta=%.5f\n', ...
        mdl.sigma_te(1), mdl.sigma_te(2));
end
