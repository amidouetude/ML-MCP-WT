function model = e5_model(family, net, nrm, opts)
%E5_MODEL  Manual double-precision prediction model of a learned family, the single prediction
%function of E5 and E6 (amendment_3.D8_evaluation_function; spec_E6_solver_O8 prediction.function,
%E6-4, E6-6): no predict(), no dlarray.
%
%   model = e5_model(family, net, nrm, opts)
%
%   family  'MLP', 'C1', 'C2', 'C3', 'C5' or 'C6' (C4 belongs to package P3)
%   net     struct of the family, from a converter of P2 or from o8_synthetic_build:
%           MLP, C1, C5  dense struct W{l}, b{l} (e5_convert_dense; C5: the residual network)
%           C2           TCN struct dil, W{l}(out, in, tap), b{l}, Wo, bo (e5_convert_tcn)
%           C3           LSTM struct H, nl, W{l}, R{l}, b{l}, Wo, bo (e5_convert_lstm)
%           C6           GP struct Xa, ell, alpha (alpha includes the kernel amplitude, e5_convert_gp)
%   nrm     mu, sd (4 x 1, inputs), mux, sdx (2 x 1, Delta x) of e5_normalisation (D2_scaling)
%   opts    struct: opts.L (C1, C2: window of L samples, L >= 2; C3: warm-up length),
%           opts.p (C5: rom_params with p.cp_mode = 'nmpc', D7)
%
%   model.name, family, nz, L
%   model.init(x_k, hist)      z0 from the measured x_k (2 x 1) and hist, the S.l_max x 4 measured
%                              [omega_r, omega_f, u, d] of k - S.l_max .. k - 1, oldest first (P1 R5):
%                              MLP, C5, C6: x_k; C1, C2: [x_k; (x, u, d) at k-1, ..., k-L+1];
%                              C3: [x_k; h and c of every layer] after the warm-up from zero states on
%                              the last L rows of hist (D3)
%   [z1, aux] = model.step(z, u, d)   one step of Ts; aux = [1, n_lambda, n_beta] (bounded
%                              evaluations of rom_step for C5, zeros for the others), as O8
%   [A, Bmv, aux] = model.jac(z, u, d, z1)   closed form for MLP, C1, C2, C3, C6
%                              (gradient.jacobians_per_arm.supplied and MLP_and_C6 amendment_6);
%                              forward differences with the rule of nlmpc for C5 (B_and_C5 option (a))
%   y = model.out(z, u, d)     normalised network output (2 x 1) of the step (tests of P2)
%   model.trace(z, u, d)       C5 only: rom_step(z, u, d, 'i', p) with its info
%
%   Outputs (D2_scaling): x_{k+1} = x_k + nrm.mux + nrm.sdx .* y for the MLP, C1, C2, C3 and C6;
%   x_{k+1} = rom_step(x_k, u, d) + nrm.sdx .* y for C5 (the residual is scaled, not centred). With
%   nrm.mux = 0 every form equals bit for bit the form of o8_model_synthetic.m (the functions below
%   are copied from its local functions, the window length 34 replaced by L).

if ~isfield(nrm, 'mux')
    error('e5_model:nrm', 'nrm must have the fields mu, sd, mux and sdx.');
end
model.family = family;
model.name = family;
model.L = [];
switch family
    case 'MLP'
        model.nz = 2;
        model.init = @(x_k, hist) init_state(x_k);
        model.step = @(z, u, d) step_learned(@(zz, ud) f_mlp(net, zz, ud, nrm), z, u, d);
        model.jac = @(z, u, d, z1) jac_supplied(@(zz, ud) j_mlp(net, zz, ud, nrm), z, u, d);
        model.out = @(z, u, d) mlp_out(net, nin(z, [u; d], nrm));
    case 'C6'
        model.nz = 2;
        model.init = @(x_k, hist) init_state(x_k);
        model.step = @(z, u, d) step_learned(@(zz, ud) f_gp(net, zz, ud, nrm), z, u, d);
        model.jac = @(z, u, d, z1) jac_supplied(@(zz, ud) j_gp(net, zz, ud, nrm), z, u, d);
        model.out = @(z, u, d) gp_out(net, nin(z, [u; d], nrm));
    case {'C1', 'C2'}
        L = opts.L;
        if ~(isscalar(L) && L >= 2 && L == round(L))
            error('e5_model:L', 'C1 and C2 need opts.L >= 2.');
        end
        model.L = L;
        model.nz = 2 + 4*(L - 1);
        if strcmp(family, 'C1')
            net_fn = @(r) mlp_out(net, r);
            netj_fn = @(r) mlp_jac(net, r);
        else
            net_fn = @(r) tcn_out_L(net, r, L);
            netj_fn = @(r) tcn_jac_L(net, r, L);
        end
        model.init = @(x_k, hist) init_window(x_k, hist, L);
        model.step = @(z, u, d) step_learned(@(zz, ud) f_win_L(net_fn, zz, ud, nrm, L), z, u, d);
        model.jac = @(z, u, d, z1) jac_supplied(@(zz, ud) j_win_L(netj_fn, zz, ud, nrm, L), z, u, d);
        model.out = @(z, u, d) net_fn(win_regressor(z, [u; d], nrm, L));
    case 'C3'
        L = opts.L;
        if ~(isscalar(L) && L >= 1 && L == round(L))
            error('e5_model:L', 'C3 needs a positive integer opts.L (warm-up length).');
        end
        model.L = L;
        model.nz = 2 + 2*net.H*net.nl;
        model.init = @(x_k, hist) lstm_warm_hist(net, x_k, hist, nrm, L);
        model.step = @(z, u, d) step_learned(@(zz, ud) f_lstm(net, zz, ud, nrm), z, u, d);
        model.jac = @(z, u, d, z1) jac_supplied(@(zz, ud) j_lstm(net, zz, ud, nrm), z, u, d);
        model.out = @(z, u, d) lstm_out(net, z, [u; d], nrm);
    case 'C5'
        p = opts.p;
        check_nmpc(p);
        model.nz = 2;
        model.init = @(x_k, hist) init_state(x_k);
        model.step = @(z, u, d) step_C5(z, u, d, p, net, nrm);
        step_fn = model.step;
        model.jac = @(z, u, d, z1) jac_forward(step_fn, z, u, d, z1);
        model.out = @(z, u, d) mlp_out(net, nin(z, [u; d], nrm));
        model.trace = @(z, u, d) rom_step(z, u, d, 'i', p);
    otherwise
        error('e5_model:family', 'Unknown family %s (MLP, C1, C2, C3, C5 or C6; C4 is in P3).', family);
end
end

% ================================ interface (P1 R5, O8 form) ==================================
function z0 = init_state(x_k)
z0 = x_k(:);
end

function z0 = init_window(x_k, hist, L)
% [x_k; (x, u, d) at k-1, ..., k-L+1]: the rows of hist from the last one backwards
hist_rows = hist(end:-1:end - L + 2, :)';
z0 = [x_k(:); hist_rows(:)];
end

function [z1, aux] = step_learned(f_case, z, u, d)
z1 = f_case(z, [u; d]);
aux = [1, 0, 0];
end

function [a_jac, b_jac, aux] = jac_supplied(J_case, z, u, d)
[a_jac, b_jac] = J_case(z, [u; d]);
aux = zeros(1, 3);
end

function [z1, aux] = step_C5(z, u, d, p, res, nrm)
% o8_model_synthetic.m step_C5: rom_step in the NMPC mode + nrm.sdx .* residual (D2, D7)
ud = [u; d];
[x1, step_info] = rom_step(z, ud(1), ud(2), 'i', p);
z1 = x1 + nrm.sdx.*mlp_out(res, nin(z, ud, nrm));
aux = [1, step_info.n_domain_lambda, step_info.n_domain_beta];
end

function check_nmpc(p)
if ~isstruct(p) || ~isfield(p, 'cp_mode') || ~(ischar(p.cp_mode) || isstring(p.cp_mode)) || ~strcmp(p.cp_mode, 'nmpc')
    error('e5_model:cpMode', 'C5 requires p.cp_mode = ''nmpc'' (amendment_3.D7_C5_physical_part).');
end
end

function [a_jac, b_jac, aux] = jac_forward(step_fn, z, u, d, z1)
% forward differences with the rule of nlmpc: copy of jac_forward of o8_model_synthetic.m
dv = 1e-6;
nz = numel(z);
x0 = z(:);
a_jac = zeros(nz, nz);
aux = zeros(1, 3);
xa = abs(x0);
xa(xa < 1) = 1;
for jstate = 1:nz
    dx = dv*xa(jstate);
    x0(jstate) = x0(jstate) + dx;
    [f_pert, aux_pert] = step_fn(x0, u, d);
    x0(jstate) = x0(jstate) - dx;
    a_jac(:, jstate) = (f_pert - z1)/dx;
    aux = aux + aux_pert;
end
ua = abs(u);
ua(ua < 1) = 1;
du = dv*ua;
u_pert = u + du;
[f_pert, aux_pert] = step_fn(x0, u_pert, d);
b_jac = (f_pert - z1)/du;
aux = aux + aux_pert;
end

% ================================ dense and GP (o8_model_synthetic.m, mux added) ==============
function s = nin(z, u, nrm)
s = ([z(1:2); u(1); u(2)] - nrm.mu)./nrm.sd;
end

function y = mlp_out(M, s)
h = s;
for l = 1:numel(M.W) - 1
    h = tanh(M.W{l}*h + M.b{l});
end
y = M.W{end}*h + M.b{end};
end

function [y, Jy] = mlp_jac(M, s)
n = numel(M.W) - 1;  H = cell(1, n);  h = s;
for l = 1:n
    h = tanh(M.W{l}*h + M.b{l});  H{l} = h;
end
y = M.W{end}*h + M.b{end};
Jy = M.W{end};
for l = n:-1:1
    Jy = (Jy.*(1 - H{l}.^2)')*M.W{l};
end
end

function z1 = f_mlp(M, z, u, nrm)
z1 = z + nrm.mux + nrm.sdx.*mlp_out(M, nin(z, u, nrm));
end

function [A, B] = j_mlp(M, z, u, nrm)
[~, Js] = mlp_jac(M, nin(z, u, nrm));
Js = nrm.sdx.*Js./nrm.sd';
A = eye(2) + Js(:, 1:2);  B = Js(:, 3);
end

function [y, Jy] = gp_out(G, s)
y = zeros(2, 1);  Jy = zeros(2, numel(s));
for o = 1:2
    D = (s' - G.Xa)./G.ell(o, :);
    k = exp(-0.5*sum(D.^2, 2));
    y(o) = G.alpha(:, o)'*k;
    if nargout > 1
        Jy(o, :) = -((G.alpha(:, o).*k)'*D)./G.ell(o, :);
    end
end
end

function z1 = f_gp(G, z, u, nrm)
z1 = z + nrm.mux + nrm.sdx.*gp_out(G, nin(z, u, nrm));
end

function [A, B] = j_gp(G, z, u, nrm)
[~, Js] = gp_out(G, nin(z, u, nrm));
Js = nrm.sdx.*Js./nrm.sd';
A = eye(2) + Js(:, 1:2);  B = Js(:, 3);
end

% ================================ window models of length L ===================================
% z = [x_k; (x, u, d) at k-1; ...; (x, u, d) at k-L+1] (2 + 4 (L - 1) values);
% regressor r = [x_k; u_k; d_k; z(3:end)] normalised per variable at every lag (D2)
function r = win_regressor(z, u, nrm, L)
r = ([z(1:2); u(1); u(2); z(3:end)] - repmat(nrm.mu, L, 1))./repmat(nrm.sd, L, 1);
end

function z1 = f_win_L(net, z, u, nrm, L)
r = ([z(1:2); u(1); u(2); z(3:end)] - repmat(nrm.mu, L, 1))./repmat(nrm.sd, L, 1);
z1 = [z(1:2) + nrm.mux + nrm.sdx.*net(r); z(1:2); u(1); u(2); z(3:end-4)];
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

% ================================ LSTM ========================================================
% z = [x_k; h_1; c_1; ...; h_nl; c_nl]; gates ordered i, f, g, o (the order of lstmLayer)
function [hn, cn, g] = lstm_cell(Ls, l, xin, h, c)
H = Ls.H;
a = Ls.W{l}*xin + Ls.R{l}*h + Ls.b{l};
g.i = 1./(1 + exp(-a(1:H)));  g.f = 1./(1 + exp(-a(H+1:2*H)));
g.g = tanh(a(2*H+1:3*H));     g.o = 1./(1 + exp(-a(3*H+1:4*H)));
cn = g.f.*c + g.i.*g.g;  g.tc = tanh(cn);  hn = g.o.*g.tc;
end

function z1 = f_lstm(Ls, z, u, nrm)
H = Ls.H;  xin = nin(z, u, nrm);  z1 = z;
for l = 1:Ls.nl
    ih = 2 + 2*H*(l-1) + (1:H);  ic = ih + H;
    [hn, cn] = lstm_cell(Ls, l, xin, z(ih), z(ic));
    z1(ih) = hn;  z1(ic) = cn;  xin = hn;
end
z1(1:2) = z(1:2) + nrm.mux + nrm.sdx.*(Ls.Wo*xin + Ls.bo);
end

function y = lstm_out(Ls, z, u, nrm)
H = Ls.H;  xin = nin(z, u, nrm);
for l = 1:Ls.nl
    ih = 2 + 2*H*(l-1) + (1:H);  ic = ih + H;
    xin = lstm_cell(Ls, l, xin, z(ih), z(ic));
end
y = Ls.Wo*xin + Ls.bo;
end

function [A, B] = j_lstm(Ls, z, u, nrm)
H = Ls.H;  nz = numel(z);
A = zeros(nz);  B = zeros(nz, 1);
xin = nin(z, u, nrm);
Din = zeros(4, nz);  Din(1, 1) = 1/nrm.sd(1);  Din(2, 2) = 1/nrm.sd(2);
Dinu = [0; 0; 1/nrm.sd(3); 0];
I = 1:H;  F = H+1:2*H;  Gg = 2*H+1:3*H;  O = 3*H+1:4*H;
for l = 1:Ls.nl
    ih = 2 + 2*H*(l-1) + (1:H);  ic = ih + H;
    c = z(ic);
    [hn, ~, g] = lstm_cell(Ls, l, xin, z(ih), c);
    dci = g.g.*g.i.*(1 - g.i);  dcf = c.*g.f.*(1 - g.f);  dcg = g.i.*(1 - g.g.^2);
    dho = g.tc.*g.o.*(1 - g.o);  dhc = g.o.*(1 - g.tc.^2);
    W = Ls.W{l};  Rm = Ls.R{l};
    Mcin = dci.*W(I, :) + dcf.*W(F, :) + dcg.*W(Gg, :);
    Mch  = dci.*Rm(I, :) + dcf.*Rm(F, :) + dcg.*Rm(Gg, :);
    Dc = Mcin*Din;  Dc(:, ih) = Dc(:, ih) + Mch;  Dc(:, ic) = Dc(:, ic) + diag(g.f);
    Dh = dhc.*Dc + dho.*(W(O, :)*Din);  Dh(:, ih) = Dh(:, ih) + dho.*Rm(O, :);
    Dcu = Mcin*Dinu;  Dhu = dhc.*Dcu + dho.*(W(O, :)*Dinu);
    A(ih, :) = Dh;  A(ic, :) = Dc;  B(ih) = Dhu;  B(ic) = Dcu;
    Din = Dh;  Dinu = Dhu;  xin = hn;
end
A(1:2, :) = nrm.sdx.*(Ls.Wo*Din);  A(1, 1) = A(1, 1) + 1;  A(2, 2) = A(2, 2) + 1;
B(1:2) = nrm.sdx.*(Ls.Wo*Dinu);
end

function z = lstm_warm_hist(Ls, x_k, hist, nrm, L)
% warm-up from zero hidden and cell states on the L measured samples k-L .. k-1 (the last L rows of
% hist), as lstm_warm of o8_model_synthetic.m with the measured history in place of a constant one
z = [hist(end - L + 1, 1:2)'; zeros(2*Ls.H*Ls.nl, 1)];
for j = 1:L
    row = hist(end - L + j, :)';
    z(1:2) = row(1:2);
    z1 = f_lstm(Ls, z, row(3:4), nrm);
    z(3:end) = z1(3:end);
end
z(1:2) = x_k(:);
end
