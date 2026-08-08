function xnext = sf_tcn(x, u, V, mdl)
% SF_TCN  State function for TCN-MPC
%
%   xnext = sf_tcn(x, u, V, mdl)
%
%   nlmpc calls: sf_tcn(x, u, p1, p2)
%     p1 = V    wind speed [m/s]
%     p2 = mdl  trained TCN model struct from stage2_train_tcn
%
%   NumberOfParameters = 2
%
%   SEQUENCE BUFFER MANAGEMENT
%     The sliding window buffer is stored in mdl.seq_buf and updated
%     externally by stage3_run_simulation_v2 before each nlmpcmove call.
%     This is different from sf_lstm.m which passed seq_buf as a separate
%     parameter — here the buffer is embedded in mdl to keep
%     NumberOfParameters=2 (same as LLNFM, GP-v2, PINN-v2).
%
%   INFERENCE FORMAT — R2024a confirmed
%     TCN uses dlarray direct with label 'CTB' = [features x time x batch].
%     This avoids the ~48ms overhead of minibatchpredict for sequenceInputLayer.
%     Confirmed: predict(net, dlarray([4 x L x 1], 'CTB')) → [2 x 1] CB.
%     After extractdata: reshape to [2 x 1] → [1 x 2] → denormalise.
%
%   SPEED
%     1.56ms/call (measured R2024a) vs LSTM 180.5ms/call.
%     Compatible with real-time MPC at Ts=0.1s.
%
%   SEE ALSO
%     stage2_train_tcn, stage3_run_simulation_v2, stage3_design_controllers_v2

% ── Update sliding window buffer ──────────────────────────────────────────────
%    Drop oldest row, append current state+input+wind
new_row    = [x(1), x(2), V, u(1)];
buf_new    = [mdl.seq_buf(2:end, :); new_row];   % [seq_len x 4]

% ── Normalise ─────────────────────────────────────────────────────────────────
buf_n = (buf_new - mdl.xmu) ./ mdl.xsig;         % [seq_len x 4]

% ── Reshape for TCN: [features x time x batch] = [4 x seq_len x 1] ───────────
buf_CTB = reshape(buf_n', 4, mdl.seq_len, 1);     % [4 x L x 1]
X_dl    = dlarray(buf_CTB, 'CTB');

% ── Forward pass via dlarray direct (avoids minibatchpredict overhead) ─────────
yn_dl  = predict(mdl.net, X_dl);                  % [2 x 1] CB
yn     = extractdata(yn_dl);                       % [2 x 1] double

% ── Denormalise ───────────────────────────────────────────────────────────────
xnext = yn .* mdl.ysig' + mdl.ymu';               % [2 x 1]
end
