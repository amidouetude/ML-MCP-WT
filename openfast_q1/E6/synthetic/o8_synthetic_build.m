function syn = o8_synthetic_build()
%O8_SYNTHETIC_BUILD  Synthetic untrained models of measurement (i) of spec_E6_solver_O8
%(cost_measurement_protocol.cases): the models of timing_E6_nlmpc.m (sha256 3bb3d6bd...), with
%the weights drawn once with rng(36000, 'twister') in the same order (mlp, res, gp, swm, tcn,
%llm, lsS, lsB), so that the models are the same (cases, timing_E6_nlmpc.m l.49).
%
%   syn = o8_synthetic_build()
%
%   Copied verbatim from timing_E6_nlmpc.m: l.24-26 (constants) and l.49-62 (draws, x0, win0) in
%   the body below, and the draw functions make_mlp (l.212-219), make_gp (l.252-254), make_tcn
%   (l.300-307), make_llm (l.353-355) and make_lstm (l.381-388) as local functions, names and
%   bodies unchanged. test_o8_synthetic_models checks syn bit for bit against the same lines
%   extracted at run time from the SHA-256-checked file (part (a)).
%   The state of the global random stream is saved before the draws and restored on exit
%   (onCleanup); this has no effect on the draws.
%
%   syn.nrm          input centring nrm.mu, input scales nrm.sd, output scales of Delta x nrm.sdx
%                    (l.50-52)
%   syn.mlp, res     MLP 3 x 128 of the case MLP and residual MLP 3 x 128 of C5 (l.53-54)
%   syn.gp           GP with an active set of 1000 points, C6 (l.55)
%   syn.swm          MLP of the window model C1 (l.56)
%   syn.tcn          TCN kernel 3, 64 channels, dilations 1 2 4 8 16, C2 (l.57)
%   syn.llm          32 local linear models on 137 regressors, C4 (l.58)
%   syn.lsS, lsB     LSTM 1 x 16 and 2 x 128, C3 (l.59-60)
%   syn.x0           [omega_rated; 97 omega_rated] (rad/s) (l.61)
%   syn.win0         constant history of the window models, 134 x 1 (l.62)
%   syn.omega_rated, syn.ngb, syn.beta0, syn.v_md   OMEGA_R (rad/s), NGB, BETA0 (deg, beta_eq at
%                    18 m/s) and V_MD (m/s) (l.24-26)
%   syn.L            window length and LSTM warm-up length, 34 (l.62, l.71, l.77)
%   syn.rng_seed, syn.rng_generator, syn.draw_order   record of the draws

rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
% ---------------- timing_E6_nlmpc.m l.24-26, verbatim ----------------
V_MD = 18;                                                               % m/s, authorisation
OMEGA_R = 12.1*pi/30;  NGB = 97;                                         % rad/s, spec_E2 V1; GBRatio
BETA0 = 14.9124;                                                         % deg, beta_eq at 18 m/s (run_E3b.m l.56)
% ---------------- timing_E6_nlmpc.m l.49-62, verbatim ----------------
rng(36000, 'twister');
nrm.mu  = [OMEGA_R; NGB*OMEGA_R; BETA0; V_MD];   % input centring (synthetic)
nrm.sd  = [0.05; 5; 5; 3];                       % input scales (synthetic)
nrm.sdx = [0.002; 0.2];                          % output scales of Delta x (synthetic)
mlp  = make_mlp(4, [128 128 128]);
res  = make_mlp(4, [128 128 128]);
gp   = make_gp(1000, 4);
swm  = make_mlp(136, [128 128 128]);
tcn  = make_tcn(4, 64, 3, [1 2 4 8 16]);
llm  = make_llm(32, 4, 137);
lsS  = make_lstm(4, 16, 1);
lsB  = make_lstm(4, 128, 2);
x0   = [OMEGA_R; NGB*OMEGA_R];
win0 = [x0; repmat([x0; BETA0; V_MD], 33, 1)];
% ---------------- record ----------------
syn.nrm = nrm;
syn.mlp = mlp;
syn.res = res;
syn.gp = gp;
syn.swm = swm;
syn.tcn = tcn;
syn.llm = llm;
syn.lsS = lsS;
syn.lsB = lsB;
syn.x0 = x0;
syn.win0 = win0;
syn.omega_rated = OMEGA_R;
syn.ngb = NGB;
syn.beta0 = BETA0;
syn.v_md = V_MD;
syn.L = 34;
syn.rng_seed = 36000;
syn.rng_generator = 'twister';
syn.draw_order = {'mlp', 'res', 'gp', 'swm', 'tcn', 'llm', 'lsS', 'lsB'};
end

function M = make_mlp(nin_, widths)
dims = [nin_ widths 2];
M.W = cell(1, numel(dims) - 1);  M.b = cell(1, numel(dims) - 1);
for l = 1:numel(dims) - 1
    M.W{l} = randn(dims(l+1), dims(l))/sqrt(dims(l));
    M.b{l} = 0.1*randn(dims(l+1), 1);
end
end

function G = make_gp(m, d)
G.Xa = randn(m, d);  G.ell = 0.5 + rand(2, d);  G.alpha = randn(m, 2)/sqrt(m);
end

function T = make_tcn(cin, ch, k, dil)
T.dil = dil;  T.W = cell(1, numel(dil));  T.b = cell(1, numel(dil));
c = cin;
for l = 1:numel(dil)
    T.W{l} = randn(ch, c, k)/sqrt(c*k);  T.b{l} = 0.1*randn(ch, 1);  c = ch;
end
T.Wo = randn(2, ch)/sqrt(ch);  T.bo = 0.1*randn(2, 1);
end

function Lm = make_llm(m, ns, np1)
Lm.c = randn(m, ns);  Lm.sig = (0.5 + rand(m, ns))/3;  Lm.Th = randn(2*m, np1)/sqrt(np1);  Lm.m = m;
end

function Ls = make_lstm(nin_, H, nl)
Ls.H = H;  Ls.nl = nl;  Ls.W = cell(1, nl);  Ls.R = cell(1, nl);  Ls.b = cell(1, nl);
c = nin_;
for l = 1:nl
    Ls.W{l} = randn(4*H, c)/sqrt(c);  Ls.R{l} = randn(4*H, H)/sqrt(H);  Ls.b{l} = 0.1*randn(4*H, 1);  c = H;
end
Ls.Wo = randn(2, H)/sqrt(H);  Ls.bo = 0.1*randn(2, 1);
end
