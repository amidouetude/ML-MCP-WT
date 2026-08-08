function xnext = sf_pinn_manual(x, u, V, mdl)
% SF_PINN_MANUAL  Same as sf_pinn.m, but the forward pass is computed
% via manual_forward_generic.m (plain matrix multiplication), NEVER
% calling predict() or touching a dlnetwork/dlarray object. Used for
% BOTH PINN (V1) and PINN-v2 (V2), matching sf_pinn.m's own convention
% of a shared state function differing only in mdl.net's trained
% weights.
%
%   xnext = sf_pinn_manual(x, u, V, mdl)
%
%   nlmpc calls: sf_pinn_manual(x, u, p1, p2)
%     p1 = V, p2 = mdl (must have been passed through
%     extract_dlnetwork_generic.m first)
%
%   NumberOfParameters = 2

feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;   % [1x4]

% ── Manual forward pass (no predict(), no dlarray) ──────────────────────────
yn = manual_forward_generic(featn, mdl.manual_W, mdl.manual_b, mdl.manual_act);  % [1x2]

% ── Denormalise, return as column [2x1] to match sf_pinn.m convention ──────
xnext = (yn .* mdl.ysig + mdl.ymu)';

end
