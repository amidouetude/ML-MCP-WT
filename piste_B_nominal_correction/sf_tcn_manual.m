function xnext = sf_tcn_manual(x, u, V, mdl)
% SF_TCN_MANUAL  Same as sf_tcn.m, but the forward pass is computed via
% tcn_forward_manual.m (hand-written causal dilated convolution, layer
% norm, ReLU, pooling, FC), NEVER calling predict() or touching a
% dlnetwork/dlarray object.
%
%   xnext = sf_tcn_manual(x, u, V, mdl)
%
%   nlmpc calls: sf_tcn_manual(x, u, p1, p2)
%     p1 = V, p2 = mdl (must have been passed through
%     extract_tcn_weights.m first, with mdl.seq_buf initialised)
%
%   NumberOfParameters = 2
%
%   PREPROCESSING — identical to sf_tcn.m up to the forward pass itself

% ── Update sliding window buffer (identical to sf_tcn.m) ───────────────────
new_row = [x(1), x(2), V, u(1)];
buf_new = [mdl.seq_buf(2:end, :); new_row];   % [seq_len x 4]

% ── Normalise ─────────────────────────────────────────────────────────────
buf_n = (buf_new - mdl.xmu) ./ mdl.xsig;      % [seq_len x 4]

% ── Reshape for TCN: [features x time] = [4 x seq_len] ─────────────────────
X_ctb = buf_n';   % [4 x seq_len]

% ── Manual forward pass (no predict(), no dlarray) ──────────────────────────
yn = tcn_forward_manual(X_ctb, mdl);   % [1 x 2]

% ── Denormalise ───────────────────────────────────────────────────────────
xnext = (yn .* mdl.ysig + mdl.ymu)';

end
