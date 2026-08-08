function mdl = stage2_train_tcn(data, cfg)
% STAGE2_TRAIN_TCN  Train Temporal Convolutional Network (TCN) surrogate
%
%   mdl = stage2_train_tcn(data, cfg)
%
%   Trains a TCN for one-step-ahead prediction of wind turbine states.
%   TCN uses dilated causal convolutions to capture temporal dependencies
%   across a receptive field larger than the sequence length, without the
%   sequential computation bottleneck of LSTM.
%
%   ARCHITECTURE
%     Input  : sequence [seq_len x 4]  (time x features)
%     Block 1: Conv1D(kernel=3, filters=16, dilation=1) + LN + ReLU + Drop
%     Block 2: Conv1D(kernel=3, filters=16, dilation=2) + LN + ReLU + Drop
%     Block 3: Conv1D(kernel=3, filters=16, dilation=4) + LN + ReLU
%     Pool   : globalAveragePooling1dLayer  (collapses time dimension)
%     Output : FC(2)  →  [omega_next, beta_next]
%
%   Receptive field = 1 + (kernel-1)*(1+2+4) = 15 > seq_len=10  (OK)
%   This means every output sees all 10 input timesteps.
%
%   INFERENCE IN MPC (sf_tcn.m)
%     Uses dlarray direct (format CTB = [features x time x batch]),
%     NOT minibatchpredict (which has ~48ms overhead per call).
%     Confirmed R2024a: 1.56ms/call vs LSTM 180.5ms/call (115x speedup).
%     [UPDATE — see paper Section 5.4/Appendix: this isolated latency
%     figure was later found NOT to be predictive of closed-loop SQP
%     cost; see the manual predict()-bypass diagnostic and
%     piste_B_nominal_correction/extract_tcn_weights.m for the
%     vectorized manual forward pass ultimately used in closed loop.]
%
%   SEQUENCE FORMAT — R2024a confirmed
%     sequenceInputLayer(4) with trainnet expects [L x 4] per cell
%     (same as LSTM, confirmed by diagnostic).
%     For dlarray inference: reshape to [4 x L x 1] with label 'CTB'.
%
%   COMPARISON WITH V1 LSTM
%     LSTM failed operationally (180ms/call) due to sequential computation.
%     TCN parallelises across time via convolutions — same temporal context
%     (seq_len=10), dramatically lower inference cost.
%
%   REPRODUCIBILITY NOTE [ADDED — reproducibility review, P0.4]
%     dlnetwork weight initialisation and trainnet's mini-batch
%     shuffling both draw from MATLAB's global random state. Earlier
%     versions of this script did not set rng() before training. This
%     version fixes rng(cfg.data.split_seed) immediately before network
%     construction/training and records the seed in the returned mdl
%     struct (mdl.rng_seed), for the same reproducibility rationale
%     documented in stage2_train_lstm.m. Reproducibility is expected
%     WITHIN a fixed MATLAB release and machine, not necessarily across
%     releases/hardware.
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config  (uses cfg.ml2.tcn fields)
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
%     rng_seed     random seed set before training [ADDED — P0.4]
%     name         'TCN'
%
%   REFERENCE
%     Bai, S. et al. (2018). An empirical evaluation of generic convolutional
%     and recurrent networks for sequence modeling. arXiv:1803.01271.

seq_len  = cfg.ml2.tcn.seq_len;
n_filt   = cfg.ml2.tcn.n_filters;
kern     = cfg.ml2.tcn.kernel;
drop     = cfg.ml2.tcn.dropout;
n_epochs = cfg.ml2.tcn.n_epochs;
lr       = cfg.ml2.tcn.lr;
batch    = cfg.ml2.tcn.batch;

fprintf('  [TCN-v2]  seq=%d  filters=%d  kernel=%d  epochs=%d ...\n', ...
        seq_len, n_filt, kern, n_epochs);
tic;

% ── Shared normalisation from Stage 1 ────────────────────────────────────────
xmu  = data.norm.xmu;
xsig = data.norm.xsig;
ymu  = data.norm.ymu;
ysig = data.norm.ysig;

% ── Normalise ─────────────────────────────────────────────────────────────────
Xn = (data.X_in  - xmu) ./ xsig;
Yn = (data.X_out - ymu) ./ ysig;

% ── Build sequences BY TRAJECTORY ────────────────────────────────────────────
%    Same strategy as LSTM: no crossing of trajectory boundaries.
%    Format [L x 4] per cell (confirmed R2024a for sequenceInputLayer).
fprintf('    Building sequences by trajectory...\n');
[XSeq_tr,  Ymat_tr]  = build_seq(Xn, Yn, data.traj_id, data.info.traj_tr,  data.info.N_steps, seq_len);
[XSeq_val, Ymat_val] = build_seq(Xn, Yn, data.traj_id, data.info.traj_val, data.info.N_steps, seq_len);
[XSeq_te,  Ymat_te]  = build_seq(Xn, Yn, data.traj_id, data.info.traj_te,  data.info.N_steps, seq_len);
fprintf('    Sequences: train=%d  val=%d  test=%d\n', ...
        numel(XSeq_tr), numel(XSeq_val), numel(XSeq_te));

% ── Fix random seed for reproducible weight init + minibatch shuffling ─────
% [ADDED — reproducibility review, P0.4]. Same seed source as
% stage2_train_lstm.m (cfg.data.split_seed) for a single documented
% source of randomness per pipeline run.
rng_seed = cfg.data.split_seed;
rng(rng_seed);
fprintf('    RNG seed fixed to %d before network construction/training.\n', rng_seed);

% ── Network architecture ──────────────────────────────────────────────────────
%    globalAveragePooling1dLayer collapses time dimension → output [n_filt x 1]
%    This is equivalent to taking the mean activation across all timesteps,
%    providing a fixed-size representation regardless of sequence length.
layers = [
    sequenceInputLayer(4, 'Name','input')

    % Block 1 — dilation 1
    convolution1dLayer(kern, n_filt, 'DilationFactor',1, ...
        'Padding','causal', 'Name','conv1')
    layerNormalizationLayer('Name','ln1')
    reluLayer('Name','relu1')
    dropoutLayer(drop, 'Name','drop1')

    % Block 2 — dilation 2
    convolution1dLayer(kern, n_filt, 'DilationFactor',2, ...
        'Padding','causal', 'Name','conv2')
    layerNormalizationLayer('Name','ln2')
    reluLayer('Name','relu2')
    dropoutLayer(drop, 'Name','drop2')

    % Block 3 — dilation 4
    convolution1dLayer(kern, n_filt, 'DilationFactor',4, ...
        'Padding','causal', 'Name','conv3')
    layerNormalizationLayer('Name','ln3')
    reluLayer('Name','relu3')

    % Collapse time dimension → fixed-size feature vector
    globalAveragePooling1dLayer('Name','gap')

    % Output projection
    fullyConnectedLayer(2, 'Name','fc')
];
net = dlnetwork(layerGraph(layers));
n_params = sum(cellfun(@numel, {net.Learnables.Value{:}}));
fprintf('    Parameters: %d\n', n_params);

% ── Training ──────────────────────────────────────────────────────────────────
opts = trainingOptions('adam', ...
    'MaxEpochs',            n_epochs, ...
    'MiniBatchSize',        batch, ...
    'InitialLearnRate',     lr, ...
    'LearnRateSchedule',    'piecewise', ...
    'LearnRateDropFactor',  cfg.ml2.tcn.lr_drop_factor, ...
    'LearnRateDropPeriod',  cfg.ml2.tcn.lr_drop_period, ...
    'GradientThreshold',    1, ...
    'ValidationData',       {XSeq_val, Ymat_val}, ...
    'ValidationFrequency',  30, ...
    'Shuffle',              'every-epoch', ...
    'Verbose',              false, ...
    'Plots',                'none');

net = trainnet(XSeq_tr, Ymat_tr, net, 'mse', opts);
mdl.train_time = toc;

% ── Evaluate ──────────────────────────────────────────────────────────────────
%    Use dlarray direct for evaluation (same path as MPC inference).
%    Reshape sequences: cell {[L x 4]} → dlarray [4 x L x N] 'CTB'
Yhat_tr  = predict_tcn(net, XSeq_tr,  ymu, ysig);
Yhat_val = predict_tcn(net, XSeq_val, ymu, ysig);
Yhat_te  = predict_tcn(net, XSeq_te,  ymu, ysig);

Ytrue_tr  = Ymat_tr  .* ysig + ymu;
Ytrue_val = Ymat_val .* ysig + ymu;
Ytrue_te  = Ymat_te  .* ysig + ymu;

mdl.rmse_tr  = sqrt(mean((Yhat_tr  - Ytrue_tr ).^2));
mdl.rmse_val = sqrt(mean((Yhat_val - Ytrue_val).^2));
mdl.rmse_te  = sqrt(mean((Yhat_te  - Ytrue_te ).^2));

% ── Store ─────────────────────────────────────────────────────────────────────
mdl.net     = net;
mdl.seq_len = seq_len;
mdl.xmu  = xmu;  mdl.xsig = xsig;
mdl.ymu  = ymu;  mdl.ysig = ysig;
mdl.rng_seed = rng_seed;   % [ADDED — reproducibility review, P0.4]
mdl.name = 'TCN';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s (%.4f rpm)  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(1)*30/pi, mdl.rmse_te(2));
fprintf('    RMSE val : omega=%.5f  beta=%.4f\n', ...
        mdl.rmse_val(1), mdl.rmse_val(2));
end

% ── Build sequences within trajectory boundaries ──────────────────────────────
function [XSeq, Ymat] = build_seq(Xn, Yn, traj_id, traj_list, N_steps, L)
    N_max = numel(traj_list) * (N_steps - L);
    XSeq  = cell(N_max, 1);
    Ymat  = zeros(N_max, 2);
    row   = 1;
    for k = 1:numel(traj_list)
        idx_k = find(traj_id == traj_list(k));
        if numel(idx_k) < L+1, continue; end
        Xk = Xn(idx_k, :);
        Yk = Yn(idx_k, :);
        for t = L : size(Xk,1)-1
            XSeq{row}   = Xk(t-L+1:t, :);   % [L x 4] — confirmed R2024a
            Ymat(row,:) = Yk(t+1, :);
            row = row + 1;
        end
    end
    XSeq = XSeq(1:row-1);
    Ymat = Ymat(1:row-1, :);
end

% ── Batch prediction via dlarray (avoids minibatchpredict overhead) ───────────
function Yhat = predict_tcn(net, XSeq, ymu, ysig)
    N = numel(XSeq);
    L = size(XSeq{1}, 1);
    C = size(XSeq{1}, 2);
    % Stack into [C x L x N] then use 'CTB' label
    X_arr = zeros(C, L, N);
    for i = 1:N
        X_arr(:,:,i) = XSeq{i}';   % transpose [L x C] → [C x L]
    end
    X_dl  = dlarray(X_arr, 'CTB');
    Yn_dl = predict(net, X_dl);    % [2 x 1 x N] CB? — extract and reshape
    Yn    = extractdata(Yn_dl);
    Yn    = reshape(Yn, 2, N)';    % [N x 2]
    Yhat  = Yn .* ysig + ymu;
end
