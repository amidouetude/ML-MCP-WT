function out = o8_synthetic_cfg_draws(kind, varargin)
%O8_SYNTHETIC_CFG_DRAWS  Weights of the intermediate configurations of spec_E6_solver_O8
%(i_intermediate for C2 and C3, amendment_7.C5_weights for C5), and the check sequence of the draws.
%
%   net  = o8_synthetic_cfg_draws('tcn', dil)          rng(36000, 'twister'), then
%                                                       make_tcn(4, 64, 3, dil)
%   net  = o8_synthetic_cfg_draws('lstm', H, nl)       rng(36000, 'twister'), then make_lstm(4, H, nl)
%   net  = o8_synthetic_cfg_draws('mlp', widths)       rng(36000, 'twister'), then make_mlp(4, widths)
%   nets = o8_synthetic_cfg_draws('timing_sequence')   rng(36000, 'twister'), then the eight draws of
%                                                       timing_E6_nlmpc.m l.53-60 in their order, with the
%                                                       local copies below (nets.mlp, res, gp, swm, tcn,
%                                                       llm, lsS, lsB): the check of these copies against
%                                                       o8_synthetic_build in test_o8_synthetic_cfg
%
%   Each configuration is drawn alone, the seed reset immediately before its draw (amendment_7
%   C5_weights for C5; the same rule for C2 and C3, an executor reading to be reviewed). The draw
%   functions make_mlp (l.212-219), make_gp (l.252-254), make_tcn (l.300-307), make_llm (l.353-355)
%   and make_lstm (l.381-388) of timing_E6_nlmpc.m (sha256 3bb3d6bd...) are copied verbatim below,
%   names and bodies unchanged. The state of the global random stream is saved and restored on exit.

rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
rng(36000, 'twister');
switch kind
    case 'tcn'
        out = make_tcn(4, 64, 3, varargin{1});
    case 'lstm'
        out = make_lstm(4, varargin{1}, varargin{2});
    case 'mlp'
        out = make_mlp(4, varargin{1});
    case 'timing_sequence'
        out.mlp = make_mlp(4, [128 128 128]);           % timing_E6_nlmpc.m l.53-60, same order
        out.res = make_mlp(4, [128 128 128]);
        out.gp  = make_gp(1000, 4);
        out.swm = make_mlp(136, [128 128 128]);
        out.tcn = make_tcn(4, 64, 3, [1 2 4 8 16]);
        out.llm = make_llm(32, 4, 137);
        out.lsS = make_lstm(4, 16, 1);
        out.lsB = make_lstm(4, 128, 2);
    otherwise
        error('o8_synthetic_cfg_draws:kind', 'Unknown kind %s.', kind);
end
end

% ================================ timing_E6_nlmpc.m, verbatim ================================
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
