function mdl = stage2_train_llnfm(data, cfg)
% STAGE2_TRAIN_LLNFM  Train Local Linear Neuro-Fuzzy Model (ANFIS)
%
%   mdl = stage2_train_llnfm(data, cfg)
%
%   Trains two independent Sugeno ANFIS models (one per output: omega, beta)
%   using the anfis() function with matrix input syntax (R2024a compatible).
%
%   API NOTE — R2024a
%     tunefis() with ANFIS method requires output MF params in the paramset,
%     but getTunableSettings() only returns input params. This makes tunefis
%     unusable for ANFIS in R2024a (confirmed by diagnostic).
%     Solution: use anfis() directly with matrix syntax:
%       anfis([X, y], fis_init, [epochs step dec inc goal])
%     This API is fully functional in R2024a and trains both input MF
%     parameters (gbellmf) and output linear coefficients (Sugeno).
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config
%
%   OUTPUT  mdl struct fields:
%     fis_omega    trained Sugeno FIS for omega_next prediction
%     fis_beta     trained Sugeno FIS for beta_next prediction
%     xmu, xsig    input normalisation  (shared from data.norm)
%     ymu, ysig    output normalisation (shared from data.norm)
%     rmse_tr      [1x2] RMSE on training set   [omega, beta]
%     rmse_val     [1x2] RMSE on validation set [omega, beta]
%     rmse_te      [1x2] RMSE on test set       [omega, beta]
%     err_omega    ANFIS training RMSE per epoch (omega FIS)
%     err_beta     ANFIS training RMSE per epoch (beta FIS)
%     train_time   total training time [s]
%     name         'LLNFM'
%
%   REFERENCE
%     Klein et al. (2024). MathWorks / RWTH Aachen.
%     MATLAB Fuzzy Logic Toolbox R2024a — anfis() documentation.

n_mf     = cfg.ml.llnfm.n_mf;
n_epochs = cfg.ml.llnfm.n_epochs;
n_sub    = cfg.ml.llnfm.n_sub;

fprintf('  [LLNFM]  n_mf=%d  epochs=%d  n_sub=%d ...\n', ...
        n_mf, n_epochs, n_sub);
tic;

% ── Shared normalisation from Stage 1 ────────────────────────────────────────
xmu  = data.norm.xmu;
xsig = data.norm.xsig;
ymu  = data.norm.ymu;
ysig = data.norm.ysig;

% ── Normalise all sets ────────────────────────────────────────────────────────
X_tr_n  = (data.X_in(data.idx_train,:)  - xmu) ./ xsig;
Y_tr_n  = (data.X_out(data.idx_train,:) - ymu) ./ ysig;
X_val_n = (data.X_in(data.idx_val,:)    - xmu) ./ xsig;
X_te_n  = (data.X_in(data.idx_test,:)   - xmu) ./ xsig;

% ── Subsample for genfis + anfis (memory constraint) ─────────────────────────
rng(42);
N_tr  = size(X_tr_n, 1);
idx_s = randperm(N_tr, min(n_sub, N_tr));
Xs    = X_tr_n(idx_s, :);
Ys    = Y_tr_n(idx_s, :);

% ── Build initial Sugeno FIS via GridPartition ────────────────────────────────
opt_gen = genfisOptions('GridPartition');
opt_gen.NumMembershipFunctions       = n_mf * ones(1, 4);
opt_gen.InputMembershipFunctionType  = 'gbellmf';
opt_gen.OutputMembershipFunctionType = 'linear';

fis_init_o = genfis(Xs, Ys(:,1), opt_gen);
fis_init_b = genfis(Xs, Ys(:,2), opt_gen);

% ── ANFIS training options ────────────────────────────────────────────────────
%    Vector format: [n_epochs, init_step, step_decrease, step_increase, error_goal]
%    error_goal = 0  → always train for full n_epochs (no early stop)
%    Confirmed working syntax in R2024a via diagnostic.
anfis_opts = [n_epochs, 0.01, 0.9, 1.1, 0];

% ── Train FIS 1/2: omega_next ─────────────────────────────────────────────────
fprintf('    FIS 1/2: omega ...\n');
data_o = [Xs, Ys(:,1)];   % [N_sub x 5] — anfis expects [X, y] concatenated
[fis_omega, err_omega] = anfis(data_o, fis_init_o, anfis_opts);

% ── Train FIS 2/2: beta_next ──────────────────────────────────────────────────
fprintf('    FIS 2/2: beta  ...\n');
data_b = [Xs, Ys(:,2)];   % [N_sub x 5]
[fis_beta, err_beta]   = anfis(data_b, fis_init_b, anfis_opts);

mdl.train_time = toc;

% ── Evaluate on all sets ──────────────────────────────────────────────────────
Y_tr  = data.X_out(data.idx_train,:);
Y_val = data.X_out(data.idx_val,:);
Y_te  = data.X_out(data.idx_test,:);

Yhat_tr  = predict_llnfm(fis_omega, fis_beta, X_tr_n,  ymu, ysig);
Yhat_val = predict_llnfm(fis_omega, fis_beta, X_val_n, ymu, ysig);
Yhat_te  = predict_llnfm(fis_omega, fis_beta, X_te_n,  ymu, ysig);

mdl.rmse_tr  = sqrt(mean((Yhat_tr  - Y_tr ).^2));
mdl.rmse_val = sqrt(mean((Yhat_val - Y_val).^2));
mdl.rmse_te  = sqrt(mean((Yhat_te  - Y_te ).^2));

% ── Store ─────────────────────────────────────────────────────────────────────
mdl.fis_omega = fis_omega;
mdl.fis_beta  = fis_beta;
mdl.xmu  = xmu;  mdl.xsig = xsig;
mdl.ymu  = ymu;  mdl.ysig = ysig;
mdl.err_omega = err_omega(:);
mdl.err_beta  = err_beta(:);
mdl.name = 'LLNFM';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(2));
fprintf('    RMSE val : omega=%.5f  beta=%.4f\n', ...
        mdl.rmse_val(1), mdl.rmse_val(2));
end

% ── Helpers ───────────────────────────────────────────────────────────────────
function Yhat = predict_llnfm(fis_o, fis_b, Xn, ymu, ysig)
% Clamp inputs to FIS range before evalfis to suppress out-of-range warnings
    Xn_o = clamp_to_fis(fis_o, Xn);
    Xn_b = clamp_to_fis(fis_b, Xn);
    o    = evalfis(fis_o, Xn_o) .* ysig(1) + ymu(1);
    b    = evalfis(fis_b, Xn_b) .* ysig(2) + ymu(2);
    Yhat = [o, b];
end

function Xc = clamp_to_fis(fis, X)
    Xc = X;
    for i = 1:numel(fis.Inputs)
        r = fis.Inputs(i).Range;
        Xc(:,i) = max(r(1), min(r(2), X(:,i)));
    end
end