function xnext = sf_swmlp_manual(x, u, V, mdl)
% SF_SWMLP_MANUAL  Same as sf_swmlp.m, but the forward pass is computed
% via manual_forward_generic.m (plain matrix multiplication), NEVER
% calling predict() or touching a dlnetwork/dlarray object.
%
%   xnext = sf_swmlp_manual(x, u, V, mdl)
%
%   nlmpc calls: sf_swmlp_manual(x, u, p1, p2)
%     p1 = V, p2 = mdl (must have been passed through
%     extract_dlnetwork_generic.m first, with mdl.seq_buf initialised)
%
%   NumberOfParameters = 2
%
%   PREPROCESSING — identical to sf_swmlp.m
%     Sliding window buffer update, normalisation, column-major
%     flatten [seq_len*4 x 1], EXCEPT the forward pass itself uses
%     manual_forward_generic.m instead of predict(net, dlarray(...)).

% ── Update sliding window buffer (identical to sf_swmlp.m) ─────────────────
new_row = [x(1), x(2), V, u(1)];
buf_new = [mdl.seq_buf(2:end, :); new_row];

% ── Normalise ─────────────────────────────────────────────────────────────
buf_n = (buf_new - mdl.xmu) ./ mdl.xsig;

% ── Flatten window: column-major (:), identical to sf_swmlp.m ─────────────
feat = buf_n(:)';   % [1 x 40]

% ── Manual forward pass (no predict(), no dlarray) ──────────────────────────
% manual_forward_generic returns a ROW vector [1x2]
yn = manual_forward_generic(feat, mdl.manual_W, mdl.manual_b, mdl.manual_act);

% ── Denormalise (mdl.ysig, mdl.ymu are row vectors [1x2], as in sf_swmlp.m's
%    own normalisation convention) then return as column [2x1] ─────────────
xnext = (yn .* mdl.ysig + mdl.ymu)';

end
