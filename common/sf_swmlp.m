function xnext = sf_swmlp(x, u, V, mdl)
% SF_SWMLP  State function for SW-MLP-MPC (Sliding-Window MLP)
%
%   xnext = sf_swmlp(x, u, V, mdl)
%
%   nlmpc calls: sf_swmlp(x, u, p1, p2)
%     p1 = V    wind speed [m/s]
%     p2 = mdl  trained SW-MLP model struct from stage2_train_swmlp
%
%   NumberOfParameters = 2  (same as LLNFM, GP-v2, PINN-v2, TCN)
%
%   INFERENCE FORMAT — R2024a confirmed
%     SW-MLP uses featureInputLayer(40) — plain vector, no sequence handling.
%     Input: flattened window [seq_len*n_feat x 1] = [40 x 1]
%     dlarray format: CB = [features x batch] = [40 x 1]
%     predict(net, dlarray([40 x 1], 'CB')) → [2 x 1] CB
%     Confirmed: 1.34ms/call — fastest surrogate in V2 benchmark.
%
%   WINDOW LAYOUT
%     The flattened window is ordered chronologically (oldest first):
%     [omega(t-L+1), beta(t-L+1), V(t-L+1), u(t-L+1),
%      omega(t-L+2), ...,
%      omega(t),     beta(t),     V(t),     u(t)]
%     This matches the layout built by build_windows() in stage2_train_swmlp.m.
%
%   BUFFER MANAGEMENT
%     Same strategy as sf_tcn.m: buffer embedded in mdl.seq_buf [seq_len x 4].
%     Updated at each call (drop oldest row, append current state).
%     External initialisation in stage3_run_simulation_v2 before nlmpcmove.
%
%   SEE ALSO
%     stage2_train_swmlp, sf_tcn, stage3_run_simulation_v2

% ── Update sliding window buffer ──────────────────────────────────────────────
new_row = [x(1), x(2), V, u(1)];
buf_new = [mdl.seq_buf(2:end, :); new_row];   % [seq_len x 4]

% ── Normalise ─────────────────────────────────────────────────────────────────
buf_n = (buf_new - mdl.xmu) ./ mdl.xsig;      % [seq_len x 4]

% ── Flatten window: [seq_len x 4] → [seq_len*4 x 1] — chronological order ────
feat = buf_n(:)';          % row-major flatten: [1 x 40]
%     buf_n(:) stacks columns first in MATLAB → need to match build_windows
%     build_windows uses window(:)' which is also column-major flatten
%     → same ordering: [omega_1,beta_1,V_1,u_1, omega_2,..., omega_L,beta_L,V_L,u_L]
%     This is consistent: both training and inference use MATLAB's column-major (:)

% ── Forward pass via dlarray CB (no sequence overhead) ────────────────────────
X_dl   = dlarray(feat', 'CB');                 % [40 x 1]
yn_dl  = predict(mdl.net, X_dl);              % [2 x 1] CB
yn     = extractdata(yn_dl);                   % [2 x 1] double

% ── Denormalise ───────────────────────────────────────────────────────────────
xnext = yn .* mdl.ysig' + mdl.ymu';           % [2 x 1]
end
