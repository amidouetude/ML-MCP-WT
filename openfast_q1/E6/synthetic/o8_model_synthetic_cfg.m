function model = o8_model_synthetic_cfg(syn, cfg, p, net)
%O8_MODEL_SYNTHETIC_CFG  O8 prediction model of one intermediate configuration of spec_E6_solver_O8
%(i_intermediate option (a) for C2 and C3, amendment_7 for C5), in the form of o8_model_synthetic.
%
%   model = o8_model_synthetic_cfg(syn, cfg, p)
%   model = o8_model_synthetic_cfg(syn, cfg, p, net)
%
%   syn   o8_synthetic_build()
%   cfg   one element of o8_synthetic_cfg_list
%   p     rom_params(cp_table_file) with p.cp_mode = 'nmpc' (C5); not used by C2 and C3
%   net   optional weights replacing the draw of o8_synthetic_cfg_draws (tests only)
%
%   C2  window model of length cfg.L with a TCN (kernel 3, 64 channels, dilations cfg.dil): f_win,
%       j_win, r2seq, tcn_out and tcn_jac of timing_E6_nlmpc.m (l.280-298, l.309-312, l.329-351)
%       copied with the only change 34 -> L (names suffixed _L, L passed as last argument), tcn_fwd
%       (l.314-327) verbatim; supplied Jacobian; z_0 = init(x, mv, md) = [x; repmat([x; mv; md],
%       L - 1, 1)] (timing l.62 with 33 = L - 1); step and jac wrappers as o8_model_synthetic.m;
%       weights: o8_synthetic_cfg_draws('tcn', cfg.dil) unless net is given.
%   C3  o8_model_synthetic(syn_cfg, 'C3B_sup', p), committed and unchanged, with syn_cfg.lsB the
%       LSTM of the configuration: o8_synthetic_cfg_draws('lstm', cfg.H, cfg.nl) unless net is given;
%       f_lstm, j_lstm and lstm_warm are already general in H and the number of layers; warm-up
%       over 34 samples; supplied Jacobian.
%   C5  o8_model_synthetic(syn_cfg, 'C5_num', p), committed and unchanged, with syn_cfg.res the
%       residual of the configuration: syn.res for 3 x 128 (amendment_7.C5_weights), otherwise
%       o8_synthetic_cfg_draws('mlp', cfg.widths), unless net is given; numerical Jacobian; trace.
%   model.nz, run_id, label, jacobian, family and cfg are set from cfg.

if nargin < 4
    net = [];
end
switch cfg.family
    case 'C2'
        if isempty(net)
            net = o8_synthetic_cfg_draws('tcn', cfg.dil);
        end
        L = cfg.L;
        nrm = syn.nrm;
        f_case = @(z,u) f_win_L(@(r) tcn_out_L(net, r, L), z, u, nrm, L);
        J_case = @(z,u) j_win_L(@(r) tcn_jac_L(net, r, L), z, u, nrm, L);
        model.name = 'C2';
        model.step = @(z, u, d) step_learned(f_case, z, u, d);
        model.jac = @(z, u, d, z1) jac_supplied(J_case, z, u, d);
        model.init = @(x, mv, md) init_window_L(x, mv, md, L);
        model.jacobian = 'supplied';
    case 'C3'
        if isempty(net)
            net = o8_synthetic_cfg_draws('lstm', cfg.H, cfg.nl);
        end
        syn_cfg = syn;
        syn_cfg.lsB = net;
        model = o8_model_synthetic(syn_cfg, 'C3B_sup', p);
    case 'C5'
        if isempty(net)
            if isequal(cfg.widths, [128 128 128])
                net = syn.res;                          % amendment_7.C5_weights
            else
                net = o8_synthetic_cfg_draws('mlp', cfg.widths);
            end
        end
        syn_cfg = syn;
        syn_cfg.res = net;
        model = o8_model_synthetic(syn_cfg, 'C5_num', p);
    otherwise
        error('o8_model_synthetic_cfg:family', 'Unknown family %s.', cfg.family);
end
model.nz = cfg.nz;
model.run_id = cfg.id;
model.label = cfg.id;
model.family = cfg.family;
model.cfg = cfg;
end

% ================================ O8 interface (as o8_model_synthetic.m) =====================
function z0 = init_window_L(x, mv, md, L)
% constant history at (x, mv, md) over L samples: timing l.62 with 33 = L - 1
z0 = [x(:); repmat([x(:); mv; md], L - 1, 1)];
end

function [z1, aux] = step_learned(f_case, z, u, d)
% f of the configuration at [MV; MD], as o8_model_synthetic.m step_learned
z1 = f_case(z, [u; d]);
aux = [1, 0, 0];
end

function [a_jac, b_jac, aux] = jac_supplied(J_case, z, u, d)
% closed-form Jacobian at [MV; MD], as o8_model_synthetic.m jac_supplied
[a_jac, b_jac] = J_case(z, [u; d]);
aux = zeros(1, 3);
end

% ================================ timing_E6_nlmpc.m, 34 -> L =================================
function z1 = f_win_L(net, z, u, nrm, L)
r = ([z(1:2); u(1); u(2); z(3:end)] - repmat(nrm.mu, L, 1))./repmat(nrm.sd, L, 1);
z1 = [z(1:2) + nrm.sdx.*net(r); z(1:2); u(1); u(2); z(3:end-4)];
end

function [A, B] = j_win_L(netj, z, u, nrm, L)
sdr = repmat(nrm.sd, L, 1);
r = ([z(1:2); u(1); u(2); z(3:end)] - repmat(nrm.mu, L, 1))./sdr;
[~, Jr] = netj(r);
Jr = nrm.sdx.*Jr./sdr';
nz = numel(z);
A = zeros(nz);  B = zeros(nz, 1);
A(1:2, 1:2) = eye(2) + Jr(:, 1:2);
A(1:2, 3:nz) = Jr(:, 5:end);
B(1:2) = Jr(:, 3);
A(3:4, 1:2) = eye(2);
B(5) = 1;
A(7:nz, 3:nz-4) = eye(nz - 6);
end

function X = r2seq_L(r, L)
% regressor (lag 0 first) to a 4 x L sequence, oldest first
X = fliplr(reshape(r, 4, L));
end

function [y, H] = tcn_fwd(T, X)
H = cell(1, numel(T.dil));  h = X;  n = size(X, 2);
for l = 1:numel(T.dil)
    P = repmat(T.b{l}, 1, n);
    for k = 0:size(T.W{l}, 3) - 1
        s = k*T.dil(l);
        if s < n
            P(:, s+1:n) = P(:, s+1:n) + T.W{l}(:, :, k+1)*h(:, 1:n-s);
        end
    end
    h = tanh(P);  H{l} = h;
end
y = T.Wo*h(:, n) + T.bo;
end

function y = tcn_out_L(T, r, L)
y = tcn_fwd(T, r2seq_L(r, L));
end

function [y, Jr] = tcn_jac_L(T, r, L)
X = r2seq_L(r, L);  n = size(X, 2);
[y, H] = tcn_fwd(T, X);
Jr = zeros(2, numel(r));
for o = 1:2
    G = zeros(size(H{end}));  G(:, n) = T.Wo(o, :)';
    for l = numel(T.dil):-1:1
        dP = G.*(1 - H{l}.^2);
        G = zeros(size(T.W{l}, 2), n);
        for k = 0:size(T.W{l}, 3) - 1
            s = k*T.dil(l);
            if s < n
                G(:, 1:n-s) = G(:, 1:n-s) + T.W{l}(:, :, k+1)'*dP(:, s+1:n);
            end
        end
    end
    Jr(o, :) = reshape(fliplr(G), 1, []);
end
end
