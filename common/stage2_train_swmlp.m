function mdl = stage2_train_swmlp(data, cfg)
% STAGE2_TRAIN_SWMLP  Train Sliding-Window MLP surrogate (SW-MLP)
%
%   mdl = stage2_train_swmlp(data, cfg)
%
%   Trains a Multi-Layer Perceptron on flattened sliding windows of the
%   input time series. This is the simplest approach to incorporate
%   temporal context without recurrence or convolution.
%
%   ARCHITECTURE
%     Input  : flattened window [seq_len * n_feat] = [40 x 1]
%              i.e. [omega(t-L+1), beta(t-L+1), V(t-L+1), u(t-L+1),
%                    omega(t-L+2), ..., omega(t), beta(t), V(t), u(t)]
%     FC1    : 64 units + ReLU
%     FC2    : 32 units + ReLU
%     Output : FC(2)  →  [omega_next, beta_next]
%
%   INFERENCE IN MPC (sf_swmlp.m)
%     Uses dlarray direct (format CB = [features x batch]),
%     exactly like PINN — featureInputLayer has no sequence overhead.
%     Confirmed R2024a: 1.34ms/call.
%
%   ROLE IN V2 BENCHMARK
%     SW-MLP is the temporal BASELINE in V2:
%       - Captures the same temporal context as TCN (seq_len=10)
%       - But without any architectural inductive bias (no causality,
%         no dilation, no weight sharing across time)
%       - If TCN outperforms SW-MLP: the convolutional structure adds value
%       - If SW-MLP ≈ TCN: the temporal context itself (not the architecture)
%         is what matters
%     This comparison is a scientific contribution in itself.
%
%   COMPARISON WITH V1 MODELS
%     V1 non-temporal models (LLNFM, GP, PINN) use a single step [4 x 1].
%     SW-MLP uses [40 x 1] — 10x more input information.
%     If SW-MLP ≈ V1 non-temporal: temporal context is uninformative
%     for this system (consistent with tau_beta = dt = 0.1s finding).
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config  (uses cfg.ml2.swmlp fields)
%
%   OUTPUT  mdl struct fields:
%     net          trained dlnetwork
%     seq_len      sequence window length [steps]
%     xmu, xsig    input normalisation  (shared from data.norm)
%     ymu, ysig    output normalisation (shared from data.norm)
%     rmse_tr      [1x2] RMSE on training set   [omega, beta]
%     rmse_val     [1x2] RMSE on validation set [omega, beta]
%     rmse_te      [1x2] RMSE on test set       [omega, beta]
%     train_time   total training time [s]
%     name         'SW-MLP'

seq_len  = cfg.ml2.swmlp.seq_len;
h1       = cfg.ml2.swmlp.hidden1;
h2       = cfg.ml2.swmlp.hidden2;
n_epochs = cfg.ml2.swmlp.n_epochs;
lr       = cfg.ml2.swmlp.lr;
batch    = cfg.ml2.swmlp.batch;
n_feat   = 4;
n_in     = seq_len * n_feat;   % = 40

fprintf('  [SW-MLP-v2]  seq=%d  input_dim=%d  hidden=[%d %d]  epochs=%d ...\n', ...
        seq_len, n_in, h1, h2, n_epochs);
tic;

% ── Shared normalisation from Stage 1 ────────────────────────────────────────
xmu  = data.norm.xmu;
xsig = data.norm.xsig;
ymu  = data.norm.ymu;
ysig = data.norm.ysig;

% ── Normalise ─────────────────────────────────────────────────────────────────
Xn = (data.X_in  - xmu) ./ xsig;
Yn = (data.X_out - ymu) ./ ysig;

% ── Build flattened windows BY TRAJECTORY ────────────────────────────────────
%    Unlike LSTM/TCN which use cell arrays of [L x 4] sequences,
%    SW-MLP uses a plain matrix [N_seq x (seq_len*n_feat)].
%    The window at time t is: [x(t-L+1); x(t-L+2); ...; x(t)] flattened.
%    Trajectory boundaries respected (no crossing).
fprintf('    Building flattened windows by trajectory...\n');
[Xmat_tr,  Ymat_tr]  = build_windows(Xn, Yn, data.traj_id, data.info.traj_tr,  data.info.N_steps, seq_len);
[Xmat_val, Ymat_val] = build_windows(Xn, Yn, data.traj_id, data.info.traj_val, data.info.N_steps, seq_len);
[Xmat_te,  Ymat_te]  = build_windows(Xn, Yn, data.traj_id, data.info.traj_te,  data.info.N_steps, seq_len);
fprintf('    Windows: train=%d  val=%d  test=%d\n', ...
        size(Xmat_tr,1), size(Xmat_val,1), size(Xmat_te,1));

% ── Network architecture ──────────────────────────────────────────────────────
%    featureInputLayer: no sequence handling — plain vector input.
%    This gives 1.34ms/call inference via dlarray (CB format).
% ── Fix random seed for reproducible weight init + minibatch shuffling ─────
% [ADDED — reproducibility review, P0.4]. Same seed source as
% stage2_train_lstm.m/stage2_train_tcn.m/stage2_train_pinn(_v2).m
% (cfg.data.split_seed).
rng_seed = cfg.data.split_seed;
rng(rng_seed);
fprintf('    RNG seed fixed to %d before network construction/training.\n', rng_seed);

layers = [
    featureInputLayer(n_in, 'Name','input', 'Normalization','none')
    fullyConnectedLayer(h1,  'Name','fc1')
    reluLayer('Name','relu1')
    fullyConnectedLayer(h2,  'Name','fc2')
    reluLayer('Name','relu2')
    fullyConnectedLayer(2,   'Name','fc_out')
];
net = dlnetwork(layerGraph(layers));
n_params = sum(cellfun(@numel, {net.Learnables.Value{:}}));
fprintf('    Parameters: %d\n', n_params);

% ── Training ──────────────────────────────────────────────────────────────────
%    featureInputLayer with trainnet: data as numeric matrices [N x features]
%    (not cell arrays — no sequence handling needed)
opts = trainingOptions('adam', ...
    'MaxEpochs',            n_epochs, ...
    'MiniBatchSize',        batch, ...
    'InitialLearnRate',     lr, ...
    'LearnRateSchedule',    'piecewise', ...
    'LearnRateDropFactor',  cfg.ml2.swmlp.lr_drop_factor, ...
    'LearnRateDropPeriod',  cfg.ml2.swmlp.lr_drop_period, ...
    'GradientThreshold',    1, ...
    'ValidationData',       {Xmat_val, Ymat_val}, ...
    'ValidationFrequency',  30, ...
    'Shuffle',              'every-epoch', ...
    'Verbose',              false, ...
    'Plots',                'none');

net = trainnet(Xmat_tr, Ymat_tr, net, 'mse', opts);
mdl.train_time = toc;

% ── Evaluate ──────────────────────────────────────────────────────────────────
%    dlarray with CB format — same path as MPC inference in sf_swmlp.m
Yhat_tr_n  = extractdata(predict(net, dlarray(Xmat_tr', 'CB')))';
Yhat_val_n = extractdata(predict(net, dlarray(Xmat_val','CB')))';
Yhat_te_n  = extractdata(predict(net, dlarray(Xmat_te', 'CB')))';

Yhat_tr  = Yhat_tr_n  .* ysig + ymu;
Yhat_val = Yhat_val_n .* ysig + ymu;
Yhat_te  = Yhat_te_n  .* ysig + ymu;

Ytrue_tr  = Ymat_tr  .* ysig + ymu;
Ytrue_val = Ymat_val .* ysig + ymu;
Ytrue_te  = Ymat_te  .* ysig + ymu;

mdl.rmse_tr  = sqrt(mean((Yhat_tr  - Ytrue_tr ).^2));
mdl.rmse_val = sqrt(mean((Yhat_val - Ytrue_val).^2));
mdl.rmse_te  = sqrt(mean((Yhat_te  - Ytrue_te ).^2));

% ── Store ─────────────────────────────────────────────────────────────────────
mdl.net     = net;
mdl.seq_len = seq_len;
mdl.n_in    = n_in;
mdl.xmu  = xmu;  mdl.xsig = xsig;
mdl.ymu  = ymu;  mdl.ysig = ysig;
mdl.rng_seed = rng_seed;   % [ADDED — reproducibility review, P0.4]
mdl.name = 'SW-MLP';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s (%.4f rpm)  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(1)*30/pi, mdl.rmse_te(2));
fprintf('    RMSE val : omega=%.5f  beta=%.4f\n', ...
        mdl.rmse_val(1), mdl.rmse_val(2));
end

% ── Build flattened sliding windows within trajectory boundaries ──────────────
function [Xmat, Ymat] = build_windows(Xn, Yn, traj_id, traj_list, N_steps, L)
% BUILD_WINDOWS  Flatten sliding windows [L x 4] → [1 x L*4] per sample
%
%   Each row of Xmat corresponds to a window ending at time t:
%   [x(t-L+1), x(t-L+2), ..., x(t)]  (chronological order, row-major)
%   Target: Ymat(row,:) = Yn(t+1,:)
%
%   Windows do NOT cross trajectory boundaries.

    N_max = numel(traj_list) * (N_steps - L);
    n_feat = size(Xn, 2);
    Xmat  = zeros(N_max, L * n_feat);
    Ymat  = zeros(N_max, size(Yn,2));
    row   = 1;

    for k = 1:numel(traj_list)
        idx_k = find(traj_id == traj_list(k));
        if numel(idx_k) < L+1, continue; end
        Xk = Xn(idx_k, :);
        Yk = Yn(idx_k, :);
        for t = L : size(Xk,1)-1
            % Flatten window: [L x 4] → [1 x 40] row-major
            window       = Xk(t-L+1:t, :);   % [L x 4]
            Xmat(row,:)  = window(:)';        % [1 x L*4]
            Ymat(row,:)  = Yk(t+1, :);
            row = row + 1;
        end
    end
    Xmat = Xmat(1:row-1, :);
    Ymat = Ymat(1:row-1, :);
end
