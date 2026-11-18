function verdict = test_e5_P4a(out_dir)
%TEST_E5_P4A  Tests of package P4a of E5 (trainers per family: e5_nn_data, e5_train_nn,
%e5_train_c4, e5_c4_identity, e5_train_c6), written before any run, on synthetic data only
%(e5_synthetic_runs); no E4 file is read; the Cp table of the repository is read for C5. Few epochs:
%the test checks the logic of the code, nothing about the quality of a model.
%
%   verdict = test_e5_P4a(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/test_e5_P4a_<stamp>/:
%   results.mat, errors.txt, verdict_test_e5_P4a.txt. verdict 'PASS' if every check passes.
%   Tolerance fixed here before any run: TOL_GPU = 1e-5, relative, for a selection loss recomputed
%   from the restored network against the loss recorded at its epoch (two single-precision passes of
%   predict on the GPU).
%   (a) e5_nn_data: layouts and sizes of the five families; the C5 exclusion of A11 (keep of
%       e5_c5_targets); refusals.
%   (b) e5_train_nn on the GPU, one small configuration per family, 4 epochs at most: status
%       COMPLETE, best epoch = first argmin of the recorded selection losses (A10), learnables in
%       double on the CPU, net.State double and zero (C3), converted model finite.
%   (c) A10 restoration on a crafted case (training target +3, selection target -3): best epoch 1,
%       stop after 1 + patience epochs, the restored network gives the loss of epoch 1, not the loss
%       of the last epoch; NO_FINITE_LOSS when the selection loss is never finite; A8: the same seed
%       gives the same initial learnables, another seed different ones.
%   (d) e5_train_c4 (du, L 4, m_max 4): A4 identity PASS for the retained model and for the model of
%       m_max local models; a crafted difference in the parameters gives FAIL; A6 count recorded.
%   (e) e5_train_c6 (subsample 300, active set 40): A13 draws reproducible with the seed and
%       different with another seed, active set shared by the two GPs and equal to the subsample
%       rows at the drawn positions, model finite.
%   Every catch records getReport(ME, 'extended').

TOL_GPU = 1e-5;
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_e5_P4a_' stamp]);
if exist(test_dir, 'dir')
    error('test_e5_P4a:exists', 'Output folder already exists: %s', test_dir);
end
mkdir(test_dir);
repo_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(repo_root, 'openfast_q1', 'E2'));
lines = {sprintf('test_e5_P4a start %s, repository %s, TOL_GPU = %g, canUseGPU %d', stamp, repo_root, TOL_GPU, canUseGPU)};
err_lines = {};
results = struct('part', {}, 'check', {}, 'pass', {});
S = e5_settings();
p = rom_params(fullfile(repo_root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
% Ts = 0.05 s entry of normalisation_E4.csv (sha256 2bc33706..., E5 l.15), as test_e5_P2
nrm = struct('mu', [1.263110277; 122.5211024; 13.37803117; 17.65675016], ...
             'sd', [0.05276818504; 4.964281324; 6.938685982; 4.395360763], ...
             'mux', [4.508361182e-07; 4.654321233e-05], 'sdx', [0.001625369198; 0.1024837435]);
runs = [e5_synthetic_runs(3, 600, 6101, S, 'training'), e5_synthetic_runs(1, 600, 6102, S, 'validation')];
part = struct('train_filtered', [true; true; true; false], 'selection', [false; false; false; true]);
nn_opts = struct('max_epochs', 4, 'patience', 2, 'batch', 256, 'eval_batch', 512, 'exec', 'gpu');
cfgs = {'MLP', struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-3), 1;
        'C1',  struct('L', 4, 'n_hidden', 1, 'n_units', 16, 'lr', 1e-3), 4;
        'C2',  struct('L', 4, 'kernel', 2, 'channels', 16, 'lr', 1e-3), 4;
        'C3',  struct('L', 4, 'hidden', 16, 'n_layers', 1, 'lr', 1e-3), 4;
        'C5',  struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-3), 1};
c5 = struct('tr', [], 'sel', []);

% ---------------------------------------------------------------- (a) e5_nn_data
data = cell(size(cfgs, 1), 2);
try
    rows_c5_tr = e5_rows(runs, part.train_filtered, 'current', 1);
    rows_c5_sel = e5_rows(runs, part.selection, 'current', 1);
    [y_tr, keep_tr] = e5_c5_targets(runs, rows_c5_tr, nrm, p);
    [y_sel, keep_sel] = e5_c5_targets(runs, rows_c5_sel, nrm, p);
    c5.tr = struct('rows', rows_c5_tr, 'Y', y_tr, 'keep', keep_tr);
    c5.sel = struct('rows', rows_c5_sel, 'Y', y_sel, 'keep', keep_sel);
    for c = 1:size(cfgs, 1)
        fam = cfgs{c, 1};
        L = cfgs{c, 3};
        if strcmp(fam, 'C5')
            data{c, 1} = e5_nn_data(runs, part.train_filtered, fam, L, nrm, c5.tr);
            data{c, 2} = e5_nn_data(runs, part.selection, fam, L, nrm, c5.sel);
        else
            data{c, 1} = e5_nn_data(runs, part.train_filtered, fam, L, nrm);
            data{c, 2} = e5_nn_data(runs, part.selection, fam, L, nrm);
        end
    end
    sz = @(c) size(data{c, 1}.X);
    n_cur = 3*600;  n_win = 3*(600 - 3);  n_seq = 3*(600 - 4);
    ok_shape = isequal(sz(1), [4, n_cur]) && isequal(sz(2), [16, n_win]) && isequal(sz(3), [4, n_win, 4]) && ...
               isequal(sz(4), [4, n_seq, 5]) && isequal(sz(5), [4, nnz(keep_tr)]) && ...
               strcmp(data{2, 1}.fmt, 'CB') && strcmp(data{3, 1}.fmt, 'CBT') && strcmp(data{4, 1}.fmt, 'CBT') && ...
               all(cellfun(@(d) isa(d.X, 'single') && isa(d.Y, 'single') && size(d.Y, 1) == 2, data(:)));
    results = add(results, 'a', sprintf('layouts: MLP 4 x %d, C1 16 x %d, C2 4 x %d x 4, C3 4 x %d x 5, C5 4 x %d, single', ...
                  n_cur, n_win, n_win, n_seq, nnz(keep_tr)), ok_shape);
    [f_ref, y_ref] = e5_features(runs, e5_rows(runs, part.train_filtered, 'window', 4), 'window', 4, nrm, 'single');
    results = add(results, 'a', 'C1 arrays equal the transposed e5_features (window, lag 0 first) bit for bit', ...
                  isequal(data{2, 1}.X, f_ref') && isequal(data{2, 1}.Y, y_ref'));
    results = add(results, 'a', sprintf('C5: rows excluded by D7 (bounded rom_step) %d of %d, Y = single(scaled residual) of the rows kept', ...
                  data{5, 1}.n_excluded, numel(keep_tr)), data{5, 1}.n_excluded == nnz(~keep_tr) && ...
                  isequal(data{5, 1}.Y, single(y_tr(keep_tr, :))') && isequal(data{5, 1}.rows, rows_c5_tr(keep_tr, :)));
    c5_bad = c5.tr;
    c5_bad.rows = c5_bad.rows(2:end, :);
    results = add(results, 'a', 'refusals: unknown family, C5 without targets, C5 targets of other rows', ...
                  expect_error(@() e5_nn_data(runs, part.train_filtered, 'C4', 4, nrm), 'e5_nn_data:family') && ...
                  expect_error(@() e5_nn_data(runs, part.train_filtered, 'C5', 1, nrm), 'e5_nn_data:c5') && ...
                  expect_error(@() e5_nn_data(runs, part.train_filtered, 'C5', 1, nrm, c5_bad), 'e5_nn_data:c5'));
catch ME
    err_lines{end+1} = sprintf('(a)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'a', 'part (a) completed without error', false);
end

% ---------------------------------------------------------------- (b) one training per family
for c = 1:size(cfgs, 1)
    fam = cfgs{c, 1};
    try
        [net, st, rec] = e5_train_nn(fam, cfgs{c, 2}, 35001, data{c, 1}, data{c, 2}, nn_opts);
        [~, first_min] = min(rec.sel_loss);
        lrn_double = all(cellfun(@(v) isa(extractdata(v), 'double') && ~isgpuarray(extractdata(v)), net.Learnables.Value));
        state_ok = true;
        if strcmp(fam, 'C3')
            state_ok = ~isempty(net.State) && all(cellfun(@(v) isa(extractdata(v), 'double') && ...
                       all(extractdata(v) == 0, 'all'), net.State.Value));
        end
        model = e5_model(fam, st, nrm, struct('L', cfgs{c, 3}, 'p', p));
        x_run = runs(4).X;
        k = 100;
        z0 = model.init(x_run(k, 1:2)', x_run(k - S.l_max:k - 1, :));
        z1 = model.step(z0, x_run(k, 3), x_run(k, 4));
        ok = strcmp(rec.status, 'COMPLETE') && rec.best_epoch == first_min && rec.best_loss == min(rec.sel_loss) && ...
             rec.n_epochs <= nn_opts.max_epochs && lrn_double && state_ok && all(isfinite(z1));
        results = add(results, 'b', sprintf('%-3s GPU %d epochs, best epoch %d = first argmin, learnables double%s, model finite', ...
                      fam, rec.n_epochs, rec.best_epoch, state_text(fam)), ok);
    catch ME
        err_lines{end+1} = sprintf('(b) %s\n%s', fam, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'b', sprintf('%-3s training completed without error', fam), false);
    end
end

% ---------------------------------------------------------------- (c) restoration, NO_FINITE_LOSS, seeds
try
    tr = data{1, 1};  sel = data{1, 2};
    tr.Y = 3*ones(size(tr.Y), 'single');
    sel.Y = -3*ones(size(sel.Y), 'single');
    opts_c = struct('max_epochs', 20, 'patience', 3, 'batch', 256, 'eval_batch', 512, 'exec', 'gpu');
    [net, ~, rec] = e5_train_nn('MLP', struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-2), 35002, tr, sel, opts_c);
    loss_restored = loss_of(net, sel);
    ok = strcmp(rec.status, 'COMPLETE') && rec.best_epoch == 1 && rec.n_epochs == 1 + opts_c.patience && ...
         abs(loss_restored - rec.sel_loss(1)) <= TOL_GPU*rec.sel_loss(1) && rec.sel_loss(end) > rec.sel_loss(1);
    results = add(results, 'c', sprintf('restoration: best epoch %d, stop at epoch %d, restored loss %.6e = epoch 1 %.6e, last epoch %.6e', ...
                  rec.best_epoch, rec.n_epochs, loss_restored, rec.sel_loss(1), rec.sel_loss(end)), ok);
    sel_nan = data{1, 2};
    sel_nan.Y(1, 1) = NaN;
    [net_n, st_n, rec_n] = e5_train_nn('MLP', struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-3), 35001, data{1, 1}, sel_nan, nn_opts);
    results = add(results, 'c', sprintf('NO_FINITE_LOSS: status %s, no network, no model, best epoch %d, %d epochs = patience', ...
                  rec_n.status, rec_n.best_epoch, rec_n.n_epochs), strcmp(rec_n.status, 'NO_FINITE_LOSS') && isempty(net_n) && ...
                  isempty(st_n) && rec_n.best_epoch == 0 && rec_n.n_epochs == nn_opts.patience && isnan(rec_n.best_loss));
    one = struct('max_epochs', 1, 'patience', 1, 'batch', 256, 'eval_batch', 512, 'exec', 'gpu');
    cfg1 = struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-3);
    [~, ~, r1] = e5_train_nn('MLP', cfg1, 35003, data{1, 1}, data{1, 2}, one);
    [~, ~, r2] = e5_train_nn('MLP', cfg1, 35003, data{1, 1}, data{1, 2}, one);
    [~, ~, r3] = e5_train_nn('MLP', cfg1, 35001, data{1, 1}, data{1, 2}, one);
    results = add(results, 'c', 'A8: same seed, same initial learnables (SHA-256); another seed, different ones', ...
                  strcmp(r1.init_hash, r2.init_hash) && ~strcmp(r1.init_hash, r3.init_hash));
catch ME
    err_lines{end+1} = sprintf('(c)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'c', 'part (c) completed without error', false);
end

% ---------------------------------------------------------------- (d) C4 trial and identity
try
    [model4, fit4, rec4] = e5_train_c4(runs, part, struct('sched', 'du', 'L', 4), nrm, S, struct('m_max', 4));
    n_seg = numel(e5_segments(600, S));
    results = add(results, 'd', sprintf('A4 retained model M = %d: %s, %d rows, %d differing', rec4.m_best, rec4.identity.verdict, ...
                  rec4.identity.n_rows, rec4.identity.n_diff), strcmp(rec4.identity.verdict, 'PASS') && rec4.identity.n_rows == n_seg);
    results = add(results, 'd', sprintf('A4 model of m_max = %d local models: %s, %d rows, %d differing', rec4.m_max, ...
                  rec4.identity_max.verdict, rec4.identity_max.n_rows, rec4.identity_max.n_diff), ...
                  strcmp(rec4.identity_max.verdict, 'PASS') && rec4.identity_max.n_rows == n_seg && rec4.m_max == 4);
    Lm_bad = e5_convert_llm(fit4, fit4.m_max);
    Lm_bad.Th(1, 1) = Lm_bad.Th(1, 1) + 1e-9*max(1, abs(Lm_bad.Th(1, 1)));
    res_bad = e5_c4_identity(fit4.models{fit4.m_max}, Lm_bad, runs, part.selection, nrm, 4, S);
    results = add(results, 'd', sprintf('A4 crafted difference of 1e-9 in one parameter: %s, %d differing rows', res_bad.verdict, ...
                  res_bad.n_diff), strcmp(res_bad.verdict, 'FAIL') && res_bad.n_diff > 0);
    x_run = runs(4).X;
    z0 = model4.init(x_run(100, 1:2)', x_run(100 - S.l_max:99, :));
    results = add(results, 'd', sprintf('A6 warning count recorded (%d), model finite, status %s', rec4.n_warn, rec4.status), ...
                  isfield(rec4, 'n_warn') && isequal(rec4.n_warn, fit4.n_warn) && all(isfinite(model4.step(z0, x_run(100, 3), x_run(100, 4)))) && ...
                  strcmp(rec4.status, 'COMPLETE'));
catch ME
    err_lines{end+1} = sprintf('(d)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'd', 'part (d) completed without error', false);
end

% ---------------------------------------------------------------- (e) C6 trial
try
    cfg6 = struct('n_sub', 300, 'n_act', 40);
    [model6, G6, rec6] = e5_train_c6(runs, part, cfg6, 35001, nrm);
    [~, ~, rec6b] = e5_train_c6(runs, part, cfg6, 35001, nrm);
    [~, ~, rec6c] = e5_train_c6(runs, part, cfg6, 35002, nrm);
    F6 = e5_features(runs, rec6.sub_rows, 'current', 1, nrm, 'double');
    active = false(cfg6.n_sub, 1);
    active(rec6.act_pos) = true;
    results = add(results, 'e', 'A13: same seed, same subsample and active set; another seed, different ones', ...
                  isequal(rec6.sub_rows, rec6b.sub_rows) && isequal(rec6.act_pos, rec6b.act_pos) && ...
                  ~isequal(rec6.sub_rows, rec6c.sub_rows));
    x_run = runs(4).X;
    z1 = model6.step(x_run(100, 1:2)', x_run(100, 3), x_run(100, 4));
    results = add(results, 'e', 'A13: 300 rows, active set of 40 = the subsample rows at the drawn positions, shared, model finite', ...
                  size(rec6.sub_rows, 1) == 300 && numel(unique(rec6.act_pos)) == 40 && isequal(G6.Xa, F6(active, :)) && ...
                  all(isfinite(z1)) && strcmp(rec6.status, 'COMPLETE'));
catch ME
    err_lines{end+1} = sprintf('(e)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'e', 'part (e) completed without error', false);
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
lines{end+1} = ['TEST E5 P4a TRAINERS: ' verdict];
write_lines(fullfile(test_dir, 'verdict_test_e5_P4a.txt'), lines);
if isempty(err_lines)
    write_lines(fullfile(test_dir, 'errors.txt'), {'errors caught by test_e5_P4a: 0'});
else
    write_lines(fullfile(test_dir, 'errors.txt'), err_lines);
end
save(fullfile(test_dir, 'results.mat'), 'results', 'lines', 'TOL_GPU');
fprintf('%s\n', lines{end-1:end});
end

% ================================================================ helpers
function value = loss_of(net, sel)
% selection loss of a restored network, recomputed independently of e5_train_nn: learnables cast
% back to single (exact), predict on the GPU, mean of the squared errors of the two outputs
net_single = dlupdate(@(v) single(v), net);
y_pred = extractdata(predict(net_single, dlarray(gpuArray(sel.X), sel.fmt)));
value = double(gather(sum((y_pred - gpuArray(sel.Y)).^2, 'all')))/numel(sel.Y);
end

function s = state_text(fam)
if strcmp(fam, 'C3'), s = ', net.State double and zero'; else, s = ''; end
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
