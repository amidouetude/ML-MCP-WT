function mdl = stage2_train_residual()
% STAGE2_TRAIN_RESIDUAL  Train a small residual-correction network for
% Piste B (nominal + learned correction, per Aswani et al. 2013).
%
%   mdl = stage2_train_residual()
%
%   ARCHITECTURE — DELIBERATELY MINIMAL
%     Input  : [omega, beta, V, u_cmd]  (4 features, same as all V1/V2
%              surrogates, shared normalisation convention)
%     Hidden : two small fully-connected layers (8 units each, tanh)
%     Output : [d_omega, d_beta]  (2 outputs — the residual correction,
%              NOT the full next state)
%     Total trainable parameters: ~130 (vs. ~1900-4800 for the V2 TCN/
%     SW-MLP surrogates) -- intentionally tiny, since the correction
%     term is expected to be a smooth, low-order function of the state
%     (see wt_step_true.m: a single added quadratic damping term), and
%     because a small network directly tests whether reducing model
%     size resolves the SQP non-convergence found in
%     test_gp_jacobian_closed_loop.m (max_iter_hits = 300/300).
%
%   INPUT
%     stage1_residual_data.mat must exist (run
%     stage1_generate_residual_data.m first).
%
%   OUTPUT  mdl struct fields:
%     net                 trained dlnetwork
%     xmu, xsig, ymu, ysig  normalisation (shared with data.norm)
%     rmse_tr/val/te      [1x2] RMSE on train/val/test sets (residual units)
%     train_time          training time [s]
%     name                'Residual-MLP'

fprintf('==========================================================\n');
fprintf('  PISTE B — Residual Network Training\n');
fprintf('==========================================================\n\n');

if ~exist('stage1_residual_data.mat', 'file')
    error(['stage1_residual_data.mat not found. Run ' ...
           'stage1_generate_residual_data() first.']);
end
data = load('stage1_residual_data.mat');

xmu = data.norm.xmu;   xsig = data.norm.xsig;
ymu = data.norm.ymu;   ysig = data.norm.ysig;

X_tr_n  = (data.X_in(data.idx_train,:) - xmu) ./ xsig;
Y_tr_n  = (data.Y_residual(data.idx_train,:) - ymu) ./ ysig;
X_val_n = (data.X_in(data.idx_val,:)   - xmu) ./ xsig;
Y_val_n = (data.Y_residual(data.idx_val,:)   - ymu) ./ ysig;
X_te_n  = (data.X_in(data.idx_test,:)  - xmu) ./ xsig;
Y_te_n  = (data.Y_residual(data.idx_test,:)  - ymu) ./ ysig;

% ── Define a deliberately tiny network ───────────────────────────────────────
layers = [
    featureInputLayer(4, 'Name', 'input')
    fullyConnectedLayer(8, 'Name', 'fc1')
    tanhLayer('Name', 'tanh1')
    fullyConnectedLayer(8, 'Name', 'fc2')
    tanhLayer('Name', 'tanh2')
    fullyConnectedLayer(2, 'Name', 'output')
];
net = dlnetwork(layers);

n_params = 0;
for i = 1:numel(net.Learnables.Value)
    n_params = n_params + numel(net.Learnables.Value{i});
end
fprintf('  Network parameters: %d (deliberately small)\n', n_params);

% ── Training options ─────────────────────────────────────────────────────────
options = trainingOptions('adam', ...
    'MaxEpochs', 100, ...
    'MiniBatchSize', 256, ...
    'InitialLearnRate', 1e-3, ...
    'ValidationData', {X_val_n, Y_val_n}, ...
    'ValidationFrequency', 20, ...
    'Verbose', true, ...
    'VerboseFrequency', 20, ...
    'Plots', 'none');

fprintf('  Training...\n');
tic;
net = trainnet(X_tr_n, Y_tr_n, net, 'mse', options);
train_time = toc;

% ── Evaluate (denormalised RMSE, residual units: rad/s and deg) ────────────
pred_tr  = predict(net, X_tr_n);
pred_val = predict(net, X_val_n);
pred_te  = predict(net, X_te_n);

Y_tr_raw  = data.Y_residual(data.idx_train,:);
Y_val_raw = data.Y_residual(data.idx_val,:);
Y_te_raw  = data.Y_residual(data.idx_test,:);

pred_tr_raw  = pred_tr  .* ysig + ymu;
pred_val_raw = pred_val .* ysig + ymu;
pred_te_raw  = pred_te  .* ysig + ymu;

rmse_tr  = sqrt(mean((pred_tr_raw  - Y_tr_raw ).^2));
rmse_val = sqrt(mean((pred_val_raw - Y_val_raw).^2));
rmse_te  = sqrt(mean((pred_te_raw  - Y_te_raw ).^2));

fprintf('\n  Done (%.1fs)\n', train_time);
fprintf('  RMSE test: d_omega=%.6f rad/s (%.4f rpm)  d_beta=%.4f deg\n', ...
    rmse_te(1), rmse_te(1)*30/pi, rmse_te(2));

% ── Reference: RMSE of the NOMINAL model alone (i.e., "predicting
%    zero correction") — this is the baseline the residual net must
%    beat to be useful at all. ────────────────────────────────────────────────
rmse_zero_correction = sqrt(mean(Y_te_raw.^2));
fprintf('  Reference (zero correction / nominal model alone): d_omega=%.6f rad/s  d_beta=%.4f deg\n', ...
    rmse_zero_correction(1), rmse_zero_correction(2));
fprintf('  Improvement: %.1f%% (omega), %.1f%% (beta)\n', ...
    100*(1 - rmse_te(1)/rmse_zero_correction(1)), ...
    100*(1 - rmse_te(2)/rmse_zero_correction(2)));

mdl.net        = net;
mdl.xmu = xmu; mdl.xsig = xsig; mdl.ymu = ymu; mdl.ysig = ysig;
mdl.rmse_tr    = rmse_tr;
mdl.rmse_val   = rmse_val;
mdl.rmse_te    = rmse_te;
mdl.rmse_zero_correction = rmse_zero_correction;
mdl.train_time = train_time;
mdl.n_params   = n_params;
mdl.name       = 'Residual-MLP';

save('stage2_residual_model.mat', 'mdl');
fprintf('\nSaved -> stage2_residual_model.mat\n');

end
