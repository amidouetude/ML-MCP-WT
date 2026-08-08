function xnext = sf_lstm_manual(x, u, V, mdl, seq_buf)
% SF_LSTM_MANUAL  Same as sf_lstm.m, but the forward pass is computed
% via lstm_forward_manual.m (hand-written gate equations + explicit
% recurrence), NEVER calling predict()/minibatchpredict() or touching a
% dlnetwork/dlarray object.
%
%   xnext = sf_lstm_manual(x, u, V, mdl, seq_buf)
%
%   nlmpc calls: sf_lstm_manual(x, u, p1, p2, p3)
%     p1=V, p2=mdl (must have been passed through
%     extract_lstm_weights.m first), p3=seq_buf
%
%   NumberOfParameters = 3  (matches sf_lstm.m's V1 convention: seq_buf
%   passed as an explicit parameter, not embedded in mdl)

% ── Update sliding window buffer (identical to sf_lstm.m) ──────────────────
new_row = [x(1), x(2), V, u(1)];
buf_new = [seq_buf(2:end, :); new_row];    % [seq_len x 4]

% ── Normalise ─────────────────────────────────────────────────────────────
buf_n = (buf_new - mdl.xmu) ./ mdl.xsig;   % [seq_len x 4], time-major

% ── Manual forward pass (no predict(), no dlarray) ──────────────────────────
yn = lstm_forward_manual(buf_n, mdl);   % [1 x 2]

% ── Denormalise ───────────────────────────────────────────────────────────
xnext = (yn .* mdl.ysig + mdl.ymu)';

end
