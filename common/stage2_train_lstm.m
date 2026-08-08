function mdl = stage2_train_lstm(data, cfg)
% STAGE2_TRAIN_LSTM  Train LSTM surrogate for wind turbine state prediction
%
%   mdl = stage2_train_lstm(data, cfg)
%
%   INPUTS
%     data   struct from stage1_generate_data
%     cfg    struct from stage0_config
%
%   OUTPUT  mdl struct fields:
%     net          trained dlnetwork
%     seq_len      sequence window length [steps]
%     xmu, xsig    input normalisation  (shared from data.norm)
%     ymu, ysig    output normalisation (shared from data.norm)
%     rmse_tr      [1x2] RMSE on training set
%     rmse_val     [1x2] RMSE on validation set
%     rmse_te      [1x2] RMSE on test set
%     train_time   total training time [s]
%     rng_seed     random seed set before training, for reproducibility
%                  [ADDED — reproducibility review, P0.4]
%     name         'LSTM'
%
%   REPRODUCIBILITY NOTE [ADDED — reproducibility review, P0.4]
%     dlnetwork weight initialisation and trainnet's mini-batch
%     shuffling both draw from MATLAB's global random state. Earlier
%     versions of this script did not set rng() before training, so
%     repeated runs produced qualitatively similar but numerically
%     different trained weights (and hence slightly different RMSE
%     values) each time. This version fixes rng(cfg.data.split_seed)
%     immediately before network construction and training, and
%     records the seed used in the returned mdl struct, so that
%     re-running this script reproduces numerically identical results
%     (to floating-point determinism limits; see caveat below).
%
%     CAVEAT: exact bit-for-bit reproducibility across MATLAB releases
%     or hardware is not guaranteed even with a fixed seed, since
%     trainnet's underlying numerical kernels may differ across
%     releases/BLAS implementations. Reproducibility is expected
%     WITHIN a fixed MATLAB release and machine.
%
%   SEQUENCE FORMAT
%     Confirmed format for R2024a sequenceInputLayer(4) + trainnet:
%       Each sequence : [L x 4]  (time x features)
%       Cell array    : {N_seq x 1}  where each cell is [L x 4]
%       Targets       : [N_seq x 2]  numeric matrix
%     Format [4 x L] is INCORRECT for sequenceInputLayer in R2024a
%     (confirmed by diagnostic: channel dimension error).
%
%   SPLIT INTEGRITY
%     Sequences are built WITHIN each trajectory only — never crossing
%     trajectory boundaries. This uses data.traj_id to identify boundaries.
%     Trajectories are assigned to train/val/test via data.info.traj_tr/val/te.
%
%   REFERENCE
%     MATLAB Deep Learning Toolbox R2024a.

seq_len  = cfg.ml.lstm.seq_len;
n_epochs = cfg.ml.lstm.n_epochs;
hidden1  = cfg.ml.lstm.hidden1;
hidden2  = cfg.ml.lstm.hidden2;
dropout  = cfg.ml.lstm.dropout;
lr       = cfg.ml.lstm.lr;
batch    = cfg.ml.lstm.batch;

fprintf('  [LSTM]  seq_len=%d  epochs=%d  hidden=[%d %d] ...\n', ...
        seq_len, n_epochs, hidden1, hidden2);
tic;

% ── Shared normalisation from Stage 1 ────────────────────────────────────────
xmu  = data.norm.xmu;
xsig = data.norm.xsig;
ymu  = data.norm.ymu;
ysig = data.norm.ysig;

% ── Normalise ─────────────────────────────────────────────────────────────────
Xn = (data.X_in  - xmu) ./ xsig;   % [N_total x 4]
Yn = (data.X_out - ymu) ./ ysig;   % [N_total x 2]

% ── Build sequences BY TRAJECTORY ─────────────────────────────────────────────
%    Critical: sequences must not cross trajectory boundaries.
%    data.traj_id identifies which trajectory each row belongs to.
%    data.info.traj_tr/val/te lists trajectory indices for each split.
fprintf('    Building sequences by trajectory...\n');

[XSeq_tr,  Ymat_tr]  = build_sequences_by_traj(Xn, Yn, data.traj_id, ...
                            data.info.traj_tr,  data.info.N_steps, seq_len);
[XSeq_val, Ymat_val] = build_sequences_by_traj(Xn, Yn, data.traj_id, ...
                            data.info.traj_val, data.info.N_steps, seq_len);
[XSeq_te,  Ymat_te]  = build_sequences_by_traj(Xn, Yn, data.traj_id, ...
                            data.info.traj_te,  data.info.N_steps, seq_len);

fprintf('    Sequences: train=%d  val=%d  test=%d\n', ...
        numel(XSeq_tr), numel(XSeq_val), numel(XSeq_te));

% Sanity check: each sequence must be [L x 4]
assert(size(XSeq_tr{1}, 1) == seq_len, ...
    'Sequence row dimension must equal seq_len');
assert(size(XSeq_tr{1}, 2) == 4, ...
    'Sequence column dimension must equal 4 (features)');

% ── Fix random seed for reproducible weight init + minibatch shuffling ─────
% [ADDED — reproducibility review, P0.4]. Reuses the same seed as the
% Stage 1 trajectory split for a single, documented source of
% randomness per pipeline run, rather than introducing a second,
% independent seed value to track.
rng_seed = cfg.data.split_seed;
rng(rng_seed);
fprintf('    RNG seed fixed to %d before network construction/training.\n', rng_seed);

% ── Network architecture ──────────────────────────────────────────────────────
%    sequenceInputLayer(4) expects [L x 4] sequences (confirmed R2024a)
layers = [
    sequenceInputLayer(4,   'Name','input')
    lstmLayer(hidden1, 'OutputMode','sequence', 'Name','lstm1')
    dropoutLayer(dropout,   'Name','drop1')
    lstmLayer(hidden2, 'OutputMode','last',     'Name','lstm2')
    fullyConnectedLayer(2,  'Name','fc')
];
net = dlnetwork(layerGraph(layers));

% ── Training options ──────────────────────────────────────────────────────────
opts = trainingOptions('adam', ...
    'MaxEpochs',            n_epochs, ...
    'MiniBatchSize',        batch, ...
    'InitialLearnRate',     lr, ...
    'LearnRateSchedule',    'piecewise', ...
    'LearnRateDropFactor',  0.5, ...
    'LearnRateDropPeriod',  20, ...
    'GradientThreshold',    1, ...
    'ValidationData',       {XSeq_val, Ymat_val}, ...
    'ValidationFrequency',  30, ...
    'Shuffle',              'every-epoch', ...
    'Verbose',              false, ...
    'Plots',                'none');

% ── Train ─────────────────────────────────────────────────────────────────────
net = trainnet(XSeq_tr, Ymat_tr, net, 'mse', opts);
mdl.train_time = toc;

% ── Evaluate ──────────────────────────────────────────────────────────────────
Yhat_tr_n  = minibatchpredict(net, XSeq_tr,  'MiniBatchSize', 128);
Yhat_val_n = minibatchpredict(net, XSeq_val, 'MiniBatchSize', 128);
Yhat_te_n  = minibatchpredict(net, XSeq_te,  'MiniBatchSize', 128);

% Denormalise predictions
Yhat_tr  = Yhat_tr_n  .* ysig + ymu;
Yhat_val = Yhat_val_n .* ysig + ymu;
Yhat_te  = Yhat_te_n  .* ysig + ymu;

% Denormalise targets
Ytrue_tr  = Ymat_tr  .* ysig + ymu;
Ytrue_val = Ymat_val .* ysig + ymu;
Ytrue_te  = Ymat_te  .* ysig + ymu;

mdl.rmse_tr  = double(sqrt(mean((Yhat_tr  - Ytrue_tr ).^2)));
mdl.rmse_val = double(sqrt(mean((Yhat_val - Ytrue_val).^2)));
mdl.rmse_te  = double(sqrt(mean((Yhat_te  - Ytrue_te ).^2)));

% ── Store ─────────────────────────────────────────────────────────────────────
mdl.net     = net;
mdl.seq_len = seq_len;
mdl.xmu  = xmu;  mdl.xsig = xsig;
mdl.ymu  = ymu;  mdl.ysig = ysig;
mdl.rng_seed = rng_seed;   % [ADDED — reproducibility review, P0.4]
mdl.name = 'LSTM';

fprintf('    Done (%.1fs)  RMSE test: omega=%.5f rad/s  beta=%.4f deg\n', ...
        mdl.train_time, mdl.rmse_te(1), mdl.rmse_te(2));
fprintf('    RMSE val : omega=%.5f  beta=%.4f\n', ...
        mdl.rmse_val(1), mdl.rmse_val(2));
end

% ── Build sliding-window sequences within trajectory boundaries ───────────────
function [XSeq, Ymat] = build_sequences_by_traj(Xn, Yn, traj_id, ...
                                                  traj_list, N_steps, L)
% BUILD_SEQUENCES_BY_TRAJ  Build [L x 4] sequences without crossing boundaries
%
%   For each trajectory k in traj_list:
%     rows = find(traj_id == k)           % N_steps consecutive rows
%     for t = L : N_steps-1
%       XSeq{end+1} = Xn(rows(t-L+1:t), :)   % [L x 4]
%       Ymat(row,:) = Yn(rows(t+1), :)         % [1 x 2]  next step target
%
%   This guarantees no sequence crosses a trajectory boundary.
%   Format [L x 4] is required by sequenceInputLayer(4) in R2024a.

N_seq_max = numel(traj_list) * (N_steps - L);
XSeq = cell(N_seq_max, 1);
Ymat = zeros(N_seq_max, 2);
row  = 1;

for k = 1:numel(traj_list)
    traj_k = traj_list(k);
    idx_k  = find(traj_id == traj_k);   % rows for this trajectory

    if numel(idx_k) < L + 1
        continue;   % trajectory too short for even one sequence
    end

    Xk = Xn(idx_k, :);   % [N_steps x 4]
    Yk = Yn(idx_k, :);   % [N_steps x 2]

    for t = L : size(Xk, 1) - 1
        XSeq{row} = Xk(t-L+1 : t, :);   % [L x 4]  — confirmed R2024a format
        Ymat(row,:) = Yk(t+1, :);        % [1 x 2]  — next step target
        row = row + 1;
    end
end

% Trim pre-allocated arrays to actual size
XSeq = XSeq(1:row-1);
Ymat = Ymat(1:row-1, :);
end
