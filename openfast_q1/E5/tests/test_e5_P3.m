function verdict = test_e5_P3(out_dir)
%TEST_E5_P3  Tests of package P3 of E5 (C4: LOLIMOT training e5_lolimot, prediction function
%e5_llm_core, converter e5_convert_llm, case C4 of e5_model), written before any run, on synthetic
%data only (e5_synthetic_runs and draws below). No E4 file is read.
%
%   verdict = test_e5_P3(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/test_e5_P3_<stamp>/:
%   part_d.csv, results.mat, errors.txt, verdict_test_e5_P3.txt. verdict 'PASS' if every check
%   passes, otherwise 'FAIL'. Tolerances fixed here before any run: TOL = 1e-10 (reading T1 of P2)
%   for the reproduction of an affine target; TOL_REL = 1e-8 for the comparison of the local
%   parameters with lscov and of a repeated training (different code paths, rounding only);
%   THRESHOLD = 1e-5 and the step sweep 1e-2 .. 1e-10 of spec_E2 verification.V2_derivatives.
%   (a) LOLIMOT on synthetic targets: an affine target reproduced by every local model of every
%       size; a target piecewise linear in d with its kink at the midpoint of the range of d: first
%       split along d at that midpoint (scheduling xud and du), training MSE lower at M = 2 and at
%       M = m_max than at M = 1.
%   (b) partition, split and selection: initial hyperrectangle, centres and standard deviations
%       (k_sigma = 1/3) of every model; worst local model (eq. (13.38)); halves of the split model,
%       other models unchanged; best split; parameters of the two new models against lscov; loss
%       and selection MSE recomputed; size retained; a repeated training; refusals.
%   (c) e5_convert_llm and e5_model C4 against the training-side prediction e5_lolimot_predict, bit
%       for bit (out and step), for (xud, L = 1), (du, L = 4), (xud, L = 8); refusals.
%   (d) closed-form Jacobian of e5_model C4 against central differences of model.step with the
%       protocol of spec_E2 verification.V2_derivatives (v2_check of test_o8_synthetic_models.m).
%   (e) with nrm.mux = 0, L = 34 and sidx = 1:4, init, step and jac of e5_model C4 equal bit for bit
%       to o8_model_synthetic C4_sup (weights of o8_synthetic_build).
%   (f) one call of e5_eval_segments per model of (c) on a synthetic run of 200 rows: 5 segments,
%       finite, not failed, e_max of the first segment equal bit for bit to a manual loop.
%   Every catch records getReport(ME, 'extended').

TOL = 1e-10;
TOL_REL = 1e-8;
THRESHOLD = 1e-5;                                  % spec_E2 V2_derivatives pass
DV_SWEEP = 10.^(-2:-1:-10);                        % spec_E2 V2_derivatives: 1e-2 to 1e-10
K_SIGMA = 1/3;                                     % amendment 1
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_e5_P3_' stamp]);
if exist(test_dir, 'dir')
    error('test_e5_P3:exists', 'Output folder already exists: %s', test_dir);
end
mkdir(test_dir);
repo_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(repo_root, 'openfast_q1', 'E2'), fullfile(repo_root, 'openfast_q1', 'E6'), ...
        fullfile(repo_root, 'openfast_q1', 'E6', 'synthetic'));
lines = {sprintf('test_e5_P3 start %s, repository %s, TOL = %g, TOL_REL = %g, V2 threshold %g', stamp, repo_root, ...
                 TOL, TOL_REL, THRESHOLD)};
err_lines = {};
results = struct('part', {}, 'check', {}, 'pass', {});
rows_d = cell(0, 8);
S = e5_settings();
% Ts = 0.05 s entry of normalisation_E4.csv (sha256 2bc33706..., E5 l.15), as test_e5_P2
nrm = struct('mu', [1.263110277; 122.5211024; 13.37803117; 17.65675016], ...
             'sd', [0.05276818504; 4.964281324; 6.938685982; 4.395360763], ...
             'mux', [4.508361182e-07; 4.654321233e-05], 'sdx', [0.001625369198; 0.1024837435]);

% ---------------------------------------------------------------- (a) synthetic targets
fit_kink = [];
F_k = [];  Y_k = [];  Fs_k = [];  Ys_k = [];
try
    rng(5001, 'twister');
    F_a = randn(400, 4);  Fs_a = randn(100, 4);  W_a = randn(2, 5);
    Y_a = [ones(400, 1), F_a]*W_a';  Ys_a = [ones(100, 1), Fs_a]*W_a';
    fit_a = e5_lolimot(F_a, Y_a, Fs_a, Ys_a, 'xud', struct('m_max', 4));
    e_out = 0;  e_par = 0;
    for m_size = 1:4
        Lm = fit_a.models{m_size};
        e_out = max(e_out, rel_err(e5_lolimot_predict(Lm, F_a'), Y_a'));
        for i_lm = 1:m_size
            e_par = max(e_par, rel_err(Lm.Th(2*i_lm - 1:2*i_lm, :), W_a));
        end
    end
    results = add(results, 'a', sprintf('affine target, xud, M = 1 .. 4: output %.2e, every local model %.2e <= %g', e_out, e_par, TOL), ...
                  e_out <= TOL && e_par <= TOL);
    rng(5003, 'twister');
    F_k = 3*rand(2000, 4) - 1.5;  Fs_k = 3*rand(500, 4) - 1.5;
    [Y_k, mid_d] = kink_target(F_k, []);
    Ys_k = kink_target(Fs_k, mid_d);
    for sc = {'xud', 'du'}
        fit_k = e5_lolimot(F_k, Y_k, Fs_k, Ys_k, sc{1}, struct('m_max', 6));
        pos_d = find(fit_k.sidx == 4);
        split_pt = fit_k.models{2}.hi(1, pos_d);
        ok = fit_k.iter(1).dim == pos_d && split_pt == mid_d && fit_k.models{2}.lo(2, pos_d) == mid_d && ...
             fit_k.train_mse(2) < fit_k.train_mse(1) && fit_k.train_mse(6) < fit_k.train_mse(1);
        results = add(results, 'a', sprintf('kink in d, %-3s: first split along d at the midpoint, MSE M=1 %.3e, M=2 %.3e, M=6 %.3e', ...
                      sc{1}, fit_k.train_mse(1), fit_k.train_mse(2), fit_k.train_mse(6)), ok);
        if strcmp(sc{1}, 'xud')
            fit_kink = fit_k;
        end
    end
catch ME
    err_lines{end+1} = sprintf('(a)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'a', 'part (a) completed without error', false);
end

% ---------------------------------------------------------------- data of (b) to (f)
runs_tr = e5_synthetic_runs(3, 600, 5101, S, 'training');
runs_sel = e5_synthetic_runs(1, 600, 5102, S, 'validation');
run_e = e5_synthetic_runs(1, 200, 5103, S, 'none');
S_e = S;
S_e.n_rows_run = 200;
cfgs = {'xud', 1; 'du', 4; 'xud', 8};
fits = cell(1, size(cfgs, 1));
data = cell(1, size(cfgs, 1));
for c = 1:size(cfgs, 1)
    try
        L = cfgs{c, 2};
        rows_tr = e5_rows(runs_tr, true(1, 3), 'window', L);
        rows_sel = e5_rows(runs_sel, true, 'window', L);
        [F_c, Y_c] = e5_features(runs_tr, rows_tr, 'window', L, nrm, 'double');
        [Fs_c, Ys_c] = e5_features(runs_sel, rows_sel, 'window', L, nrm, 'double');
        fits{c} = e5_lolimot(F_c, Y_c, Fs_c, Ys_c, cfgs{c, 1}, struct('m_max', 6));
        data{c} = struct('F', F_c, 'Y', Y_c, 'Fs', Fs_c, 'Ys', Ys_c);
    catch ME
        err_lines{end+1} = sprintf('training %s L %d\n%s', cfgs{c, 1}, cfgs{c, 2}, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
    end
end
results = add(results, 'b', 'three window trainings (xud L 1, du L 4, xud L 8) completed', all(~cellfun(@isempty, fits)));

% ---------------------------------------------------------------- (b) partition, split, selection
b_sets = {fit_kink, F_k, Y_k, Fs_k, Ys_k, 'kink xud L 1'};
for c = 1:size(cfgs, 1)
    if ~isempty(fits{c})
        b_sets(end+1, :) = {fits{c}, data{c}.F, data{c}.Y, data{c}.Fs, data{c}.Ys, ...
                            sprintf('%s L %d', cfgs{c, 1}, cfgs{c, 2})}; %#ok<AGROW>
    end
end
for q = 1:size(b_sets, 1)
    try
        if isempty(b_sets{q, 1})
            error('test_e5_P3:noFit', 'No fit for %s.', b_sets{q, 6});
        end
        [ok_b, txt_b] = check_fit(b_sets{q, :}, K_SIGMA, TOL_REL);
        for k = 1:numel(ok_b)
            results = add(results, 'b', sprintf('%-13s %s', b_sets{q, 6}, txt_b{k}), ok_b(k));
        end
    catch ME
        err_lines{end+1} = sprintf('(b) %s\n%s', b_sets{q, 6}, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'b', sprintf('%-13s checks completed without error', b_sets{q, 6}), false);
    end
end
try
    c = 2;
    rng_before = rng;
    fit_rep = e5_lolimot(data{c}.F, data{c}.Y, data{c}.Fs, data{c}.Ys, cfgs{c, 1}, struct('m_max', 6));
    rng_after = rng;
    same_struct = isequal([fit_rep.iter.worst], [fits{c}.iter.worst]) && isequal([fit_rep.iter.dim], [fits{c}.iter.dim]) && ...
                  fit_rep.m_best == fits{c}.m_best;
    e_rep = 0;
    for m_size = 1:6
        e_rep = max(e_rep, rel_err(fit_rep.models{m_size}.Th, fits{c}.models{m_size}.Th));
    end
    e_rep = max([e_rep, rel_err(fit_rep.train_loss, fits{c}.train_loss), rel_err(fit_rep.sel_mse, fits{c}.sel_mse)]);
    results = add(results, 'b', sprintf('du L 4 repeated: same worst models, splits and size, values %.2e <= %g, rng state unchanged', ...
                  e_rep, TOL_REL), same_struct && e_rep <= TOL_REL && isequal(rng_before, rng_after));
    F_bad = data{c}.F;  F_bad(5, 2) = NaN;
    F_const = data{c}.F;  F_const(:, 4) = 0.25;
    results = add(results, 'b', 'refusals: unknown scheduling, non-finite regressor, constant scheduling variable', ...
                  expect_error(@() e5_lolimot(data{c}.F, data{c}.Y, data{c}.Fs, data{c}.Ys, 'ud', struct('m_max', 2)), 'e5_lolimot:sched') && ...
                  expect_error(@() e5_lolimot(F_bad, data{c}.Y, data{c}.Fs, data{c}.Ys, 'du', struct('m_max', 2)), 'e5_lolimot:rows') && ...
                  expect_error(@() e5_lolimot(F_const, data{c}.Y, data{c}.Fs, data{c}.Ys, 'du', struct('m_max', 2)), 'e5_lolimot:range'));
catch ME
    err_lines{end+1} = sprintf('(b) repetition and refusals\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'b', 'repetition and refusals completed without error', false);
end

% ---------------------------------------------------------------- (c) manual C4 against training side
models_c = cell(1, size(cfgs, 1));
k_e = (S.l_max + 1:200)';
for c = 1:size(cfgs, 1)
    tag = sprintf('%s L %d', cfgs{c, 1}, cfgs{c, 2});
    try
        L = cfgs{c, 2};
        Lm_fit = fits{c}.models{fits{c}.m_best};
        Lm = e5_convert_llm(fits{c});
        model = e5_model('C4', Lm, nrm, struct('L', L));
        F_e = e5_features(run_e, [ones(numel(k_e), 1), k_e], 'window', L, nrm, 'double');
        y_train = e5_lolimot_predict(Lm_fit, F_e');
        out_eq = true;  step_eq = true;
        for q = 1:numel(k_e)
            k = k_e(q);
            x_k = run_e.X(k, 1:2)';
            z0 = model.init(x_k, run_e.X(k - S.l_max:k - 1, :));
            u_k = run_e.X(k, 3);  d_k = run_e.X(k, 4);
            out_eq = out_eq && same_bits(model.out(z0, u_k, d_k), y_train(:, q));
            z1 = model.step(z0, u_k, d_k);
            if L == 1
                z1_ref = x_k + nrm.mux + nrm.sdx.*y_train(:, q);
            else
                z1_ref = [x_k + nrm.mux + nrm.sdx.*y_train(:, q); x_k; u_k; d_k; z0(3:end - 4)];
            end
            step_eq = step_eq && same_bits(z1, z1_ref) && numel(z0) == model.nz;
        end
        results = add(results, 'c', sprintf('%-9s M = %d of %d: e5_model out and step = e5_lolimot_predict, %d rows, bit for bit', ...
                      tag, fits{c}.m_best, fits{c}.m_max, numel(k_e)), out_eq && step_eq && isequal(Lm.Th, Lm_fit.Th));
        models_c{c} = model;
    catch ME
        err_lines{end+1} = sprintf('(c) %s\n%s', tag, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'c', sprintf('%-9s completed without error', tag), false);
    end
end
try
    fit_bad = fits{2};
    fit_bad.models{fit_bad.m_best}.sig(1, 1) = 0;
    fit_shape = fits{2};
    fit_shape.models{fit_shape.m_best}.Th(end, :) = [];
    Lm_ok = e5_convert_llm(fits{2});
    results = add(results, 'c', 'refusals: zero standard deviation, Th of wrong size, opts.L not matching Th', ...
                  expect_error(@() e5_convert_llm(fit_bad), 'e5_convert_llm:sigma') && ...
                  expect_error(@() e5_convert_llm(fit_shape), 'e5_convert_llm:shape') && ...
                  expect_error(@() e5_model('C4', Lm_ok, nrm, struct('L', 8)), 'e5_model:C4'));
catch ME
    err_lines{end+1} = sprintf('(c) refusals\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'c', 'refusals completed without error', false);
end

% ---------------------------------------------------------------- (d) V2_derivatives
for c = 1:size(cfgs, 1)
    tag = sprintf('%s L %d', cfgs{c, 1}, cfgs{c, 2});
    try
        model = models_c{c};
        if isempty(model)
            error('test_e5_P3:noModel', 'No model for %s.', tag);
        end
        k = S.l_max + 1;
        d_k = run_e.X(k, 4);
        z_start = model.init(run_e.X(k, 1:2)', run_e.X(k - S.l_max:k - 1, :));
        pts = {z_start, run_e.X(k, 3), 'start'};
        for mv_offset = [5, -5]
            mv_b = run_e.X(k, 3) + mv_offset;
            z_b = z_start;
            for istep = 1:30
                z_b = model.step(z_b, mv_b, d_k);
                if istep == 10 || istep == 30
                    pts(end+1, :) = {z_b, mv_b, sprintf('MV %+g deg, %d steps', mv_offset, istep)}; %#ok<AGROW>
                end
            end
        end
        ok_all = true;
        worst = 0;
        for ipt = 1:size(pts, 1)
            r_b = v2_check(model, pts{ipt, 1}, pts{ipt, 2}, d_k, DV_SWEEP, THRESHOLD);
            ok_pt = r_b.max_error <= THRESHOLD && r_b.n_unstable == 0;
            ok_all = ok_all && ok_pt;
            worst = max(worst, r_b.max_error);
            rows_d(end+1, :) = {tag, pts{ipt, 3}, r_b.nz, r_b.n_point, r_b.max_error, r_b.n_unstable, r_b.modal_dv, ...
                                pass_word(ok_pt)}; %#ok<AGROW>
        end
        results = add(results, 'd', sprintf('%-9s V2_derivatives at %d points: max error %.3e <= %g, no unstable reference', ...
                      tag, size(pts, 1), worst, THRESHOLD), ok_all);
    catch ME
        err_lines{end+1} = sprintf('(d) %s\n%s', tag, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'd', sprintf('%-9s completed without error', tag), false);
    end
end

% ---------------------------------------------------------------- (e) bit for bit against C4_sup of O8
try
    syn = o8_synthetic_build();
    nrm_d = syn.nrm;
    nrm_d.mux = [0; 0];
    Lm_syn = syn.llm;
    Lm_syn.sidx = 1:4;
    m_new = e5_model('C4', Lm_syn, nrm_d, struct('L', 34));
    m_ref = o8_model_synthetic(syn, 'C4_sup', []);
    hist_const = repmat([syn.x0', syn.beta0, syn.v_md], S.l_max, 1);
    z0_new = m_new.init(syn.x0, hist_const);
    z0_ref = m_ref.init(syn.x0, syn.beta0, syn.v_md);
    all_eq = same_bits(z0_new, z0_ref) && m_new.nz == m_ref.nz;
    pert = 0.01*sin((1:numel(z0_ref)).').*max(abs(z0_ref), 1);
    inputs = {z0_ref, syn.beta0, syn.v_md; z0_ref + pert, 0.01, 12; z0_ref - pert, 29.99, 24; z0_ref + 0.5*pert, 7.5, 16};
    for s_in = 1:size(inputs, 1)
        z_in = inputs{s_in, 1};  mv_in = inputs{s_in, 2};  md_in = inputs{s_in, 3};
        [z1_n, aux_n] = m_new.step(z_in, mv_in, md_in);
        [z1_r, aux_r] = m_ref.step(z_in, mv_in, md_in);
        [a_n, b_n, auxj_n] = m_new.jac(z_in, mv_in, md_in, z1_n);
        [a_r, b_r, auxj_r] = m_ref.jac(z_in, mv_in, md_in, z1_r);
        all_eq = all_eq && same_bits(z1_n, z1_r) && same_bits(aux_n, aux_r) && same_bits(a_n, a_r) && ...
                 same_bits(b_n, b_r) && same_bits(auxj_n, auxj_r);
    end
    results = add(results, 'e', 'C4  against C4_sup   init, step, jac at 4 inputs bit for bit', all_eq);
catch ME
    err_lines{end+1} = sprintf('(e)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'e', 'part (e) completed without error', false);
end

% ---------------------------------------------------------------- (f) e5_eval_segments
for c = 1:size(cfgs, 1)
    tag = sprintf('%s L %d', cfgs{c, 1}, cfgs{c, 2});
    try
        model = models_c{c};
        if isempty(model)
            error('test_e5_P3:noModel', 'No model for %s.', tag);
        end
        seg = e5_eval_segments(run_e, true, model, S_e, 'a');
        s = seg.start(1);
        z = model.init(run_e.X(s, 1:2)', run_e.X(s - S_e.l_max:s - 1, :));
        om = zeros(S_e.np, 1);
        for i_step = 1:S_e.np
            z = model.step(z, run_e.X(s + i_step - 1, 3), run_e.X(s + i_step - 1, 4));
            om(i_step) = z(1);
        end
        e_manual = max(abs((om - run_e.X(s + 1:s + S_e.np, 1))/S_e.omega_rated*100), [], 'includenan');
        results = add(results, 'f', sprintf('%-9s e5_eval_segments: 5 segments, finite, not failed, first e_max = manual loop', tag), ...
                      numel(seg.e_max) == 5 && all(isfinite(seg.e_max)) && ~any(seg.failed) && seg.e_max(1) == e_manual);
    catch ME
        err_lines{end+1} = sprintf('(f) %s\n%s', tag, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'f', sprintf('%-9s e5_eval_segments completed without error', tag), false);
    end
end

% ---------------------------------------------------------------- verdict
all_pass = ~isempty(results) && all([results.pass]);
for k = 1:numel(results)
    lines{end+1} = sprintf('(%s) %-110s %s', results(k).part, results(k).check, pass_word(results(k).pass)); %#ok<AGROW>
end
if all_pass
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
lines{end+1} = sprintf('checks %d, passed %d, errors caught %d', numel(results), nnz([results.pass]), numel(err_lines));
lines{end+1} = ['TEST E5 P3 C4 LOLIMOT: ' verdict];
write_lines(fullfile(test_dir, 'verdict_test_e5_P3.txt'), lines);
if isempty(err_lines)
    write_lines(fullfile(test_dir, 'errors.txt'), {'errors caught by test_e5_P3: 0'});
else
    write_lines(fullfile(test_dir, 'errors.txt'), err_lines);
end
tbl_d = cell2table(rows_d, 'VariableNames', {'model', 'point', 'nz', 'n_point', 'max_error', 'n_unstable', 'modal_plateau_dv', 'status'});
writetable(tbl_d, fullfile(test_dir, 'part_d.csv'), 'Delimiter', ';');
save(fullfile(test_dir, 'results.mat'), 'results', 'lines', 'tbl_d', 'fits', 'TOL', 'TOL_REL', 'THRESHOLD');
fprintf('%s\n', lines{end-1:end});
end

% ================================================================ targets
function [Y, mid_d] = kink_target(F, mid_d)
% two outputs piecewise linear in d (column 4) with the kink at mid_d, the midpoint of the range of
% d of the training rows (the first split of LOLIMOT along d); mid_d computed when empty
if isempty(mid_d)
    mid_d = (min(F(:, 4)) + max(F(:, 4)))/2;
end
Y = [0.5*F(:, 1) + 2*max(F(:, 4) - mid_d, 0), -0.3*F(:, 3) + max(mid_d - F(:, 4), 0)];
end

% ================================================================ (b)
function [ok, txt] = check_fit(fit, F, Y, Fs, Ys, ~, k_sigma, tol_rel)
ok = [];  txt = {};
sidx = fit.sidx;
Ft = F';
X1 = [ones(size(F, 1), 1), F];
lo0 = min(F(:, sidx), [], 1);  hi0 = max(F(:, sidx), [], 1);
geo_ok = isequal(fit.models{1}.lo, lo0) && isequal(fit.models{1}.hi, hi0) && numel(fit.models) == fit.m_max;
for m_size = 1:fit.m_max
    Lm = fit.models{m_size};
    geo_ok = geo_ok && Lm.m == m_size && isequal(Lm.c, (Lm.lo + Lm.hi)/2) && isequal(Lm.sig, k_sigma*(Lm.hi - Lm.lo));
end
ok(end+1) = geo_ok;
txt{end+1} = sprintf('box [min, max] of the scheduling data; c midpoints, sig = k_sigma x extension, M = 1 .. %d', fit.m_max);
worst_ok = true;  halves_ok = true;  best_ok = true;  e_wls = 0;  e_loc = 0;
for it = 1:numel(fit.iter)
    rec = fit.iter(it);
    m_new = rec.m;
    l_w = rec.worst;
    prev = fit.models{m_new - 1};
    cur = fit.models{m_new};
    [Y_prev, Phi_prev] = e5_lolimot_predict(prev, Ft);
    local_ref = Phi_prev*sum((Y - Y_prev').^2, 2);
    [~, l_ref] = max(local_ref);
    e_loc = max(e_loc, rel_err(rec.local_loss, local_ref));
    worst_ok = worst_ok && l_ref == l_w;
    j = rec.dim;
    mid = (prev.lo(l_w, j) + prev.hi(l_w, j))/2;
    lower_lo = prev.lo(l_w, :);  lower_hi = prev.hi(l_w, :);  lower_hi(j) = mid;
    upper_lo = prev.lo(l_w, :);  upper_lo(j) = mid;  upper_hi = prev.hi(l_w, :);
    others = setdiff(1:m_new - 1, l_w);
    rows_th = sort([2*others - 1, 2*others]);
    halves_ok = halves_ok && isequal(cur.lo(l_w, :), lower_lo) && isequal(cur.hi(l_w, :), lower_hi) && ...
                isequal(cur.lo(m_new, :), upper_lo) && isequal(cur.hi(m_new, :), upper_hi) && ...
                isequal(cur.lo(others, :), prev.lo(others, :)) && isequal(cur.hi(others, :), prev.hi(others, :)) && ...
                isequal(cur.c(others, :), prev.c(others, :)) && isequal(cur.sig(others, :), prev.sig(others, :)) && ...
                isequal(cur.Th(rows_th, :), prev.Th(rows_th, :));
    [~, j_ref] = min(rec.cand_loss);
    [Y_cur, Phi_cur] = e5_lolimot_predict(cur, Ft);
    best_ok = best_ok && j_ref == j && fit.train_loss(m_new) == rec.cand_loss(j) && ...
              fit.train_loss(m_new) == sum((Y - Y_cur').^2, 'all');
    for i_new = [l_w, m_new]
        th_ref = lscov(X1, Y, Phi_cur(i_new, :)');
        e_wls = max(e_wls, rel_err(cur.Th(2*i_new - 1:2*i_new, :), th_ref'));
    end
end
ok(end+1) = worst_ok && e_loc <= tol_rel;
txt{end+1} = sprintf('worst model = argmax of the local losses (13.38) at every split, losses %.2e', e_loc);
ok(end+1) = halves_ok;
txt{end+1} = 'split model replaced by its two halves, the other models unchanged (bounds, c, sig, Th)';
ok(end+1) = best_ok;
txt{end+1} = 'best split = first argmin of the candidate losses; loss recomputed bit for bit';
ok(end+1) = e_wls <= tol_rel;
txt{end+1} = sprintf('parameters of the two new models against lscov with weights Phi: %.2e <= %g', e_wls, tol_rel);
sel_ok = true;
for m_size = 1:fit.m_max
    Ys_hat = e5_lolimot_predict(fit.models{m_size}, Fs');
    sel_ok = sel_ok && fit.sel_mse(m_size) == sum((Ys - Ys_hat').^2, 'all')/(2*size(Fs, 1));
end
[~, m_ref] = min(fit.sel_mse);
ok(end+1) = sel_ok && fit.m_best == m_ref;
txt{end+1} = sprintf('selection MSE recomputed bit for bit, size retained %d = first argmin (WLS warnings %d, reported)', ...
                     fit.m_best, fit.n_warn);
end

% ================================================================ (d)
function r_b = v2_check(model, z, mv, md, dv_sweep, threshold)
% spec_E2 verification.V2_derivatives on [A, Bmv] of model.jac at (z, mv, md): central
% differences of model.step in v = [z; mv], step h = dv x max(|v_c|, 1); plateau per entry by
% absolute difference (gradient_check.amendment_2.reference); scale and error as amendment_2
% (copy of v2_check of test_o8_synthetic_models.m, sha256 in the launch block)
z = z(:);
nz = numel(z);
z1 = model.step(z, mv, md);
[a_sup, b_sup] = model.jac(z, mv, md, z1);
j_sup = [a_sup, b_sup];
v = [z; mv];
nd = numel(dv_sweep);
est = zeros(nz, nz + 1, nd);
for col = 1:nz + 1
    scale_c = max(abs(v(col)), 1);
    for s_dv = 1:nd
        h_c = dv_sweep(s_dv)*scale_c;
        v_plus = v;   v_plus(col) = v_plus(col) + h_c;
        v_minus = v;  v_minus(col) = v_minus(col) - h_c;
        f_plus = model.step(v_plus(1:nz), v_plus(nz + 1), md);
        f_minus = model.step(v_minus(1:nz), v_minus(nz + 1), md);
        est(:, col, s_dv) = (f_plus - f_minus)/(2*h_c);
    end
end
pair = abs(est(:, :, 1:nd - 1) - est(:, :, 2:nd));
[pair_min, s_star] = min(pair, [], 3);
n_entries = nz*(nz + 1);
lin = reshape(1:n_entries, nz, nz + 1) + (s_star - 1)*n_entries;
ref_j = 0.5*(est(lin) + est(lin + n_entries));
n_point = max([abs(ref_j(:)); 1]);
err = abs(j_sup - ref_j)/n_point;
[max_err, imax] = max(err(:));
[worst_row, worst_col] = ind2sub(size(err), imax);
rel = abs(j_sup - ref_j)./abs(ref_j);
rel(ref_j == 0) = NaN;
r_b = struct('nz', nz, 'n_point', n_point, 'max_error', max_err, 'worst_row', worst_row, 'worst_col', worst_col, ...
             'max_pair_diff_scaled', max(pair_min(:))/n_point, 'n_unstable', nnz(pair_min > threshold*n_point), ...
             'modal_dv', dv_sweep(mode(s_star(:))), 'max_rel_info', max([rel(:); -Inf], [], 'omitnan'));
end

% ================================================================ helpers
function e = rel_err(Y, Y_ref)
% relative error of reading T1 of P2: max |Y - Y_ref| over max |Y_ref|
e = max(abs(Y(:) - Y_ref(:)))/max(abs(Y_ref(:)));
end

function eq = same_bits(a, b)
eq = strcmp(class(a), class(b)) && isequal(size(a), size(b)) && ...
     isequal(typecast(double(a(:)), 'uint64'), typecast(double(b(:)), 'uint64'));
end

function results = add(results, part_name, check_name, pass)
results(end+1) = struct('part', part_name, 'check', check_name, 'pass', logical(pass));
fprintf('(%s) %-110s %s\n', part_name, check_name, pass_word(pass));
end

function ok = expect_error(fn, identifier)
ok = false;
try
    fn();
catch ME
    ok = strcmp(ME.identifier, identifier);
end
end

function s = pass_word(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function write_lines(file_path, text_lines)
fid = fopen(file_path, 'w');
fprintf(fid, '%s\n', text_lines{:});
fclose(fid);
end
