function mdl = stage2_train_pinn_v2(data, cfg)
% STAGE2_TRAIN_PINN_V2  Physics-Informed Neural Network — V2
%
%   mdl = stage2_train_pinn_v2(data, cfg)
%
%   Improvement over V1 stage2_train_pinn.m:
%     Differentiable Cp computation via softplus approximations,
%     enabling true gradient flow through the physics residual.
%
%   V1 PROBLEM — NON-DIFFERENTIABLE Cp CLAMP
%     V1 used: Cp = max(0, min(16/27, Cp_poly))
%     max() and min() are not differentiable at the clamp boundaries.
%     This means dlgradient cannot propagate gradients through Cp,
%     so L_phy contributes ZERO gradient to the network parameters
%     whenever Cp hits a boundary — which happens frequently in
%     Region II where Cp is far from the Betz limit.
%     Effectively, V1 PINN had a physics residual that was a constant
%     (non-differentiable) target, not a true differentiable constraint.
%
%   V2 SOLUTION — SOFTPLUS APPROXIMATION
%     softplus(x, beta) = (1/beta) * log(1 + exp(beta*x))
%     Properties:
%       - Smooth approximation of max(0, x)
%       - Differentiable everywhere (C-infinity)
%       - Controlled sharpness: higher beta → closer to hard clamp
%       - With beta=20: |softplus(x,20) - max(0,x)| < 0.05 for |x|>0.3
%
%     Cp clamp via softplus:
%       Cp_lower = softplus(Cp_poly, beta)           ≈ max(0, Cp_poly)
%       Cp_upper = Betz - softplus(Betz-Cp_lower, beta) ≈ min(Betz, Cp_lower)
%
%   RESIDUAL SCOPE — OMEGA ONLY (same as V1)
%     Beta actuator residual is still excluded.
%     Reason: with dt=tau_beta=0.1s, beta_next_phys=u exactly,
%     conflicting with rate saturation in real data (documented in V1).
%     Only the rotor ODE (omega) is used as physics constraint.
%
%   COMBINED LOSS
%     L = (1 - lambda_phy) * L_data + lambda_phy * L_physics_omega
%     where L_physics_omega uses differentiable Cp (softplus clamp)
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config  (uses cfg.ml2.pinn fields)
%
%   OUTPUT  mdl struct fields:
%     net              trained dlnetwork
%     xmu, xsig        input normalisation  (shared from data.norm)
%     ymu, ysig        output normalisation (shared from data.norm)
%     rmse_tr          [1x2] RMSE on training set
%     rmse_val         [1x2] RMSE on validation set
%     rmse_te          [1x2] RMSE on test set
%     lambda_phy       physics loss weight used
%     softplus_beta    softplus sharpness parameter
%     loss_history     [n_iter x 1] total loss per iteration
%     loss_data_hist   [n_iter x 1] data loss component
%     loss_phy_hist    [n_iter x 1] physics loss component
%     train_time       total training time [s]
%     name             'PINN-v2'
%
%   REFERENCE
%     Raissi, M. et al. (2019). Physics-informed neural networks.
%       Journal of Computational Physics, 378, 686-707.
%     Karniadakis, G.E. et al. (2021). Physics-informed machine learning.
%       Nature Reviews Physics, 3(6), 422-440.
%     Dugas, C. et al. (2000). Incorporating second-order functional
%       knowledge for better option pricing. NeurIPS.
%       [Original softplus reference for smooth activation functions]

n_iter       = cfg.ml2.pinn.n_iter;
lambda_phy   = cfg.ml2.pinn.lambda_phy;
batch        = cfg.ml2.pinn.batch;
lr_init      = cfg.ml2.pinn.lr_init;
lr_decay     = cfg.ml2.pinn.lr_decay;
lr_step      = cfg.ml2.pinn.lr_step;
sp_beta      = cfg.ml2.pinn.softplus_beta;   % softplus sharpness

fprintf('  [PINN-v2]  iters=%d  lambda_phy=%.2f  softplus_beta=%d ...\n', ...
        n_iter, lambda_phy, sp_beta);
tic;

% ── Shared normalisation from Stage 1 ────────────────────────────────────────
xmu  = data.norm.xmu;
xsig = data.norm.xsig;
ymu  = data.norm.ymu;
ysig = data.norm.ysig;

p = data.p;

% ── Normalised arrays ─────────────────────────────────────────────────────────
Xn_tr  = (data.X_in(data.idx_train,:)  - xmu) ./ xsig;
Yn_tr  = (data.X_out(data.idx_train,:) - ymu) ./ ysig;
Xn_val = (data.X_in(data.idx_val,:)    - xmu) ./ xsig;
Yn_val = (data.X_out(data.idx_val,:)   - ymu) ./ ysig;
Xn_te  = (data.X_in(data.idx_test,:)   - xmu) ./ xsig;

% Raw training inputs needed for physics residual
X_raw_tr = data.X_in(data.idx_train,:);

% ── Fix random seed for reproducible weight init + minibatch shuffling ─────
% [ADDED — reproducibility review, P0.4]. Same seed source as
% stage2_train_lstm.m/stage2_train_tcn.m/stage2_train_pinn.m
% (cfg.data.split_seed).
rng_seed = cfg.data.split_seed;
rng(rng_seed);
fprintf('    RNG seed fixed to %d before network construction/training.\n', rng_seed);

% ── Network architecture (identical to V1) ────────────────────────────────────
layers = [
    featureInputLayer(4,   'Name','in',  'Normalization','none')
    fullyConnectedLayer(64,'Name','fc1')
    tanhLayer('Name','tanh1')
    fullyConnectedLayer(64,'Name','fc2')
    tanhLayer('Name','tanh2')
    fullyConnectedLayer(32,'Name','fc3')
    tanhLayer('Name','tanh3')
    fullyConnectedLayer(2, 'Name','out')
];
net = dlnetwork(layerGraph(layers));

% ── Physics parameters for residual ──────────────────────────────────────────
phys.R        = p.R;
phys.rho      = p.rho;
phys.A_rotor  = p.A_rotor;
phys.J        = p.J;
phys.Br       = p.Br;
phys.N_gear   = p.N_gear;
phys.Tg_rated = p.Tg_rated;
phys.K_opt    = p.K_opt;
phys.omega_r  = p.omega_r;
phys.dt       = data.cfg.data.dt;
phys.ymu      = ymu;
phys.ysig     = ysig;
phys.sp_beta  = sp_beta;       % softplus sharpness — KEY V2 parameter

% ── Training loop ─────────────────────────────────────────────────────────────
avgG   = [];
avgSqG = [];
N_tr   = size(Xn_tr, 1);

loss_history   = zeros(n_iter, 1);
loss_data_hist = zeros(n_iter, 1);
loss_phy_hist  = zeros(n_iter, 1);

fprintf('    Training loop...\n');

for iter = 1:n_iter
    % Piecewise LR decay
    n_decays = floor((iter-1) / lr_step);
    lr       = lr_init * (lr_decay ^ n_decays);

    % Mini-batch
    idx_b  = randperm(N_tr, min(batch, N_tr));
    Xb_n   = dlarray(Xn_tr(idx_b,:)',   'CB');
    Yb_n   = dlarray(Yn_tr(idx_b,:)',   'CB');
    Xb_raw = X_raw_tr(idx_b,:)';

    % Gradients via dlfeval
    [loss_val, grads, l_data, l_phy] = dlfeval(@pinn_v2_loss, ...
        net, Xb_n, Yb_n, Xb_raw, phys, lambda_phy);

    [net, avgG, avgSqG] = adamupdate(net, grads, avgG, avgSqG, iter, lr);

    loss_history(iter)   = double(extractdata(loss_val));
    loss_data_hist(iter) = double(extractdata(l_data));
    loss_phy_hist(iter)  = double(extractdata(l_phy));

    if mod(iter, 500) == 0
        fprintf('      iter %4d/%d  lr=%.2e  loss=%.6f  (data=%.6f  phy=%.6f)\n', ...
                iter, n_iter, lr, loss_history(iter), ...
                loss_data_hist(iter), loss_phy_hist(iter));
    end
end
mdl.train_time = toc;

% ── Evaluate ──────────────────────────────────────────────────────────────────
Yhat_tr_n  = extractdata(predict(net, dlarray(Xn_tr', 'CB')))';
Yhat_val_n = extractdata(predict(net, dlarray(Xn_val','CB')))';
Yhat_te_n  = extractdata(predict(net, dlarray(Xn_te', 'CB')))';

Yhat_tr  = Yhat_tr_n  .* ysig + ymu;
Yhat_val = Yhat_val_n .* ysig + ymu;
Yhat_te  = Yhat_te_n  .* ysig + ymu;

Y_tr  = data.X_out(data.idx_train,:);
Y_val = data.X_out(data.idx_val,:);
Y_te  = data.X_out(data.idx_test,:);

mdl.rmse_tr  = sqrt(mean((Yhat_tr  - Y_tr ).^2));
mdl.rmse_val = sqrt(mean((Yhat_val - Y_val).^2));
mdl.rmse_te  = sqrt(mean((Yhat_te  - Y_te ).^2));

% ── Store ─────────────────────────────────────────────────────────────────────
mdl.net            = net;
mdl.xmu  = xmu;  mdl.xsig = xsig;
mdl.ymu  = ymu;  mdl.ysig = ysig;
mdl.lambda_phy     = lambda_phy;
mdl.softplus_beta  = sp_beta;
mdl.loss_history   = loss_history;
mdl.loss_data_hist = loss_data_hist;
mdl.loss_phy_hist  = loss_phy_hist;
mdl.rng_seed       = rng_seed;   % [ADDED — reproducibility review, P0.4]
mdl.name           = 'PINN-v2';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s (%.4f rpm)  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(1)*30/pi, mdl.rmse_te(2));
fprintf('    RMSE val : omega=%.5f  beta=%.4f\n', ...
        mdl.rmse_val(1), mdl.rmse_val(2));
end

% ── Physics-informed loss with differentiable Cp (V2) ─────────────────────────
function [loss, grads, L_data, L_phy] = pinn_v2_loss(net, Xb_n, Yb_n, ...
                                                       Xb_raw, ph, lam)
% PINN_V2_LOSS  Combined data + physics loss with differentiable Cp
%
%   KEY DIFFERENCE FROM V1:
%   Cp is computed using softplus approximations instead of max/min clamps.
%   This ensures the gradient dL_phy/dtheta is non-zero whenever the
%   network prediction deviates from the physics-predicted omega_next,
%   even at Cp boundary points.
%
%   softplus(x, beta) = (1/beta)*log(1 + exp(beta*x))
%   Approximates max(0,x) with smoothness controlled by beta.
%   Higher beta = sharper transition = closer to hard clamp.
%
%   Cp polynomial clamp (V2):
%     Cp_raw    = c1*(c2/li - c3*beta - c4)*exp(-c5/li) + c6*lambda
%     Cp_lower  = softplus(Cp_raw, beta)          ≈ max(0, Cp_raw)
%     Cp_clamped = Betz - softplus(Betz-Cp_lower, beta)  ≈ min(Betz, Cp_lower)
%   Both operations are differentiable → dlgradient propagates through Cp.

Ypred = forward(net, Xb_n);   % [2 x batch]
L_data = mean((Ypred - Yb_n).^2, 'all');

% ── Physical constants ────────────────────────────────────────────────────────
BETZ   = 16/27;
sp_b   = ph.sp_beta;   % softplus sharpness

% ── Raw physical quantities (non-differentiable inputs — used as targets) ─────
omega_raw = Xb_raw(1,:);           % [rad/s]
beta_raw  = Xb_raw(2,:);           % [deg]
V_raw     = max(Xb_raw(3,:), 0.5); % [m/s]

% ── Cp polynomial with softplus clamps (DIFFERENTIABLE) ───────────────────────
%    TSR — clamped to calibration domain using softplus
%    lambda in [2, 13] via two softplus ops
lambda_raw = ph.R * omega_raw ./ V_raw;
lambda_lo  = 2  + softplus_fn(lambda_raw - 2,  sp_b);   % ≥ 2
lambda_cl  = 13 - softplus_fn(13 - lambda_lo,   sp_b);  % ≤ 13

%    Beta in [0, 25] via two softplus ops
beta_lo    = softplus_fn(beta_raw,        sp_b);         % ≥ 0
beta_cl    = 25 - softplus_fn(25-beta_lo, sp_b);         % ≤ 25

%    Jonkman polynomial intermediate variable
li_inv = 1./(lambda_cl + 0.08*beta_cl) - 0.035./(beta_cl.^3 + 1);
li     = 1./(li_inv + 1e-9);

%    Raw Cp polynomial
c1=0.5176; c2=116; c3=0.4; c4=5; c5=21; c6=0.0068;
Cp_raw = c1*(c2./li - c3*beta_cl - c4).*exp(-c5./li) + c6*lambda_cl;

%    Differentiable Cp clamp to [0, Betz]
Cp_lo  = softplus_fn(Cp_raw,        sp_b);     % ≈ max(0, Cp_raw)
Cp     = BETZ - softplus_fn(BETZ-Cp_lo, sp_b); % ≈ min(Betz, Cp_lo)

% ── Aerodynamic torque [N.m] ──────────────────────────────────────────────────
Ta = 0.5 * ph.rho * ph.A_rotor .* Cp .* V_raw.^3 ./ (omega_raw + 1e-6);

% ── Generator torque — Region II/III switching (differentiable approx) ────────
%    Hard switch: Tg = K_opt*omega^2 if omega < omega_r, else N*Tg_rated
%    Approximated with sigmoid blending for differentiability:
%    Tg = sigmoid(s*(omega-omega_r)) * N*Tg_rated
%       + (1-sigmoid(s*(omega-omega_r))) * K_opt*omega^2
%    With s=100: transition width ~ 0.02 rad/s (negligible vs physical scale)
s      = 100;
sig    = 1 ./ (1 + exp(-s*(omega_raw - ph.omega_r)));   % ≈ 1 in Region III
Tg_lss = sig .* (ph.N_gear * ph.Tg_rated) + ...
         (1-sig) .* (ph.K_opt * omega_raw.^2);

% ── Omega next from ODE ───────────────────────────────────────────────────────
omega_next_phys = omega_raw + (ph.dt/ph.J) .* ...
    (Ta - Tg_lss - ph.Br*omega_raw);

% ── Physics residual in normalised space ──────────────────────────────────────
omega_next_n = (omega_next_phys - ph.ymu(1)) ./ ph.ysig(1);
L_phy        = mean((Ypred(1,:) - dlarray(omega_next_n,'CB')).^2, 'all');

% ── Total loss ────────────────────────────────────────────────────────────────
loss  = (1-lam)*L_data + lam*L_phy;
grads = dlgradient(loss, net.Learnables);
end

% ── Softplus helper (differentiable via dlarray) ──────────────────────────────
function y = softplus_fn(x, beta)
% SOFTPLUS_FN  Smooth approximation of max(0, x)
%   y = (1/beta) * log(1 + exp(beta*x))
%   Numerically stable: for large beta*x, log(1+exp(z)) ≈ z
%   Uses log1p for numerical stability: log(1+exp(x)) = log1p(exp(x))
%   but for large x, use x directly to avoid overflow.
%
%   Compatible with dlarray — fully differentiable.
    y = (1/beta) .* log(1 + exp(beta .* x));
end
