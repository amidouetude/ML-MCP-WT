function xnext = sf_residual_manual(x, u, V, mdl, p, dt)
% SF_RESIDUAL_MANUAL  Same as sf_residual.m, but the learned correction
% is computed with a HAND-WRITTEN forward pass (plain matrix
% multiplication on mdl.W1/b1/W2/b2/W3/b3), NEVER calling predict() or
% touching a dlnetwork/dlarray object at simulation time.
%
%   xnext = sf_residual_manual(x, u, V, mdl, p, dt)
%
%   nlmpc calls: sf_residual_manual(x, u, p1, p2, p3, p4)
%     p1=V, p2=mdl (must have been passed through
%     extract_residual_weights.m first), p3=p, p4=dt
%
%   NumberOfParameters = 4
%
%   PURPOSE — see extract_residual_weights.m for full rationale. This
%   is the definitive test of whether predict() itself (rather than
%   network size or dlnetwork specifically) is the structural cause of
%   the catastrophic per-step SQP cost observed with EVERY predict()-
%   based surrogate tested in this project (TCN, LSTM, SW-MLP,
%   PINN-v2, GP-v2, and the 130-parameter residual network in
%   sf_residual.m) -- as opposed to LLNFM/evalfis(), which has never
%   shown this behavior.

% ── Nominal prediction (identical to sf_residual.m) ──────────────────────────
x_nominal = wt_step(x, u, V, p, dt);

% ── Learned correction — MANUAL forward pass, no predict(), no dlarray ─────
feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;   % [1x4]

h1 = tanh(mdl.W1 * featn' + mdl.b1);    % [8x1]
h2 = tanh(mdl.W2 * h1 + mdl.b2);        % [8x1]
corr_n = (mdl.W3 * h2 + mdl.b3)';       % [1x2]

correction = corr_n .* mdl.ysig + mdl.ymu;

xnext = x_nominal + correction(:);

end
