function verdict = test_e5_P4b(out_dir)
%TEST_E5_P4B  Tests of package P4b of E5 (campaign driver), written before any run, on synthetic data
%only (e5_synthetic_runs); no E4 file is read; the Cp table of the repository is read for C5. The
%settings of the campaign (e5_campaign_settings, the 48 h ceiling included) are used unchanged.
%
%   verdict = test_e5_P4b(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/test_e5_P4b_<stamp>/
%   (the synthetic campaigns a, x, int, b, bad, c and their files), results.mat, errors.txt,
%   verdict_test_e5_P4b.txt. verdict 'PASS' if every check passes.
%   (a) e5_campaign_settings: the values of the spec (A1, A3, A7, A9, A10, A12, A16).
%   (b) e5_search_space and e5_campaign_plan: sizes of the spaces, C3 without (128, 2), lexicographic
%       order, draws of D1 (d) recomputed, 136 trials in the order of A16, scaled sum of A2.
%   (c) e5_ceiling_check (A3) on crafted values; (d) e5_select (A19) on crafted tables;
%       (e) e5_campaign_prereq (A7) on crafted facts; e5_stop_rule (A4) on crafted records.
%   (f) campaign a: a synthetic plan of 10 trials (MLP x 3 seeds, C4, C5 x 3, C6 x 3) with the
%       settings unchanged: COMPLETE; records and trials.csv (A15); spec values passed to the
%       trainers; A4 both PASS; A6; A5 flags; A11 exclusions; A14 cost in every trial; A8 draws in
%       meta; selection of the four families with A17.
%   (g) campaign x: a trial with an error stops the campaign with getReport in errors/ (A20).
%   (h) resume (l.154): campaign int = a without its last two lines and with one record changed;
%       campaign b reuses the 7 unchanged records and runs the 3 others; a campaign -a of another
%       commit is refused; campaign c, whose reused record holds 47.9 h, stops at the ceiling (A3).
%   Version 2 (supervisor review of 20/11/2026, K1 to K6):
%   (f) also: the fields of l.150 in every record (K4); the C5 targets computed after the C4
%       trial and before the first C5 trial (K3); the cache cleared once per family (K5).
%   (h) also: the refused resume of another commit is an ERROR stop at 'resume' with
%       errors/resume.txt (K1).
%   (i) K1: an error outside a trial (C5 targets of a context with an invalid cp_mode) stops the
%       campaign with stop.txt (FAILED_KEPT, ERROR, where C5_targets) and errors/C5_targets.txt.
%   (j) K2: campaign k2 with a crafted C4 record whose identity_max is FAIL; the -b resume does not
%       reuse it and runs the C4 trial again.
%   (k) K6: e5_campaign with a wrong expected_head raises e5_campaign:prereq; the listing of
%       results/ is unchanged and no folder Q1-E5-TRAIN-<date>-a is created; maxNumCompThreads is
%       restored after the call.
%   Every catch records getReport(ME, 'extended').

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_e5_P4b_' stamp]);
if exist(test_dir, 'dir')
    error('test_e5_P4b:exists', 'Output folder already exists: %s', test_dir);
end
mkdir(test_dir);
repo_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(repo_root, 'openfast_q1', 'E2'));
lines = {sprintf('test_e5_P4b start %s, repository %s, canUseGPU %d', stamp, repo_root, canUseGPU)};
err_lines = {};
results = struct('part', {}, 'check', {}, 'pass', {});
C = e5_campaign_settings();

% ---------------------------------------------------------------- (a) settings
try
    ok = C.ceiling_s == 172800 && C.allowance == 1.5 && strcmp(C.train_opts.exec, 'gpu') && C.train_opts.max_epochs == 100 && ...
         C.train_opts.patience == 10 && C.train_opts.batch == 4096 && C.c4_opts.m_max == 32 && ...
         isequal(C.families, {'MLP', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6'}) && isequal(C.seeds, [35001 35002 35003]) && ...
         C.search_seed == 35100 && C.n_draw == 8 && C.threads == 8 && strcmp(C.machine, 'DESKTOP-90QKMPU') && C.disk_min_gb == 20 && ...
         isequal([C.time_train.MLP, C.time_train.C1, C.time_train.C2, C.time_train.C3, C.time_train.C4, C.time_train.C5], ...
                 [416.5, 331.0, 865.0, 843.6, 1031.7, 416.5]) && isequal(C.time_train_c6, [298.0, 3915.0]) && ...
         isequal([C.time_eval.MLP, C.time_eval.C1, C.time_eval.C2, C.time_eval.C3, C.time_eval.C4, C.time_eval.C5, C.time_eval.C6], ...
                 [9.9, 12.3, 31.2, 36.6, 4.8, 140.7, 13.4]) && isequal(C.c6_cfgs, [10000 500; 40000 1000]) && ...
         strcmp(C.spec_sha, '076d190a30a042da2902da119ce3bf5e83559fc14cfa7981fbedddfd52911cbd');
    results = add(results, 'a', 'settings: 48 h, allowance 1.5, gpu, 100 epochs, patience 10, batch 4096, m_max 32, times of A1', ok);
catch ME
    err_lines{end+1} = sprintf('(a)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'a', 'part (a) completed without error', false);
end

% ---------------------------------------------------------------- (b) search space and plan
try
    SP = e5_search_space(C);
    sizes = arrayfun(@(s) size(s.values, 1), SP);
    sp3 = SP(4).values;
    ok_space = isequal({SP.family}, {'MLP', 'C1', 'C2', 'C3', 'C5'}) && isequal(sizes, [24 96 24 56 24]) && ...
               ~any(sp3(:, 2) == 128 & sp3(:, 3) == 2) && isequal(SP(2).values(1, :), [4 1 16 3e-4]) && ...
               isequal(SP(2).values(end, :), [34 3 128 1e-3]) && isequal(SP(2).values(2, :), [4 1 16 1e-3]);
    draws_ok = true;
    for f = 1:numel(SP)
        rng(35100, 'twister');
        perm = randperm(sizes(f));
        draws_ok = draws_ok && isequal(SP(f).drawn, perm(1:8));
    end
    results = add(results, 'b', 'spaces 24, 96, 24, 56, 24, C3 without (128, 2), lexicographic, draws = randperm(n) of rng 35100, first 8', ...
                  ok_space && draws_ok);
    plan = e5_campaign_plan(C);
    fam_seq = {plan.family};
    first_of = cellfun(@(f) find(strcmp(fam_seq, f), 1), C.families);
    tot = 0;
    for i = 1:numel(plan)
        T = e5_scaled_time(C, plan(i).family, plan(i).cfg_index);
        tot = tot + T.total;
    end
    counts = cellfun(@(f) nnz(strcmp(fam_seq, f)), C.families);
    ok_plan = numel(plan) == 136 && isequal(counts, [24 24 24 24 10 24 6]) && issorted(first_of) && ...
              isequal([plan(1:3).seed], C.seeds) && plan(1).cfg_index == SP(1).drawn(1) && plan(4).cfg_index == SP(1).drawn(2) && ...
              abs(tot - 146345.4) < 1e-6;
    results = add(results, 'b', sprintf('plan: 136 trials, order of A16, seeds inside a configuration, scaled sum %.1f s (A2 about 146340)', tot), ok_plan);
catch ME
    err_lines{end+1} = sprintf('(b)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'b', 'part (b) completed without error', false);
end

% ---------------------------------------------------------------- (c) ceiling, (d) selection, (e) prerequisites, stop rule
try
    [ok1, m1] = e5_ceiling_check(C.ceiling_s - 600, 600, C.ceiling_s);
    ok2 = e5_ceiling_check(C.ceiling_s - 600, 600.001, C.ceiling_s);
    results = add(results, 'c', 'A3: elapsed + scaled = 48 h allowed (margin 0), above refused, invalid values refused', ok1 && m1 == 0 && ~ok2 && ...
                  expect_error(@() e5_ceiling_check(-1, 1, C.ceiling_s), 'e5_ceiling_check:args') && ...
                  expect_error(@() e5_ceiling_check(NaN, 1, C.ceiling_s), 'e5_ceiling_check:args'));
catch ME
    err_lines{end+1} = sprintf('(c)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'c', 'part (c) completed without error', false);
end
try
    s1 = e5_select(tbl([1 35001 0 2.0 1e-5; 1 35002 0 1.0 1e-5; 1 35003 0 3.0 1e-5]));
    s2 = e5_select(tbl([1 35001 0 5.0 1e-5; 1 35002 0 5.0 1e-5; 1 35003 0 5.0 1e-5; 2 35001 1 0.5 1e-5; 2 35002 1 0.5 1e-5; 2 35003 1 0.5 1e-5]));
    s3 = e5_select(tbl([1 0 0 1.000 2e-5; 2 0 0 1.005 1e-5; 3 0 0 1.020 1e-6]));
    s4 = e5_select(tbl([1 0 0 1.000 1e-5; 2 0 0 1.004 1e-5]));
    s5 = e5_select(tbl([1 35001 0 1.0 3e-5; 1 35002 0 1.0 2e-5; 1 35003 0 1.0 1e-5]));
    s6 = e5_select(tbl([1 35001 0 Inf NaN; 1 35002 0 Inf NaN; 1 35003 0 Inf NaN; 2 35001 0 4.0 1e-5; 2 35002 0 4.0 1e-5; 2 35003 0 4.0 1e-5]));
    s7 = e5_select(tbl([1 35001 3 2.0 1e-5; 1 35002 0 9.0 1e-5; 1 35003 1 1.0 1e-5]));
    results = add(results, 'd', 'A19: median repetition, failed count first, tie < 1 % to the lower cost, equal costs to the lower criterion', ...
                  s1.retained_seed == 35001 && s2.retained_cfg == 1 && s3.retained_cfg == 2 && isequal(s3.configs.in_tie', [true true false]) && ...
                  s4.retained_cfg == 1);
    results = add(results, 'd', 'A19: equal pairs ordered by seed (middle seed 35002), infinite criterion never retained, failed count orders the repetitions', ...
                  s5.retained_seed == 35002 && s6.retained_cfg == 2 && s7.retained_seed == 35003 && s7.configs.n_failed == 1);
catch ME
    err_lines{end+1} = sprintf('(d)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'd', 'part (d) completed without error', false);
end
try
    good = struct('matlab_version', C.matlab_version, 'machine', C.machine, 'threads', C.threads, 'gpu', true, 'disk_free_gb', 100, ...
                  'head', repmat('a', 1, 40), 'expected_head', repmat('a', 1, 40), 'status_clean', true, 'spec_sha', C.spec_sha);
    faults = {'matlab_version', '24.2.0.1'; 'machine', 'OTHER-PC'; 'threads', 4; 'gpu', false; 'disk_free_gb', 10; ...
              'head', repmat('b', 1, 40); 'status_clean', false; 'spec_sha', repmat('0', 1, 64)};
    ok = isempty(e5_campaign_prereq(good, C));
    for k = 1:size(faults, 1)
        bad = good;
        bad.(faults{k, 1}) = faults{k, 2};
        ok = ok && isscalar(e5_campaign_prereq(bad, C));
    end
    results = add(results, 'e', 'A7: no refusal on the facts of the measurement; one refusal for each of 8 faults (version, machine, threads, GPU, disk, HEAD, status, spec)', ok);
    r_ok = struct('family', 'C4', 'identity', 'PASS', 'identity_max', 'PASS');
    r_f1 = r_ok;  r_f1.identity = 'FAIL';
    r_f2 = r_ok;  r_f2.identity_max = 'FAIL';
    r_nn = struct('family', 'MLP', 'identity', '', 'identity_max', '');
    results = add(results, 'e', 'A4 stop rule: FAIL of the retained or of the m_max comparison stops (A4), PASS and other families do not', ...
                  isempty(e5_stop_rule(r_ok)) && strcmp(e5_stop_rule(r_f1), 'A4') && strcmp(e5_stop_rule(r_f2), 'A4') && isempty(e5_stop_rule(r_nn)));
catch ME
    err_lines{end+1} = sprintf('(e)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'e', 'part (e) completed without error', false);
end

% ---------------------------------------------------------------- synthetic context
S = e5_settings();
S.n_rows_run = 600;
p = rom_params(fullfile(repo_root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
nrm = struct('mu', [1.263110277; 122.5211024; 13.37803117; 17.65675016], ...
             'sd', [0.05276818504; 4.964281324; 6.938685982; 4.395360763], ...
             'mux', [4.508361182e-07; 4.654321233e-05], 'sdx', [0.001625369198; 0.1024837435], ...
             'sha', 'synthetic normalisation of test_e5_P4b');
runs = [e5_synthetic_runs(3, 600, 7101, S, 'training'), e5_synthetic_runs(3, 600, 7102, S, 'validation')];
part = struct('train_filtered', logical([1 1 1 0 0 0])', 'selection', logical([0 0 0 1 1 0])', 'validation', logical([0 0 0 1 1 1])');
[~, head_out] = system(sprintf('git -C "%s" rev-parse HEAD', repo_root));
nn_cfg = struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-3);
plan_a = [entry('MLP', 1, 35001, nn_cfg), entry('MLP', 1, 35002, nn_cfg), entry('MLP', 1, 35003, nn_cfg), ...
          entry('C4', 1, 0, struct('sched', 'du', 'L', 1)), ...
          entry('C5', 1, 35001, nn_cfg), entry('C5', 1, 35002, nn_cfg), entry('C5', 1, 35003, nn_cfg), ...
          entry('C6', 1, 35001, struct('n_sub', 300, 'n_act', 40)), entry('C6', 1, 35002, struct('n_sub', 300, 'n_act', 40)), ...
          entry('C6', 1, 35003, struct('n_sub', 300, 'n_act', 40))];
ctx = struct('dir', '', 'mode', 'a', 'prev_dir', '', 'runs', {runs}, 'part', part, 'nrm', nrm, 'p', p, 'S', S, 'C', C, ...
             'plan', {plan_a}, 'head', strtrim(head_out), 'facts', struct('note', 'test_e5_P4b, synthetic data'), ...
             'data_info', struct('note', 'e5_synthetic_runs 7101, 7102'), 't0', tic);
dir_a = fullfile(test_dir, 'campaign_a');

% ---------------------------------------------------------------- (f) campaign a
try
    ctx_a = ctx;  ctx_a.dir = dir_a;  ctx_a.t0 = tic;
    res_a = e5_campaign_run(ctx_a);
    rows = e5_records('read', dir_a);
    ver_ok = all(arrayfun(@(r) e5_records('verify', dir_a, r), rows));
    results = add(results, 'f', sprintf('campaign a: %s, %d trials run, trials.csv %d lines in the plan order, every record and model SHA-256 verified (A15)', ...
                  res_a.status, res_a.n_run, numel(rows)), strcmp(res_a.status, 'COMPLETE') && res_a.n_run == 10 && ...
                  isequal({rows.trial_id}, {plan_a.trial_id}) && ver_ok && all(strcmp({rows.status}, 'COMPLETE')));
    opts_ok = true;  cost_ok = true;  flag_ok = true;
    for k = 1:numel(rows)
        rr = load(fullfile(dir_a, rows(k).record_file), 'rec');
        rec = rr.rec;
        T = e5_scaled_time(C, rec.family, rec.cfg_index);
        if any(strcmp(rec.family, {'MLP', 'C5'}))
            opts_ok = opts_ok && isequal(rec.train_opts, C.train_opts) && rec.train.max_epochs == 100 && rec.train.patience == 10 && ...
                      rec.train.batch == 4096 && strcmp(rec.train.exec, 'gpu');
        elseif strcmp(rec.family, 'C4')
            opts_ok = opts_ok && isequal(rec.c4_opts, C.c4_opts) && rec.train.m_max == 32;
            c4_rec = rec;
        end
        cost_ok = cost_ok && rec.cost.n == S.cost_calls - 1 && isfinite(rec.cost_median) && rec.time_cost > 0;
        flag_ok = flag_ok && isequal(rec.scaled, T) && any(rec.flag_train == [0 1]) && any(rec.flag_eval == [0 1]) && ...
                  rec.flag_train == double(rec.time_train > T.train) && rec.flag_eval == double(rec.time_eval > T.eval);
    end
    results = add(results, 'f', 'spec values passed to the trainers: gpu, 100 epochs, patience 10, batch 4096 (NN records), m_max 32 (C4 record)', opts_ok);
    results = add(results, 'f', 'A14 prediction cost in every trial (999 timed calls); A5 scaled times and flags in every record', cost_ok && flag_ok);
    results = add(results, 'f', sprintf('A4 retained %s and m_max %s in the C4 record and trials.csv; A6 warning count %d', c4_rec.identity, ...
                  c4_rec.identity_max, c4_rec.n_warn), strcmp(c4_rec.identity, 'PASS') && strcmp(c4_rec.identity_max, 'PASS') && ...
                  strcmp(rows(4).identity, 'PASS') && strcmp(rows(4).identity_max, 'PASS') && isfinite(c4_rec.n_warn));
    [~, keep_tr] = e5_c5_targets(runs, e5_rows(runs, part.train_filtered, 'current', 1), nrm, p);
    rr = load(fullfile(dir_a, rows(5).record_file), 'rec');
    results = add(results, 'f', sprintf('A11 C5 rows excluded %d = e5_c5_targets keep', rr.rec.n_excluded), rr.rec.n_excluded == nnz(~keep_tr));
    mm = load(fullfile(dir_a, 'meta.mat'), 'meta');
    meta_txt = fileread(fullfile(dir_a, 'meta.txt'));
    results = add(results, 'f', sprintf('A8 draws and enumeration in meta.mat and meta.txt, settings and plan recorded; A7 GPU name in meta (%s)', mm.meta.gpu_name), ...
                  isfield(mm.meta, 'gpu_name') && ~isempty(mm.meta.gpu_name) && contains(meta_txt, ['gpu ' mm.meta.gpu_name]) && ...
                  isequal(mm.meta.draws, e5_search_space(C)) && isequal(mm.meta.settings, C) && contains(meta_txt, 'draws C3 (56 configurations') && ...
                  isequal(mm.meta.plan_ids, {plan_a.trial_id}));
    sel_txt = splitlines(strtrim(fileread(fullfile(dir_a, 'selection.csv'))));
    so = load(fullfile(dir_a, 'selection_MLP.mat'), 'out');
    results = add(results, 'f', 'A19 and A17: selection of MLP, C4, C5, C6; retained model evaluated on the other validation run and for plausibility', ...
                  numel(sel_txt) == 5 && all(isfile(fullfile(dir_a, strcat('selection_', {'MLP', 'C4', 'C5', 'C6'}, '.mat')))) && ...
                  ~isempty(so.out.validation_other) && numel(so.out.validation_other.seg_a.e_max) == numel(e5_segments(600, S)) && so.out.plausibility.n > 0);
    k4_ok = true;
    k4_names = {'partitions', 'loss', 'optimiser', 'normalisation_sha', 'stopping_rule'};
    for k = 1:numel(rows)
        rr = load(fullfile(dir_a, rows(k).record_file), 'rec');
        rec = rr.rec;
        k4_ok = k4_ok && all(isfield(rec, k4_names)) && isequal(rec.partitions.train_filtered, {runs(part.train_filtered).id}) && ...
                isequal(rec.partitions.selection, {runs(part.selection).id}) && strcmp(rec.normalisation_sha, nrm.sha) && ...
                ischar(rec.loss) && ~isempty(rec.loss) && ischar(rec.optimiser) && ~isempty(rec.optimiser) && ...
                ischar(rec.stopping_rule) && ~isempty(rec.stopping_rule);
    end
    results = add(results, 'f', 'K4: partitions, loss, optimiser, normalisation SHA-256 and stopping rule in every record (l.150)', k4_ok);
    log_a = regexprep(splitlines(fileread(fullfile(dir_a, 'log.txt'))), '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} ', '');   % date and time of log_line removed
    i_c4 = find(startsWith(log_a, 'C4_c01_s0 '), 1);
    i_tg = find(startsWith(log_a, 'C5 targets:'));
    i_c5 = find(startsWith(log_a, 'C5_c01_s35001 '), 1);
    results = add(results, 'f', 'K3: C5 targets computed once, after the C4 trial and before the first C5 trial (A11)', ...
                  isscalar(i_tg) && isscalar(i_c4) && isscalar(i_c5) && i_c4 < i_tg && i_tg < i_c5);
    cache_lines = log_a(startsWith(log_a, 'data cache cleared at the start of family '));
    results = add(results, 'f', 'K5: data cache cleared once at the start of each family (MLP, C4, C5, C6)', ...
                  isequal(strrep(cache_lines', 'data cache cleared at the start of family ', ''), {'MLP', 'C4', 'C5', 'C6'}));
catch ME
    err_lines{end+1} = sprintf('(f)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'f', 'part (f) completed without error', false);
end

% ---------------------------------------------------------------- (g) A20
try
    ctx_x = ctx;  ctx_x.dir = fullfile(test_dir, 'campaign_x');  ctx_x.t0 = tic;
    ctx_x.plan = [entry('MLP', 1, 35001, nn_cfg), entry('C1', 1, 35001, struct('L', 5, 'n_hidden', 1, 'n_units', 16, 'lr', 1e-3))];
    res_x = e5_campaign_run(ctx_x);
    err_file = fullfile(ctx_x.dir, 'errors', 'C1_c01_s35001.txt');
    err_txt = '';
    if isfile(err_file)
        err_txt = fileread(err_file);
    end
    stop_txt = fileread(fullfile(ctx_x.dir, 'stop.txt'));
    rows_x = e5_records('read', ctx_x.dir);
    results = add(results, 'g', sprintf('A20: error in trial %s stops the campaign (%s, %s), report of getReport in errors/, 1 line in trials.csv', ...
                  res_x.trial_id, res_x.status, res_x.reason), strcmp(res_x.status, 'INTERRUPTED') && strcmp(res_x.reason, 'ERROR') && ...
                  strcmp(res_x.trial_id, 'C1_c01_s35001') && contains(err_txt, 'L must be 4, 8, 16 or 34') && contains(err_txt, 'e5_net_c1') && ...
                  contains(stop_txt, 'FAILED_KEPT') && isscalar(rows_x));
catch ME
    err_lines{end+1} = sprintf('(g)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'g', 'part (g) completed without error', false);
end

% ---------------------------------------------------------------- (h) resume and ceiling
try
    dir_int = fullfile(test_dir, 'campaign_int');
    copyfile(dir_a, dir_int);
    csv_lines = splitlines(strtrim(fileread(fullfile(dir_int, 'trials.csv'))));
    write_lines(fullfile(dir_int, 'trials.csv'), csv_lines(1:end - 2));
    fid = fopen(fullfile(dir_int, 'records', 'MLP_c01_s35002.mat'), 'a');
    fwrite(fid, uint8(0));
    fclose(fid);
    ctx_b = ctx;  ctx_b.dir = fullfile(test_dir, 'campaign_b');  ctx_b.mode = 'b';  ctx_b.prev_dir = dir_int;  ctx_b.t0 = tic;
    res_b = e5_campaign_run(ctx_b);
    rows_b = e5_records('read', ctx_b.dir);
    reused_ids = {rows_b([rows_b.reused] == 1).trial_id};
    run_ids = {rows_b([rows_b.reused] == 0).trial_id};
    exp_reused = {plan_a([1 3 4 5 6 7 8]).trial_id};
    exp_run = {plan_a([2 9 10]).trial_id};
    ver_b = all(arrayfun(@(r) e5_records('verify', ctx_b.dir, r), rows_b));
    results = add(results, 'h', sprintf('resume -b: %s, %d reused (SHA-256 unchanged), %d run (missing or changed), every file verified', ...
                  res_b.status, res_b.n_reused, res_b.n_run), strcmp(res_b.status, 'COMPLETE') && res_b.n_reused == 7 && res_b.n_run == 3 && ...
                  isequal(sort(reused_ids), sort(exp_reused)) && isequal(sort(run_ids), sort(exp_run)) && ver_b);
    dir_bad = fullfile(test_dir, 'campaign_bad');
    copyfile(dir_int, dir_bad);
    mb = load(fullfile(dir_bad, 'meta.mat'), 'meta');
    meta = mb.meta;
    meta.head = repmat('0', 1, 40);
    save(fullfile(dir_bad, 'meta.mat'), 'meta', '-v7');
    ctx_bad = ctx_b;  ctx_bad.dir = fullfile(test_dir, 'campaign_b_bad');  ctx_bad.prev_dir = dir_bad;  ctx_bad.t0 = tic;
    res_bad = e5_campaign_run(ctx_bad);
    stop_bad = fileread(fullfile(ctx_bad.dir, 'stop.txt'));
    err_bad = fullfile(ctx_bad.dir, 'errors', 'resume.txt');
    results = add(results, 'h', sprintf(['resume -b refused for a campaign -a of another code commit: %s, %s at %s, %s, ' ...
                  'errors/resume.txt (K1)'], res_bad.status, res_bad.reason, res_bad.trial_id, res_bad.error_id), ...
                  strcmp(res_bad.status, 'INTERRUPTED') && strcmp(res_bad.reason, 'ERROR') && strcmp(res_bad.trial_id, 'resume') && ...
                  strcmp(res_bad.error_id, 'e5_campaign_run:resume') && isfile(err_bad) && contains(fileread(err_bad), 'another code commit, spec or plan') && ...
                  contains(stop_bad, 'FAILED_KEPT') && contains(stop_bad, 'where resume') && res_bad.n_run == 0 && res_bad.n_reused == 0);
    dir_c = fullfile(test_dir, 'campaign_c');
    mkdir(dir_c);
    copyfile(fullfile(dir_a, 'meta.mat'), fullfile(dir_c, 'meta.mat'));
    e5_records('init', dir_c);
    pay = load(fullfile(dir_a, 'models', 'MLP_c01_s35001.mat'));
    rc = load(fullfile(dir_a, 'records', 'MLP_c01_s35001.mat'), 'rec');
    rec_c = rc.rec;
    rec_c.time_total = 47.9*3600;
    e5_records('write', dir_c, pay, rec_c);
    ctx_c = ctx_b;  ctx_c.dir = fullfile(test_dir, 'campaign_c_b');  ctx_c.prev_dir = dir_c;  ctx_c.t0 = tic;
    res_c = e5_campaign_run(ctx_c);
    stop_c = fileread(fullfile(ctx_c.dir, 'stop.txt'));
    results = add(results, 'h', sprintf('A3 in the driver: reused record of 47.9 h, next trial refused (%s, %s at %s), stop as an interruption', ...
                  res_c.status, res_c.reason, res_c.trial_id), strcmp(res_c.status, 'INTERRUPTED') && strcmp(res_c.reason, 'CEILING') && ...
                  strcmp(res_c.trial_id, 'MLP_c01_s35002') && res_c.n_reused == 1 && res_c.n_run == 0 && contains(stop_c, 'FAILED_KEPT'));
catch ME
    err_lines{end+1} = sprintf('(h)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'h', 'part (h) completed without error', false);
end

% ---------------------------------------------------------------- (i) K1, error outside a trial
try
    ctx_i = ctx;  ctx_i.dir = fullfile(test_dir, 'campaign_k1');  ctx_i.t0 = tic;
    ctx_i.p.cp_mode = 'invalid_for_test';
    ctx_i.plan = entry('C5', 1, 35001, nn_cfg);
    res_i = e5_campaign_run(ctx_i);
    stop_i = fileread(fullfile(ctx_i.dir, 'stop.txt'));
    err_i = fullfile(ctx_i.dir, 'errors', 'C5_targets.txt');
    err_txt = '';
    if isfile(err_i)
        err_txt = fileread(err_i);
    end
    rows_i = e5_records('read', ctx_i.dir);
    results = add(results, 'i', sprintf('K1: error of the C5 targets outside a trial: %s, %s at %s, %s; stop.txt and errors/C5_targets.txt', ...
                  res_i.status, res_i.reason, res_i.trial_id, res_i.error_id), strcmp(res_i.status, 'INTERRUPTED') && ...
                  strcmp(res_i.reason, 'ERROR') && strcmp(res_i.trial_id, 'C5_targets') && strcmp(res_i.error_id, 'e5_c5_targets:cpMode') && ...
                  contains(stop_i, 'FAILED_KEPT') && contains(stop_i, 'reason ERROR') && contains(stop_i, 'where C5_targets') && ...
                  contains(err_txt, 'e5_c5_targets') && isempty(rows_i) && res_i.n_run == 0);
catch ME
    err_lines{end+1} = sprintf('(i)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'i', 'part (i) completed without error', false);
end

% ---------------------------------------------------------------- (j) K2, an A4 record is not reused
try
    plan_k2 = plan_a(4);
    dir_k2 = fullfile(test_dir, 'campaign_k2');
    mkdir(dir_k2);
    mk = load(fullfile(dir_a, 'meta.mat'), 'meta');
    meta = mk.meta;
    meta.plan_ids = {plan_k2.trial_id};
    meta.plan = plan_k2;
    save(fullfile(dir_k2, 'meta.mat'), 'meta', '-v7');
    e5_records('init', dir_k2);
    pay = load(fullfile(dir_a, 'models', 'C4_c01_s0.mat'));
    rk = load(fullfile(dir_a, 'records', 'C4_c01_s0.mat'), 'rec');
    rec_k2 = rk.rec;
    rec_k2.identity_max = 'FAIL';
    e5_records('write', dir_k2, pay, rec_k2);
    rows_k2 = e5_records('read', dir_k2);
    ctx_j = ctx;  ctx_j.dir = fullfile(test_dir, 'campaign_k2_b');  ctx_j.mode = 'b';  ctx_j.prev_dir = dir_k2;  ctx_j.t0 = tic;
    ctx_j.plan = plan_k2;
    res_j = e5_campaign_run(ctx_j);
    rows_j = e5_records('read', ctx_j.dir);
    log_j = fileread(fullfile(ctx_j.dir, 'log.txt'));
    results = add(results, 'j', sprintf(['K2: crafted C4 record with identity_max FAIL (SHA-256 verified %d) not reused by -b: %s, ' ...
                  '%d reused, %d run, identity_max of the new record %s'], e5_records('verify', dir_k2, rows_k2), res_j.status, ...
                  res_j.n_reused, res_j.n_run, strjoin({rows_j.identity_max}, ' ')), e5_records('verify', dir_k2, rows_k2) && ...
                  strcmp(e5_stop_rule(rec_k2), 'A4') && strcmp(res_j.status, 'COMPLETE') && res_j.n_reused == 0 && res_j.n_run == 1 && ...
                  isscalar(rows_j) && rows_j.reused == 0 && strcmp(rows_j.identity_max, 'PASS') && ...
                  contains(log_j, 'resume: line C4_c01_s0 not reused (A4 stop rule'));
catch ME
    err_lines{end+1} = sprintf('(j)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'j', 'part (j) completed without error', false);
end

% ---------------------------------------------------------------- (k) K6, e5_campaign refused before any loading
threads_before = maxNumCompThreads;
try
    res_dir = fullfile(repo_root, 'results');
    listing = dir(res_dir);
    list_before = sort({listing.name});
    camp_dir_a = fullfile(res_dir, sprintf('Q1-E5-TRAIN-%s-a', char(datetime('now', 'Format', 'yyyy-MM-dd'))));
    existed_before = isfolder(camp_dir_a);
    refused = expect_error(@() e5_campaign(repmat('0', 1, 40)), 'e5_campaign:prereq');
    maxNumCompThreads(threads_before);
    listing = dir(res_dir);
    list_after = sort({listing.name});
    results = add(results, 'k', sprintf(['K6: e5_campaign with a wrong expected_head raises e5_campaign:prereq; listing of results/ ' ...
                  'unchanged (%d entries); no campaign folder created; maxNumCompThreads restored to %d'], numel(list_after), threads_before), ...
                  refused && isequal(list_before, list_after) && (existed_before || ~isfolder(camp_dir_a)) && maxNumCompThreads == threads_before);
catch ME
    maxNumCompThreads(threads_before);
    err_lines{end+1} = sprintf('(k)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'k', 'part (k) completed without error', false);
end

% ---------------------------------------------------------------- verdict
all_pass = ~isempty(results) && all([results.pass]);
for k = 1:numel(results)
    lines{end+1} = sprintf('(%s) %-120s %s', results(k).part, results(k).check, pass_word(results(k).pass)); %#ok<AGROW>
end
if all_pass
    verdict = 'PASS';
else
    verdict = 'FAIL';
end
lines{end+1} = sprintf('checks %d, passed %d, errors caught %d', numel(results), nnz([results.pass]), numel(err_lines));
lines{end+1} = ['TEST E5 P4b CAMPAIGN DRIVER: ' verdict];
write_lines(fullfile(test_dir, 'verdict_test_e5_P4b.txt'), lines);
if isempty(err_lines)
    write_lines(fullfile(test_dir, 'errors.txt'), {'errors caught by test_e5_P4b: 0'});
else
    write_lines(fullfile(test_dir, 'errors.txt'), err_lines);
end
save(fullfile(test_dir, 'results.mat'), 'results', 'lines');
fprintf('%s\n', lines{end-1:end});
end

% ================================================================ helpers
function e = entry(fam, cfg_index, seed, cfg)
e = struct('trial_id', sprintf('%s_c%02d_s%d', fam, cfg_index, seed), 'family', fam, 'cfg_index', cfg_index, ...
           'seed', seed, 'cfg', cfg);
end

function T = tbl(m)
T = table(m(:, 1), m(:, 2), m(:, 3), m(:, 4), m(:, 5), 'VariableNames', {'cfg_index', 'seed', 'n_failed', 'criterion', 'cost'});
end

function results = add(results, part_name, check_name, pass)
results(end+1) = struct('part', part_name, 'check', check_name, 'pass', logical(pass));
fprintf('(%s) %-120s %s\n', part_name, check_name, pass_word(pass));
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
