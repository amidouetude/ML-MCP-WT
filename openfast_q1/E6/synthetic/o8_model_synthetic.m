function model = o8_model_synthetic(syn, run_id, p)
%O8_MODEL_SYNTHETIC  O8 prediction model of one run of measurement (i) of spec_E6_solver_O8
%(cost_measurement_protocol.cases, jacobians, amendment_4.runs, C5_jacobian, plant_and_start), in
%the form of o8_model_B.m: the model of the case of timing_E6_nlmpc.m (sha256 3bb3d6bd...) with
%the interface of o8_solve.
%
%   model = o8_model_synthetic(syn, run_id, p)
%
%   syn      o8_synthetic_build()
%   run_id   one id of o8_synthetic_runs()
%   p        rom_params(cp_table_file) with p.cp_mode = 'nmpc' for B_num and C5_num (prediction
%            cp_fallback: B and the physical part of C5); not used by the other runs (may be [])
%
%   model.name, nz          family name and state dimension; model.run_id, label, jacobian,
%                           family as in o8_synthetic_runs
%   model.init(x, mv, md)   z_0 of the run from the measured x, the last MV and the disturbance:
%                           x(:) for B, C5, MLP and C6; the constant history
%                           [x; repmat([x; mv; md], 33, 1)] for C1, C2 and C4 (timing l.62); the
%                           warm-up lstm_warm(Ls, [x; mv; md], nrm, 34) for C3 (timing l.71, l.77);
%                           init(syn.x0, syn.beta0, syn.v_md) is the z0 of the timing case
%                           (amendment_4.plant_and_start)
%   model.step(z, u, d)     [z1, aux_row]: z1 = f(z, [u; d]) with f the function of the timing case
%                           (C(k).f, l.65-78); aux_row = [1, 0, 0] for the learned models (no lambda
%                           or beta clamp); [1, n_domain_lambda, n_domain_beta] of rom_step for B
%                           and C5, as o8_model_B
%   model.jac(z, u, d, z1)  [A, Bmv, aux_row]: supplied runs: [A, Bmv] = J(z, [u; d]) with J the
%                           closed form of the timing case (C(k).J), aux_row = [0, 0, 0] (no
%                           evaluation of model.step); numerical runs: forward differences with
%                           the rule of nlmpc, jac_forward below, a copy of o8_model_B.m l.37-60
%                           (computeJacobianState.m l.19-43), aux_row the sum over its nz + 1
%                           evaluations of model.step; B_num: o8_model_B itself (C5_jacobian:
%                           numerical for B and C5)
%   model.trace(z, u, d)    C5 only: rom_step(z, u, d, 'i', p) with its info, the physical part of
%                           C5 (solver_failure.region3_counter.prediction_side, amendment 3); B_num:
%                           the trace of o8_model_B
%
%   B_num is o8_model_B(p), unchanged, with model.init replaced by the three-argument form above
%   (same value x(:)). The model functions of timing_E6_nlmpc.m used by the runs are copied
%   verbatim below as local functions, names and bodies unchanged: l.208-210, l.221-250,
%   l.256-276, l.278-298, l.309-351, l.357-377, l.379-380 and l.390-441 (nin, mlp_out, mlp_jac,
%   f_mlp, j_mlp, gp_out, f_gp, j_gp, f_win, j_win, r2seq, tcn_fwd, tcn_out, tcn_jac, llm_core,
%   llm_out, llm_jac, lstm_cell, f_lstm, j_lstm, lstm_warm); test_o8_synthetic_models checks
%   step, jac and init bit for bit against the same functions extracted at run time from the
%   SHA-256-checked file (part (a)).

if ~((ischar(run_id) && isrow(run_id)) || (isstring(run_id) && isscalar(run_id)))
    error('o8_model_synthetic:run', 'run_id must be a character vector or a string scalar.');
end
runs = o8_synthetic_runs();
sel = find(strcmp({runs.id}, char(run_id)));
if numel(sel) ~= 1
    error('o8_model_synthetic:run', 'Unknown run_id %s.', char(run_id));
end
run_def = runs(sel);
nrm = syn.nrm;
L_HIST = 34;                                    % timing l.62 (33 + 1 samples), l.71, l.77
if syn.L ~= L_HIST
    error('o8_model_synthetic:L', 'syn.L is %g, expected %d.', syn.L, L_HIST);
end
f_case = [];
J_case = [];
switch run_def.family
    case 'B'                                    % timing l.65; o8_model_B, committed, unchanged
        model = o8_model_B(p);
        model.init = @(x, mv, md) init_state(x, mv, md);
    case 'C5'                                   % timing l.66
        check_nmpc(p);
        res = syn.res;
        model.name = 'C5';
        model.step = @(z, u, d) step_C5(z, u, d, p, res, nrm);
        model.trace = @(z, u, d) rom_step(z, u, d, 'i', p);
        model.init = @(x, mv, md) init_state(x, mv, md);
    case 'MLP'                                  % timing l.67-68
        mlp = syn.mlp;
        f_case = @(z,u) f_mlp(mlp, z, u, nrm);
        J_case = @(z,u) j_mlp(mlp, z, u, nrm);
        model.init = @(x, mv, md) init_state(x, mv, md);
    case 'C6'                                   % timing l.69-70
        gp = syn.gp;
        f_case = @(z,u) f_gp(gp, z, u, nrm);
        J_case = @(z,u) j_gp(gp, z, u, nrm);
        model.init = @(x, mv, md) init_state(x, mv, md);
    case 'C3'                                   % timing l.71-72 (lsS) and l.77-78 (lsB)
        if strcmp(run_def.id, 'C3S_sup')
            Ls = syn.lsS;
        else
            Ls = syn.lsB;
        end
        f_case = @(z,u) f_lstm(Ls, z, u, nrm);
        J_case = @(z,u) j_lstm(Ls, z, u, nrm);
        model.init = @(x, mv, md) lstm_warm(Ls, [x(:); mv; md], nrm, L_HIST);
    case 'C1'                                   % timing l.73-74
        swm = syn.swm;
        f_case = @(z,u) f_win(@(r) mlp_out(swm, r), z, u, nrm);
        J_case = @(z,u) j_win(@(r) mlp_jac(swm, r), z, u, nrm);
        model.init = @(x, mv, md) init_window(x, mv, md);
    case 'C2'                                   % timing l.75
        tcn = syn.tcn;
        f_case = @(z,u) f_win(@(r) tcn_out(tcn, r), z, u, nrm);
        J_case = @(z,u) j_win(@(r) tcn_jac(tcn, r), z, u, nrm);
        model.init = @(x, mv, md) init_window(x, mv, md);
    case 'C4'                                   % timing l.76
        llm = syn.llm;
        f_case = @(z,u) f_win(@(r) llm_out(llm, r), z, u, nrm);
        J_case = @(z,u) j_win(@(r) llm_jac(llm, r), z, u, nrm);
        model.init = @(x, mv, md) init_window(x, mv, md);
    otherwise
        error('o8_model_synthetic:family', 'Unknown family %s.', run_def.family);
end
if ~isempty(f_case)                             % learned models
    model.name = run_def.family;
    model.step = @(z, u, d) step_learned(f_case, z, u, d);
end
if ~strcmp(run_def.family, 'B')
    if strcmp(run_def.jacobian, 'supplied')
        model.jac = @(z, u, d, z1) jac_supplied(J_case, z, u, d);
    else
        step_fn = model.step;
        model.jac = @(z, u, d, z1) jac_forward(step_fn, z, u, d, z1);
    end
end
model.nz = run_def.nz;
model.run_id = run_def.id;
model.label = run_def.label;
model.jacobian = run_def.jacobian;
model.family = run_def.family;
end

% ================================ O8 interface ===============================================
function z0 = init_state(x, ~, ~)
% z_0 = x measured (B, C5, MLP, C6; timing l.65-70: z0 = x0)
z0 = x(:);
end

function z0 = init_window(x, mv, md)
% constant history at (x, mv, md): timing l.62, win0 = [x0; repmat([x0; BETA0; V_MD], 33, 1)]
z0 = [x(:); repmat([x(:); mv; md], 33, 1)];
end

function [z1, aux] = step_learned(f_case, z, u, d)
% f of the timing case at [MV; MD], as nlmpc passes it to the StateFcn
z1 = f_case(z, [u; d]);
aux = [1, 0, 0];
end

function [a_jac, b_jac, aux] = jac_supplied(J_case, z, u, d)
% closed-form Jacobian of the timing case at [MV; MD]; Bmv is the MV column only (timing J)
[a_jac, b_jac] = J_case(z, [u; d]);
aux = zeros(1, 3);
end

function [z1, aux] = step_C5(z, u, d, p, res, nrm)
% timing l.66: rom_step(z, u(1), u(2), 'i', p) + nrm.sdx.*mlp_out(res, nin(z,u,nrm)), u = [MV; MD]
ud = [u; d];
[x1, step_info] = rom_step(z, ud(1), ud(2), 'i', p);
z1 = x1 + nrm.sdx.*mlp_out(res, nin(z, ud, nrm));
aux = [1, step_info.n_domain_lambda, step_info.n_domain_beta];
end

function check_nmpc(p)
% as o8_model_B.m l.21-23 (prediction.cp_fallback)
if ~isstruct(p) || ~isfield(p, 'cp_mode') || ~(ischar(p.cp_mode) || isstring(p.cp_mode)) || ~strcmp(p.cp_mode, 'nmpc')
    error('o8_model_synthetic:cpMode', 'C5 requires p.cp_mode = ''nmpc'' (prediction.cp_fallback).');
end
end

function [a_jac, b_jac, aux] = jac_forward(step_fn, z, u, d, z1)
% forward differences with the rule of nlmpc: copy of o8_model_B.m l.37-60 (computeJacobianState.m
% l.19-43), with step_B replaced by the step of the run
dv = 1e-6;                                      % computeJacobianState.m l.19
nz = numel(z);
x0 = z(:);
a_jac = zeros(nz, nz);
aux = zeros(1, 3);
xa = abs(x0);                                   % l.21-22
xa(xa < 1) = 1;
for jstate = 1:nz                               % l.23-30
    dx = dv*xa(jstate);
    x0(jstate) = x0(jstate) + dx;
    [f_pert, aux_pert] = step_fn(x0, u, d);
    x0(jstate) = x0(jstate) - dx;
    a_jac(:, jstate) = (f_pert - z1)/dx;
    aux = aux + aux_pert;
end
ua = abs(u);                                    % l.33-34 (MV only, nmv = 1)
ua(ua < 1) = 1;
du = dv*ua;                                     % l.37-38
u_pert = u + du;
[f_pert, aux_pert] = step_fn(x0, u_pert, d);
b_jac = (f_pert - z1)/du;                       % l.41
aux = aux + aux_pert;
end

% ================================ timing_E6_nlmpc.m, verbatim ================================
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
% output and Jacobian dy/ds of the tanh MLP (closed form)
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
z1 = z + nrm.sdx.*mlp_out(M, nin(z, u, nrm));
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
z1 = z + nrm.sdx.*gp_out(G, nin(z, u, nrm));
end

function [A, B] = j_gp(G, z, u, nrm)
[~, Js] = gp_out(G, nin(z, u, nrm));
Js = nrm.sdx.*Js./nrm.sd';
A = eye(2) + Js(:, 1:2);  B = Js(:, 3);
end

% ================================ models: window L = 34 ======================================
% z = [x_k; (x, u, d) at k-1; ...; (x, u, d) at k-33] (134 values); regressor r = [x_k; u_k; d_k; z(3:134)]
function z1 = f_win(net, z, u, nrm)
r = ([z(1:2); u(1); u(2); z(3:end)] - repmat(nrm.mu, 34, 1))./repmat(nrm.sd, 34, 1);
z1 = [z(1:2) + nrm.sdx.*net(r); z(1:2); u(1); u(2); z(3:end-4)];
end

function [A, B] = j_win(netj, z, u, nrm)
sdr = repmat(nrm.sd, 34, 1);
r = ([z(1:2); u(1); u(2); z(3:end)] - repmat(nrm.mu, 34, 1))./sdr;
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

function X = r2seq(r)
% regressor (lag 0 first) to a 4 x 34 sequence, oldest first
X = fliplr(reshape(r, 4, 34));
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

function y = tcn_out(T, r)
y = tcn_fwd(T, r2seq(r));
end

function [y, Jr] = tcn_jac(T, r)
X = r2seq(r);  n = size(X, 2);
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

function [y, Phi, Lc, mu, D] = llm_core(Lm, r)
s = r(1:4)';                                   % scheduling: current sample [x_k, u_k, d_k]
D = (s - Lm.c)./Lm.sig;
mu = exp(-0.5*sum(D.^2, 2));
Phi = mu/sum(mu);
Lc = reshape(Lm.Th*[1; r], 2, Lm.m);           % local model outputs, 2 x m
y = Lc*Phi;
end

function y = llm_out(Lm, r)
y = llm_core(Lm, r);
end

function [y, Jr] = llm_jac(Lm, r)
[y, Phi, Lc, mu, D] = llm_core(Lm, r);
Th = reshape(Lm.Th(:, 2:end), 2, Lm.m, []);
Jr = reshape(sum(Th.*Phi', 2), 2, []);         % sum_i Phi_i dTheta_i r / dr
dmu = -mu.*D./Lm.sig;                          % m x 4
dPhi = (dmu - Phi*sum(dmu, 1))/sum(mu);        % m x 4
Jr(:, 1:4) = Jr(:, 1:4) + Lc*dPhi;
end

% ================================ models: LSTM ===============================================
% z = [x_k; h_1; c_1; ...; h_nl; c_nl]; gates ordered i, f, g, o

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
z1(1:2) = z(1:2) + nrm.sdx.*(Ls.Wo*xin + Ls.bo);
end

function [A, B] = j_lstm(Ls, z, u, nrm)
H = Ls.H;  nz = numel(z);
A = zeros(nz);  B = zeros(nz, 1);
xin = nin(z, u, nrm);
Din = zeros(4, nz);  Din(1, 1) = 1/nrm.sd(1);  Din(2, 2) = 1/nrm.sd(2);   % d(input)/dz
Dinu = [0; 0; 1/nrm.sd(3); 0];                                            % d(input)/du(MV)
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

function z = lstm_warm(Ls, xud, nrm, L)
% warm-up on a constant history at the equilibrium (E6-15): h and c from zero over L samples
z = [xud(1:2); zeros(2*Ls.H*Ls.nl, 1)];
for k = 1:L
    z1 = f_lstm(Ls, z, xud(3:4), nrm);
    z(3:end) = z1(3:end);
end
end
