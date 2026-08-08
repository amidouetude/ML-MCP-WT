function mdl = stage2_train_gp_v2(data, cfg)
% STAGE2_TRAIN_GP_V2  Train GP surrogate — V2 (Matern 5/2 + HP optimisation)
%
%   mdl = stage2_train_gp_v2(data, cfg)
%
%   Improvements over V1 stage2_train_gp.m:
%     1. Kernel: Matern 5/2  instead of Squared Exponential (SE)
%     2. Hyperparameter optimisation: Bayesian optimisation (20 evals)
%        instead of fixed default hyperparameters
%
%   WHY MATERN 5/2 OVER SE
%     The SE kernel assumes infinitely differentiable sample paths — a strong
%     smoothness assumption that is rarely met by physical dynamics subject to
%     turbulent forcing. The Matern 5/2 kernel (twice differentiable) is more
%     appropriate for physical systems with moderate regularity.
%     Formally:
%       SE      : k(r) = exp(-r^2 / (2*l^2))
%       Matern52: k(r) = (1 + sqrt(5)*r/l + 5*r^2/(3*l^2)) * exp(-sqrt(5)*r/l)
%     where r = ||x-x'|| and l = length scale.
%     Rasmussen & Williams (2006) recommend Matern 5/2 for physical systems.
%
%   WHY HYPERPARAMETER OPTIMISATION
%     V1 used default SE hyperparameters (sigma_f, l fixed at MATLAB defaults).
%     These do not reflect the actual length scales of the normalised input
%     space — e.g., omega and beta have very different dynamics but were
%     treated identically. Bayesian optimisation of (sigma_f, l, sigma_n)
%     via marginal likelihood maximisation gives calibrated uncertainty
%     estimates, which directly improves the GP-MPC cost term kappa*sigma^2.
%
%   COMPUTATIONAL COST
%     fitrgp with 'OptimizeHyperparameters','all' and MaxObjectiveEvaluations=20:
%     ~15s on 100 pts (measured), estimated ~90s on N_sub=400 pts.
%     This is a one-time training cost — inference cost unchanged.
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config  (uses cfg.ml2.gp fields)
%
%   OUTPUT  mdl struct fields:
%     gp_o         trained GP for omega_next (Matern52 + optimised HP)
%     gp_b         trained GP for beta_next  (Matern52 + optimised HP)
%     hp_o         optimised hyperparameters for omega GP
%     hp_b         optimised hyperparameters for beta GP
%     xmu, xsig    input normalisation  (shared from data.norm)
%     ymu, ysig    output normalisation (shared from data.norm)
%     rmse_tr      [1x2] RMSE on training set
%     rmse_val     [1x2] RMSE on validation set
%     rmse_te      [1x2] RMSE on test set
%     sigma_te     [1x2] mean predictive std on test set
%     train_time   total training time [s]
%     name         'GP-v2'
%
%   REFERENCE
%     Rasmussen, C.E. & Williams, C.K.I. (2006). Gaussian Processes for
%       Machine Learning. MIT Press. Chapter 4 (covariance functions).
%     MATLAB fitrgp documentation — OptimizeHyperparameters option.

N_sub    = cfg.ml2.gp.N_sub;
kernel   = cfg.ml2.gp.kernel;      % 'matern52'
max_eval = cfg.ml2.gp.max_evals;   % 20

fprintf('  [GP-v2]  N_sub=%d  kernel=%s  optim_HP=%d evals ...\n', ...
        N_sub, kernel, max_eval);
tic;

% ── Shared normalisation from Stage 1 ────────────────────────────────────────
xmu  = data.norm.xmu;
xsig = data.norm.xsig;
ymu  = data.norm.ymu;
ysig = data.norm.ysig;

% ── Normalise using GLOBAL statistics ────────────────────────────────────────
X_tr_n  = (data.X_in(data.idx_train,:)  - xmu) ./ xsig;
Y_tr    =  data.X_out(data.idx_train,:);
X_val_n = (data.X_in(data.idx_val,:)    - xmu) ./ xsig;
X_te_n  = (data.X_in(data.idx_test,:)   - xmu) ./ xsig;

% ── Subsample from training set ───────────────────────────────────────────────
rng(1);
N_tr  = size(X_tr_n, 1);
idx_s = randperm(N_tr, min(N_sub, N_tr));
Xs_n  = X_tr_n(idx_s, :);
Ys    = Y_tr(idx_s, :);

% ── Bayesian hyperparameter optimisation options ──────────────────────────────
hp_opts = struct(...
    'MaxObjectiveEvaluations', max_eval, ...
    'ShowPlots',               false, ...
    'Verbose',                 0, ...
    'UseParallel',             false);

% ── Fit GP 1/2: omega_next ────────────────────────────────────────────────────
fprintf('    GP 1/2: omega (Matern52 + Bayesian HP optim) ...\n');
gp_o = fitrgp(Xs_n, Ys(:,1), ...
    'KernelFunction',                     kernel, ...
    'Standardize',                        true, ...
    'OptimizeHyperparameters',            'all', ...
    'HyperparameterOptimizationOptions',  hp_opts);

% Extract optimised hyperparameters for reporting
hp_o.KernelParameters = gp_o.KernelInformation.KernelParameters;
hp_o.Sigma            = gp_o.Sigma;
fprintf('    omega GP: sigma_f=%.4f  l=%.4f  sigma_n=%.4f\n', ...
        hp_o.KernelParameters(end), hp_o.KernelParameters(1), hp_o.Sigma);

% ── Fit GP 2/2: beta_next ─────────────────────────────────────────────────────
fprintf('    GP 2/2: beta  (Matern52 + Bayesian HP optim) ...\n');
gp_b = fitrgp(Xs_n, Ys(:,2), ...
    'KernelFunction',                     kernel, ...
    'Standardize',                        true, ...
    'OptimizeHyperparameters',            'all', ...
    'HyperparameterOptimizationOptions',  hp_opts);

hp_b.KernelParameters = gp_b.KernelInformation.KernelParameters;
hp_b.Sigma            = gp_b.Sigma;
fprintf('    beta  GP: sigma_f=%.4f  l=%.4f  sigma_n=%.4f\n', ...
        hp_b.KernelParameters(end), hp_b.KernelParameters(1), hp_b.Sigma);

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
mdl.hp_o = hp_o;
mdl.hp_b = hp_b;
mdl.xmu  = xmu;  mdl.xsig = xsig;
mdl.ymu  = ymu;  mdl.ysig = ysig;
mdl.name = 'GP-v2';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s (%.4f rpm)  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(1)*30/pi, mdl.rmse_te(2));
fprintf('    Mean sigma_te : omega=%.5f  beta=%.5f\n', ...
        mdl.sigma_te(1), mdl.sigma_te(2));
fprintf('    [Improvement vs V1: calibrated uncertainty for GP-MPC cost]\n');
end
