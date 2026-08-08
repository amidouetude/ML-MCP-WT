function mdl = stage2_train_gp_residual()
% STAGE2_TRAIN_GP_RESIDUAL  Train a Gaussian Process residual-correction
% model for the "does bypassing predict() generalize beyond neural
% networks?" follow-up test.
%
%   mdl = stage2_train_gp_residual()
%
%   WHY A SEPARATE, SMALL GP (not reusing the original GP-v2 from the
%   V1/V2 project)
%     This tests a specific, narrow question — is predict() itself
%     the bottleneck, independent of surrogate TYPE (not just network
%     size, per the MLP result in test_residual_manual_closed_loop.m)?
%     A small, purpose-trained GP on the SAME residual-learning task as
%     stage2_train_residual.m gives a clean, directly comparable
%     experiment, without touching the original (larger, differently-
%     normalized) GP-v2 pipeline from the V1/V2 project.
%
%   KEY DESIGN CHOICE — Standardize=false
%     fitrgp's 'Standardize',true option applies an ADDITIONAL internal
%     standardization on top of whatever normalisation is already
%     applied to the input features. Our features are already
%     normalised via data.norm.xmu/xsig (as for every other surrogate
%     in this project). Setting 'Standardize',false avoids a second,
%     internal (and less directly accessible) standardization layer,
%     so that ActiveSetVectors are stored in exactly the same
%     (already-normalised) feature space we pass at inference time —
%     essential for the manual posterior-mean formula in
%     extract_gp_weights.m to be straightforward and verifiable.
%
%   BASIS FUNCTION
%     fitrgp's default BasisFunction is 'constant': the posterior mean
%     is h(x)*Beta + k(x, X_active)*Alpha, NOT just the kernel sum. The
%     constant term (mdl.gp_o.Beta) must be included in the manual
%     forward pass or it will not match predict().
%
%   OUTPUT  mdl struct fields:
%     gp_o, gp_b     trained RegressionGP objects (omega, beta residual)
%     xmu,xsig,ymu,ysig  normalisation (from stage1_residual_data.mat)
%     rmse_te        [1x2] test RMSE
%     train_time     [s]
%     name           'GP-Residual'

fprintf('==========================================================\n');
fprintf('  FOLLOW-UP TEST — GP Residual Model (predict() bypass, GP case)\n');
fprintf('==========================================================\n\n');

if ~exist('stage1_residual_data.mat', 'file')
    error(['stage1_residual_data.mat not found. Run ' ...
           'stage1_generate_residual_data() first (Track B dataset is reused here).']);
end
data = load('stage1_residual_data.mat');

xmu = data.norm.xmu; xsig = data.norm.xsig;
ymu = data.norm.ymu; ysig = data.norm.ysig;

X_tr_n  = (data.X_in(data.idx_train,:) - xmu) ./ xsig;
Y_tr    =  data.Y_residual(data.idx_train,:);
X_te_n  = (data.X_in(data.idx_test,:)  - xmu) ./ xsig;
Y_te    =  data.Y_residual(data.idx_test,:);

% ── Subsample for tractable O(N^3) GP training ──────────────────────────────
N_sub = 50;   % reduced from 300 — testing whether manual-GP cost
              % scales down proportionally with active-set size
              % (see docs/experiment_log.md, 2026-07-28 follow-up entry)
rng(1);
N_tr = size(X_tr_n, 1);
idx_s = randperm(N_tr, min(N_sub, N_tr));
Xs_n = X_tr_n(idx_s, :);
Ys   = Y_tr(idx_s, :);

fprintf('Training GP 1/2 (d_omega, Matern52, Standardize=false, N_sub=%d)...\n', N_sub);
tic;
gp_o = fitrgp(Xs_n, Ys(:,1), ...
    'KernelFunction', 'matern52', ...
    'Standardize', false, ...
    'BasisFunction', 'constant');
fprintf('Training GP 2/2 (d_beta)...\n');
gp_b = fitrgp(Xs_n, Ys(:,2), ...
    'KernelFunction', 'matern52', ...
    'Standardize', false, ...
    'BasisFunction', 'constant');
train_time = toc;

pred_te = [predict(gp_o, X_te_n), predict(gp_b, X_te_n)];
rmse_te = sqrt(mean((pred_te - Y_te).^2));

fprintf('\nDone (%.1fs)\n', train_time);
fprintf('RMSE test: d_omega=%.6f rad/s  d_beta=%.6f deg\n', rmse_te(1), rmse_te(2));

mdl.gp_o = gp_o;
mdl.gp_b = gp_b;
mdl.xmu = xmu; mdl.xsig = xsig; mdl.ymu = ymu; mdl.ysig = ysig;
mdl.rmse_te = rmse_te;
mdl.train_time = train_time;
mdl.name = 'GP-Residual';

save('stage2_gp_residual_model.mat', 'mdl');
fprintf('\nSaved -> stage2_gp_residual_model.mat\n');

end