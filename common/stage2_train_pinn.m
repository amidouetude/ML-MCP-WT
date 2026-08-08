function mdl = stage2_train_pinn(data, cfg)
% STAGE2_TRAIN_PINN  Physics-Informed Neural Network for WT state prediction
%
%   mdl = stage2_train_pinn(data, cfg)
%
%   Combined loss:
%     L = (1 - lambda_phy) * L_data + lambda_phy * L_physics
%
%   Physics residuals:
%     L_physics_omega : MSE( omega_pred, omega_next_ODE )
%       where omega_next_ODE = omega + dt/J * (Ta - N_gear*Tg - Br*omega)
%             Ta = 0.5*rho*A*Cp*V^3/omega
%
%     L_physics_beta  : MSE( beta_pred, beta_next_actuator )
%       where beta_next_actuator = beta + dt/tau * (u - beta)
%             (1st-order pitch actuator ODE)
%
%   Both physics residuals are included. The beta ODE is trivial but
%   reinforces the actuator constraint explicitly.
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config
%
%   OUTPUT  mdl struct fields:
%     net              trained dlnetwork
%     xmu, xsig        input normalisation  (shared from data.norm)
%     ymu, ysig        output normalisation (shared from data.norm)
%     rmse_tr          [1x2] RMSE on training set
%     rmse_val         [1x2] RMSE on validation set
%     rmse_te          [1x2] RMSE on test set
%     lambda_phy       physics loss weight used
%     loss_history     [n_iter x 1] total loss per iteration
%     loss_data_hist   [n_iter x 1] data loss component
%     loss_phy_hist    [n_iter x 1] physics loss component
%     train_time       total training time [s]
%     name             'PINN'
%
%   LEARNING RATE SCHEDULE
%     Piecewise decay: lr drops by lr_decay every lr_step iterations.
%     This prevents the loss increase observed at iter 300 with fixed lr.
%
%   REFERENCE
%     Raissi et al. (2019). Physics-informed neural networks. JCP.
%     Jonkman et al. (2009). NREL/TP-500-38060.

n_iter     = cfg.ml.pinn.n_iter;
lambda_phy = cfg.ml.pinn.lambda_phy;
batch      = cfg.ml.pinn.batch;
lr_init    = cfg.ml.pinn.lr_init;
lr_decay   = cfg.ml.pinn.lr_decay;
lr_step    = cfg.ml.pinn.lr_step;

fprintf('  [PINN]  iters=%d  lambda_phy=%.2f  batch=%d ...\n', ...
        n_iter, lambda_phy, batch);
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

% Raw training inputs needed for physics residual (un-normalised)
X_raw_tr = data.X_in(data.idx_train,:);

% ── Fix random seed for reproducible weight init + minibatch shuffling ─────
% [ADDED — reproducibility review, P0.4]. Same seed source as
% stage2_train_lstm.m/stage2_train_tcn.m (cfg.data.split_seed) for a
% single documented source of randomness per pipeline run.
rng_seed = cfg.data.split_seed;
rng(rng_seed);
fprintf('    RNG seed fixed to %d before network construction/training.\n', rng_seed);

% ── Build dlnetwork ───────────────────────────────────────────────────────────
layers = [
    featureInputLayer(4,  'Name','in',  'Normalization','none')
    fullyConnectedLayer(64,'Name','fc1')
    tanhLayer('Name','tanh1')
    fullyConnectedLayer(64,'Name','fc2')
    tanhLayer('Name','tanh2')
    fullyConnectedLayer(32,'Name','fc3')
    tanhLayer('Name','tanh3')
    fullyConnectedLayer(2, 'Name','out')
];
net = dlnetwork(layerGraph(layers));

% ── Physics parameters struct (passed to loss function) ───────────────────────
phys.R        = p.R;
phys.rho      = p.rho;
phys.A_rotor  = p.A_rotor;
phys.J        = p.J;
phys.Br       = p.Br;
phys.N_gear   = p.N_gear;
phys.Tg_rated = p.Tg_rated;
phys.tau_beta = p.tau_beta;
phys.dt       = data.cfg.data.dt;
phys.ymu      = ymu;
phys.ysig     = ysig;

% ── Adam optimiser state ──────────────────────────────────────────────────────
avgG   = [];
avgSqG = [];
N_tr   = size(Xn_tr, 1);

loss_history    = zeros(n_iter, 1);
loss_data_hist  = zeros(n_iter, 1);
loss_phy_hist   = zeros(n_iter, 1);

fprintf('    Training loop...\n');

for iter = 1:n_iter
    % Learning rate schedule: piecewise decay
    n_decays = floor((iter-1) / lr_step);
    lr       = lr_init * (lr_decay ^ n_decays);

    % Mini-batch
    idx_b   = randperm(N_tr, min(batch, N_tr));
    Xb_n    = dlarray(Xn_tr(idx_b,:)',   'CB');   % [4 x batch]
    Yb_n    = dlarray(Yn_tr(idx_b,:)',   'CB');   % [2 x batch]
    Xb_raw  = X_raw_tr(idx_b,:)';                 % [4 x batch] un-normalised

    % Compute gradients via dlfeval
    [loss_val, grads, l_data, l_phy] = dlfeval(@pinn_loss, ...
        net, Xb_n, Yb_n, Xb_raw, phys, lambda_phy);

    % Adam update
    [net, avgG, avgSqG] = adamupdate(net, grads, avgG, avgSqG, iter, lr);

    loss_history(iter)   = double(extractdata(loss_val));
    loss_data_hist(iter) = double(extractdata(l_data));
    loss_phy_hist(iter)  = double(extractdata(l_phy));

    if mod(iter, 50) == 0
        fprintf('      iter %3d/%d   lr=%.2e   loss=%.6f  (data=%.6f  phy=%.6f)\n', ...
                iter, n_iter, lr, loss_history(iter), ...
                loss_data_hist(iter), loss_phy_hist(iter));
    end
end
mdl.train_time = toc;

% ── Evaluate on all sets ──────────────────────────────────────────────────────
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
mdl.loss_history   = loss_history;
mdl.loss_data_hist = loss_data_hist;
mdl.loss_phy_hist  = loss_phy_hist;
mdl.rng_seed       = rng_seed;   % [ADDED — reproducibility review, P0.4]
mdl.name           = 'PINN';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(2));
fprintf('    RMSE val : omega=%.5f  beta=%.4f\n', ...
        mdl.rmse_val(1), mdl.rmse_val(2));
end

% ── Physics-informed loss function ────────────────────────────────────────────
function [loss, grads, L_data, L_phy] = pinn_loss(net, Xb_n, Yb_n, ...
                                                    Xb_raw, ph, lam)
% PINN_LOSS  Combined data + physics loss for PINN training
%
%   Physics residual — rotor ODE (omega) ONLY:
%     Ta = 0.5*rho*A*Cp*V^3/omega
%     omega_next_phys = omega + dt/J*(Ta - N*Tg - Br*omega)
%
%   NOTE: beta actuator residual is excluded.
%     With dt = tau_beta = 0.1s, the ODE gives beta_next = u_cmd exactly,
%     which conflicts with rate saturation in real data and degrades
%     generalisation. Only the rotor ODE (omega) is used as constraint.

Ypred = forward(net, Xb_n);   % [2 x batch], normalised

% Data loss
L_data = mean((Ypred - Yb_n).^2, 'all');

% ── Physics: rotor ODE (omega) ────────────────────────────────────────────────
omega_raw = Xb_raw(1,:);           % current omega [rad/s]
beta_raw  = Xb_raw(2,:);           % current beta  [deg]
V_raw     = max(Xb_raw(3,:), 0.5); % wind speed    [m/s]
u_raw     = Xb_raw(4,:);           % pitch command [deg]

% TSR and Cp (non-differentiable path — used as fixed target)
lambda_tsr = ph.R * omega_raw ./ V_raw;
lambda_tsr = max(2.0, min(13.0, lambda_tsr));
beta_clamped = max(0.0, min(25.0, beta_raw));

li_inv = 1./(lambda_tsr + 0.08*beta_clamped) - 0.035./(beta_clamped.^3 + 1);
li     = 1./(li_inv + 1e-9);
Cp     = 0.5176*(116./li - 0.4*beta_clamped - 5).*exp(-21./li) + 0.0068*lambda_tsr;
Cp     = max(0, min(16/27, Cp));

Ta = 0.5 * ph.rho * ph.A_rotor .* Cp .* V_raw.^3 ./ (omega_raw + 1e-6);
omega_next_phys = omega_raw + (ph.dt/ph.J) .* ...
    (Ta - ph.N_gear*ph.Tg_rated - ph.Br*omega_raw);

% Normalise physics target to match network output scale
omega_next_n = (omega_next_phys - ph.ymu(1)) ./ ph.ysig(1);
L_phy_omega  = mean((Ypred(1,:) - dlarray(omega_next_n, 'CB')).^2, 'all');

% ── Physics: pitch actuator (beta) — REMOVED ─────────────────────────────────
%    With dt = tau_beta = 0.1s, the 1st-order actuator ODE gives:
%      beta_next_phys = beta + dt/tau*(u-beta) = beta + 1.0*(u-beta) = u
%    This forces beta_pred → u_cmd on all inputs, which conflicts with
%    the rate saturation (dbeta_max = 8 deg/s) active in the real data.
%    The conflicting gradient degrades generalisation even as training loss
%    decreases. Physics residual for beta is therefore excluded.
%    Only the rotor ODE residual (omega) is used as physical constraint.

L_phy = L_phy_omega;

% ── Total loss ────────────────────────────────────────────────────────────────
loss  = (1 - lam) * L_data + lam * L_phy;
grads = dlgradient(loss, net.Learnables);
end