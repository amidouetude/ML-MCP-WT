function [model, G, rec] = e5_train_c6(runs, part, cfg, seed, nrm)
%E5_TRAIN_C6  One C6 trial: subsample, active set and the two FIC GPs of the state components
%(framework_decisions.C6_sparse_GP, search, E5 l.37, l.63; amendment_3.D5_C6; amendment_4.A13).
%
%   [model, G, rec] = e5_train_c6(runs, part, cfg, seed, nrm)
%
%   runs, part   the runs and the masks of e5_partition (field train_filtered)
%   cfg          n_sub (10000 or 40000 in the campaign) and n_act (500 or 1000)
%   seed         35001, 35002 or 35003
%   A13: rng(seed, 'twister'); randperm without replacement of the current-sample training rows
%   (e5_rows kind 'current' of part.train_filtered) for the subsample, then randperm of the
%   positions of the subsample for the active set; the logical ActiveSet passed to both fitrgp
%   calls (omega_r, omega_f) with FitMethod and PredictMethod 'fic', KernelFunction
%   'ardsquaredexponential', BasisFunction 'none', Standardize false, the other options at their
%   defaults; inputs and targets of e5_features (double, D2_scaling).
%   model   e5_model('C6', G, nrm); G  e5_convert_gp of the two GPs
%   rec     status 'COMPLETE', seed, n_sub, n_act, sub_rows (n_sub x 2 [run, k], in the order of the
%           draw), act_pos (positions in the subsample, in the order of the draw), time_fit_r,
%           time_fit_f, time_train (s)

t_train = tic;
rows = e5_rows(runs, part.train_filtered, 'current', 1);
if cfg.n_sub > size(rows, 1) || cfg.n_act > cfg.n_sub
    error('e5_train_c6:size', 'Subsample %d of %d rows with an active set of %d is not possible.', cfg.n_sub, ...
          size(rows, 1), cfg.n_act);
end
rng(seed, 'twister');
sub = randperm(size(rows, 1), cfg.n_sub);
act_pos = randperm(cfg.n_sub, cfg.n_act);
active = false(cfg.n_sub, 1);
active(act_pos) = true;
sub_rows = rows(sub, :);
[F, Y] = e5_features(runs, sub_rows, 'current', 1, nrm, 'double');
gp_opts = {'KernelFunction', 'ardsquaredexponential', 'FitMethod', 'fic', 'PredictMethod', 'fic', ...
           'ActiveSet', active, 'BasisFunction', 'none', 'Standardize', false};
t_fit = tic;
gp_r = fitrgp(F, Y(:, 1), gp_opts{:});
rec.time_fit_r = toc(t_fit);
t_fit = tic;
gp_f = fitrgp(F, Y(:, 2), gp_opts{:});
rec.time_fit_f = toc(t_fit);
G = e5_convert_gp(gp_r, gp_f);
model = e5_model('C6', G, nrm, struct());
rec.status = 'COMPLETE';
rec.seed = seed;
rec.n_sub = cfg.n_sub;
rec.n_act = cfg.n_act;
rec.sub_rows = sub_rows;
rec.act_pos = act_pos;
rec.time_train = toc(t_train);
end
