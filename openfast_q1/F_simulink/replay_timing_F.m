function R = replay_timing_F(nlobj, L)
%REPLAY_TIMING_F  Per-call NMPC time by offline replay (spec_F cases.F2_nmpc_physics.timing_method).
%
%   R = replay_timing_F(nlobj, L)
%
%   L: the block inputs logged at every Ts during the closed-loop case
%      L.x (N x nx), L.lastmv (N x nmv), L.md (N x nmd), L.ref (1 x ny), L.mv_block (N x nmv),
%      L.status_block (N x 1).
%   The N calls are replayed once each, in the same order, by nlmpcmove on the same nlmpc
%   object; each call is timed alone by tic/toc.
%
%   Warm-start chain = the one of the Nonlinear MPC block in R2024a (default, no custom
%   initialization): the block feeds back its previous solution through the "xmvs_router"
%   subsystem of mpcsigdimcheck_private.slx (read 16/10/2026):
%     X0     = Xopt(k-1) rows min(3,p+1):(p+1)      (selector "Constant", Delay x_Delay)
%     MV0    = MVopt(k-1) rows 2:max(2,p)           (selector "Constant1", Delay mv_Delay)
%     Slack0 = slack(k-1) = max(Info.Slack,0)       (Delay slack_delay; nmpcblock_interface.m l.172)
%   with initial conditions at the first call: X0 = rows of ones(p+1,1)*x(1)', MV0 = rows of
%   ones(p+1,1)*lastmv(1)', Slack0 = 0 (constant "e.init_zero" of mpclib.slx).
%   The block passes them to nlmpcmove as Options.X0/MV0/Slack0 (nmpcblock_interface.m l.155-157,
%   l.163). Here the chain is rebuilt from the replay's own solutions.
%   Fidelity (spec_F timing_method): max |MV_replay - MV_block| over the N calls.
%   Limitation written in the verdict: Simulink overhead not included.

p = nlobj.PredictionHorizon;
N = size(L.x, 1);
t  = zeros(N, 1);
mv = zeros(N, size(L.mv_block, 2));
ef = zeros(N, 1);
rx  = min(3, p+1):(p+1);
rmv = 2:max(2, p);
X0  = ones(p+1, 1)*L.x(1,:);       X0  = X0(rx,:);
MV0 = ones(p+1, 1)*L.lastmv(1,:);  MV0 = MV0(rmv,:);
S0  = 0;
for k = 1:N
    opt = nlmpcmoveopt;
    opt.X0 = X0;
    opt.MV0 = MV0;
    opt.Slack0 = S0;
    x = L.x(k,:)';
    lastmv = L.lastmv(k,:)';
    md = L.md(k,:);
    tk = tic;
    [mvk, ~, info] = nlmpcmove(nlobj, x, lastmv, L.ref, md, opt);
    t(k) = toc(tk);
    mv(k,:) = mvk';
    ef(k) = info.ExitFlag;
    X0  = info.Xopt(rx,:);
    MV0 = info.MVopt(rmv,:);
    S0  = max(info.Slack, 0);
end
d = abs(mv - L.mv_block);
R = struct('time_s', t, 'median_s', median(t), 'p95_s', prctile(t, 95), ...
           'p99_s', prctile(t, 99), 'max_s', max(t), 'n_calls', N, ...
           'mv_replay', mv, 'exitflag_replay', ef, 'fidelity_max_abs_dmv', max(d(:)), ...
           'n_exitflag_differences', nnz(ef ~= L.status_block(:)));
end
