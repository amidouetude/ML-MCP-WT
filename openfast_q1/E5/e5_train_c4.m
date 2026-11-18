function [model, fit, rec] = e5_train_c4(runs, part, cfg, nrm, S, opts)
%E5_TRAIN_C4  One C4 trial: LOLIMOT training of one configuration and the checks of finding F1
%(amendment_4.A4, A6, A12; amendment_3.D6; amendment 1).
%
%   [model, fit, rec] = e5_train_c4(runs, part, cfg, nrm, S, opts)
%
%   runs, part   the runs and the masks of e5_partition (fields train_filtered and selection)
%   cfg          sched ('du' or 'xud') and L (1, 4, 8, 16 or 34)
%   nrm, S       e5_normalisation and e5_settings
%   opts         struct, optional field m_max (default 32, framework_decisions.optimiser)
%   A12: training rows of kind 'window' with L of part.train_filtered, selection rows of
%   part.selection (e5_rows, e5_features, double precision on the CPU); e5_lolimot with m_max and
%   k_sigma = 1/3; no seed (D6). A4: e5_c4_identity for the retained model (e5_convert_llm(fit))
%   and for the model of m_max local models (e5_convert_llm(fit, fit.m_max)). A6: fit.n_warn.
%   model        e5_model('C4', ...) of the retained size
%   fit          the fit of e5_lolimot (all sizes, losses, sel_mse, n_warn)
%   rec          status 'COMPLETE', sched, L, m_max, m_best, n_train, n_sel, n_warn, time_features,
%                time_train (e5_lolimot, construction and size choice), time_identity, identity
%                (retained) and identity_max (m_max), each a result of e5_c4_identity; Lm the
%                converted model of the retained size

if nargin < 6 || isempty(opts)
    opts = struct();
end
if isfield(opts, 'm_max')
    m_max = opts.m_max;
else
    m_max = 32;
end
t_feat = tic;
rows_tr = e5_rows(runs, part.train_filtered, 'window', cfg.L);
rows_sel = e5_rows(runs, part.selection, 'window', cfg.L);
[F, Y] = e5_features(runs, rows_tr, 'window', cfg.L, nrm, 'double');
[F_sel, Y_sel] = e5_features(runs, rows_sel, 'window', cfg.L, nrm, 'double');
rec.time_features = toc(t_feat);
t_fit = tic;
fit = e5_lolimot(F, Y, F_sel, Y_sel, cfg.sched, struct('m_max', m_max, 'k_sigma', 1/3));
rec.time_train = toc(t_fit);
clear F Y F_sel Y_sel
Lm = e5_convert_llm(fit);
Lm_max = e5_convert_llm(fit, fit.m_max);
model = e5_model('C4', Lm, nrm, struct('L', cfg.L));
t_id = tic;
rec.identity = e5_c4_identity(fit.models{fit.m_best}, Lm, runs, part.selection, nrm, cfg.L, S);
rec.identity_max = e5_c4_identity(fit.models{fit.m_max}, Lm_max, runs, part.selection, nrm, cfg.L, S);
rec.time_identity = toc(t_id);
rec.status = 'COMPLETE';
rec.sched = cfg.sched;
rec.L = cfg.L;
rec.m_max = fit.m_max;
rec.m_best = fit.m_best;
rec.n_train = fit.n_train;
rec.n_sel = fit.n_sel;
rec.n_warn = fit.n_warn;
rec.Lm = Lm;
end
