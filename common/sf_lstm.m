function xnext = sf_lstm(x, u, V, mdl, seq_buf)
% SF_LSTM  State function for LSTM-MPC
%
%   xnext = sf_lstm(x, u, V, mdl, seq_buf)
%
%   nlmpc calls: sf_lstm(x, u, p1, p2, p3)
%     p1 = V        wind speed [m/s]
%     p2 = mdl      trained LSTM model struct from stage2_train_lstm
%     p3 = seq_buf  [seq_len x 4] sliding window buffer of past states
%                   each row = [omega_r, beta, V_wind, u_cmd]
%
%   NumberOfParameters = 3
%
%   SEQUENCE UPDATE
%     The buffer is updated by dropping the oldest row and appending
%     the current state. The updated buffer is normalised and fed to
%     the LSTM network.
%
%   FORMAT NOTE
%     Confirmed R2024a: sequenceInputLayer(4) expects [L x 4] sequences.
%     minibatchpredict with cell input: each cell is [L x 4].

% Update sliding window buffer: drop oldest, append current
new_row = [x(1), x(2), V, u(1)];
buf_new = [seq_buf(2:end, :); new_row];    % [seq_len x 4]

% Normalise
buf_n = (buf_new - mdl.xmu) ./ mdl.xsig;  % [seq_len x 4]

% Predict — wrap in cell as required by minibatchpredict
yn = minibatchpredict(mdl.net, {buf_n}, 'MiniBatchSize', 1);  % [1 x 2]

% Denormalise
xnext = (yn .* mdl.ysig + mdl.ymu)';      % [2 x 1]
end
