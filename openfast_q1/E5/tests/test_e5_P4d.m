function verdict = test_e5_P4d(out_dir)
%TEST_E5_P4D  Test of package P4d of E5 (resume of an interrupted session, spec_E5 amendment 6, R12),
%written before any run, on synthetic data only (e5_synthetic_runs); no E4 file is read; the Cp
%table of the repository is read for C5. The settings of e5_campaign_settings are used unchanged.
%
%   verdict = test_e5_P4d(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/test_e5_P4d_<stamp>/
%   (synthetic results folders with their campaign folders and console logs), results.mat,
%   errors.txt, verdict_test_e5_P4d.txt. verdict 'PASS' if every check passes.
%   A base campaign of the sessions 1 to 3 on a plan of 8 trials (MLP, C1, C2 x 2, C3, C4, C5, C6)
%   gives the folder states copied by the cases below.
%   (a) power cut inside session 2 (start line, one C2 line, an orphan model and record file of the
%       second C2 trial, its trial start line, no meta_session2): resume into -b (R1 b, R2, R3, R5),
%       then session 3 in -b (R6); the -a folder unchanged; elapsed time of R5; log lines of R5.
%   (b) power cut before the first line of session 2: resume with elapsed time 0 (R1 b, R5).
%   (c) ERROR in session 4 (C5 targets of a context with an invalid cp_mode), resume of session 4
%       then session 5: COMPLETE (R1 a, R6); a C5 count different from the interrupted log: ERROR
%       stop e5_campaign_run:c5Count (R10).
%   (d) refusals, each with every campaign folder unchanged: A4; CEILING; a second resume of the
%       same session (R7); HEAD, spec SHA-256, plan different; a record of an earlier session
%       changed; a selection of an earlier session changed (R4); a resume of a SESSION_COMPLETE
%       session; a resume out of order; the resume folder existing (R8); a normal launch of a
%       started session (R6).
%   (e) the cumulative ceiling reached in a resume (S5, R5), then the resume refused again (R7).
%   (f) a truncated last line of trials.csv dropped and its trial run again; a malformed line that
%       is not the last refused (R9).
%   (g) e5_campaign(wrong head, 'resume', k): e5_campaign:prereq; k = 7: e5_campaign:mode; the
%       listing of results/ unchanged; maxNumCompThreads restored.
%   Every catch records getReport(ME, 'extended').

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_e5_P4d_' stamp]);
if exist(test_dir, 'dir')
    error('test_e5_P4d:exists', 'Output folder already exists: %s', test_dir);
end
mkdir(test_dir);
repo_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(repo_root, 'openfast_q1', 'E2'));
lines = {sprintf('test_e5_P4d start %s, repository %s, canUseGPU %d', stamp, repo_root, canUseGPU)};
err_lines = {};
results = struct('part', {}, 'check', {}, 'pass', {});
C = e5_campaign_settings();

% ---------------------------------------------------------------- synthetic context
S = e5_settings();
S.n_rows_run = 600;
p = rom_params(fullfile(repo_root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
nrm = struct('mu', [1.263110277; 122.5211024; 13.37803117; 17.65675016], ...
             'sd', [0.05276818504; 4.964281324; 6.938685982; 4.395360763], ...
             'mux', [4.508361182e-07; 4.654321233e-05], 'sdx', [0.001625369198; 0.1024837435], ...
             'sha', 'synthetic normalisation of test_e5_P4d');
runs = [e5_synthetic_runs(3, 600, 7101, S, 'training'), e5_synthetic_runs(3, 600, 7102, S, 'validation')];
part = struct('train_filtered', logical([1 1 1 0 0 0])', 'selection', logical([0 0 0 1 1 0])', 'validation', logical([0 0 0 1 1 1])');
[~, head_out] = system(sprintf('git -C "%s" rev-parse HEAD', repo_root));
nn_cfg = struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-3);
c2_cfg = struct('L', 4, 'kernel', 2, 'channels', 16, 'lr', 1e-3);
plan_d = [entry('MLP', 1, 35001, nn_cfg), entry('C1', 1, 35001, struct('L', 4, 'n_hidden', 1, 'n_units', 16, 'lr', 1e-3)), ...
          entry('C2', 1, 35001, c2_cfg), entry('C2', 1, 35002, c2_cfg), ...
          entry('C3', 1, 35001, struct('L', 4, 'hidden', 16, 'n_layers', 1, 'lr', 1e-3)), ...
          entry('C4', 1, 0, struct('sched', 'du', 'L', 1)), entry('C5', 1, 35001, nn_cfg), ...
          entry('C6', 1, 35001, struct('n_sub', 300, 'n_act', 40))];
ctx = struct('dir', '', 'mode', 'session', 'session', 1, 'prev_dir', '', 'chain', {{}}, 'runs', {runs}, 'part', part, ...
             'nrm', nrm, 'p', p, 'S', S, 'C', C, 'plan', {plan_d}, 'head', strtrim(head_out), ...
             'facts', struct('note', 'test_e5_P4d, synthetic data'), 'data_info', struct('note', 'e5_synthetic_runs 7101, 7102'), 't0', tic);
snap = fullfile(test_dir, 'snapshots');
mkdir(snap);
name_a = '';
name_b = '';

% ---------------------------------------------------------------- base campaign: sessions 1 to 3
try
    root0 = fullfile(test_dir, 'results_base');
    mkdir(root0);
    st0 = cell(1, 3);
    for k = 1:3
        [res0, P0] = run_session(ctx, root0, k);
        st0{k} = res0.status;
        copyfile(P0.dir, fullfile(snap, sprintf('after_s%d', k)));
    end
    name_a = P0.name;
    name_b = [name_a(1:end - 1) 'b'];
    ms1 = load_ms(fullfile(snap, 'after_s1'), 1);
    results = add(results, 'base', sprintf(['sessions 1 to 3 of the base campaign: %s; meta_session1 records the SHA-256 and ' ...
                  'the line of selection.csv of MLP and C1 (R4)'], strjoin(st0, ' ')), isequal(st0, repmat({'SESSION_COMPLETE'}, 1, 3)) && ...
                  isequal({ms1.selections.family}, {'MLP', 'C1'}) && ...
                  strcmp(ms1.selections(1).sha, e5_sha256(fullfile(snap, 'after_s1', 'selection_MLP.mat'))));
    log0 = read_lines(fullfile(snap, 'after_s3', 'log.txt'));
    results = add(results, 'base', ['R5: every line of log.txt written by the sessions ends with the elapsed time; a trial start line ' ...
                  'precedes each trial'], all(~cellfun(@isempty, regexp(log0, '\| elapsed_s \d+(\.\d+)?$', 'once'))) && ...
                  nnz(startsWith(strip_date(log0), 'trial start ')) == 5);
catch ME
    err_lines{end+1} = sprintf('(base)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'base', 'base campaign completed without error', false);
end

% ---------------------------------------------------------------- crafted state: power cut inside session 2
snap_cut = fullfile(snap, 'cut_s2');
try
    copyfile(fullfile(snap, 'after_s2'), snap_cut);
    delete(fullfile(snap_cut, 'meta_session2.mat'));
    delete(fullfile(snap_cut, 'meta_session2.txt'));
    delete(fullfile(snap_cut, 'selection_C2.mat'));
    sel_l = read_lines(fullfile(snap_cut, 'selection.csv'));
    write_lines(fullfile(snap_cut, 'selection.csv'), sel_l(~startsWith(sel_l, 'C2;')));
    csv_l = read_lines(fullfile(snap_cut, 'trials.csv'));
    write_lines(fullfile(snap_cut, 'trials.csv'), csv_l(1:end - 1));       % C2_c01_s35002: model and record left orphan
    log_l = read_lines(fullfile(snap_cut, 'log.txt'));
    i_ts = find(startsWith(strip_date(log_l), 'trial start C2_c01_s35002 '), 1);
    write_lines(fullfile(snap_cut, 'log.txt'), log_l(1:i_ts));
    el_tok = regexp(log_l{i_ts}, 'elapsed_s (\d+(?:\.\d+)?)$', 'tokens', 'once');
    T_c2 = e5_scaled_time(C, 'C2', 1);
    expected_cut = str2double(el_tok{1}) + T_c2.total;
catch ME
    err_lines{end+1} = sprintf('(cut)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'a', 'crafted state of the power cut completed without error', false);
    expected_cut = NaN;
end

% ---------------------------------------------------------------- (a) power cut inside session 2, resume, session 3
try
    root_a = make_root(test_dir, 'results_a', snap_cut, name_a);
    dig_a = folder_digest(fullfile(root_a, name_a));
    res_a = run_resume(ctx, root_a, 2);
    dir_b = fullfile(root_a, name_b);
    copyfile(root_a, fullfile(snap, 'root_a_after_resume'));
    rows_b = e5_records('read', dir_b);
    mb = load(fullfile(dir_b, 'meta.mat'), 'meta');
    ms2 = load_ms(dir_b, 2);
    ms1 = load_ms(fullfile(snap, 'after_s1'), 1);
    results = add(results, 'a', sprintf(['R1 b, R2, R3: resume of session 2 into %s: %s, %d reused, %d run; trials.csv of -b ' ...
                  '%s with reused %s; every line verified'], name_b, res_a.status, res_a.n_reused, res_a.n_run, ...
                  strjoin({rows_b.trial_id}, ' '), mat2str([rows_b.reused])), strcmp(res_a.status, 'SESSION_COMPLETE') && ...
                  res_a.n_reused == 3 && res_a.n_run == 1 && isequal({rows_b.trial_id}, {plan_d(1:4).trial_id}) && ...
                  isequal([rows_b.reused], [1 1 1 0]) && all(arrayfun(@(r) e5_records('verify', dir_b, r), rows_b)) && ...
                  strcmp(mb.meta.mode, 'resume') && strcmp(mb.meta.resume_case, 'NO_META') && mb.meta.resume_session == 2);
    results = add(results, 'a', sprintf(['R5: elapsed of the cut session = last elapsed_s of its lines + scaled time of the trial ' ...
                  'started and not recorded = %.1f s (expected %.1f s); cumulative before the resume = meta_session1 + that'], ...
                  mb.meta.elapsed_interrupted_s, expected_cut), abs(mb.meta.elapsed_interrupted_s - expected_cut) < 1e-6 && ...
                  abs(mb.meta.elapsed_prior_s - (ms1.elapsed_cumulative_s + expected_cut)) < 1e-6 && ...
                  abs(ms2.elapsed_prior_s - mb.meta.elapsed_prior_s) < 1e-9);
    results = add(results, 'a', 'R2: the interrupted -a folder is unchanged by the resume', isequal(dig_a, folder_digest(fullfile(root_a, name_a))));
    res_a3 = run_session(ctx, root_a, 3);
    rows_b3 = e5_records('read', dir_b);
    log_b = read_lines(fullfile(dir_b, 'log.txt'));
    results = add(results, 'a', sprintf(['R6: session 3 after the resume runs in %s: %s, %d run; trials.csv of -b 5 lines; -a ' ...
                  'unchanged; every line of the -b log ends with elapsed_s'], name_b, res_a3.status, res_a3.n_run), ...
                  strcmp(res_a3.status, 'SESSION_COMPLETE') && res_a3.n_run == 1 && numel(rows_b3) == 5 && ...
                  isequal(dig_a, folder_digest(fullfile(root_a, name_a))) && ...
                  all(~cellfun(@isempty, regexp(log_b, '\| elapsed_s \d+(\.\d+)?$', 'once'))) && ...
                  ~isfile(fullfile(root_a, name_a, 'meta_session3.mat')) && isfile(fullfile(dir_b, 'meta_session3.mat')));
catch ME
    err_lines{end+1} = sprintf('(a)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'a', 'part (a) completed without error', false);
end

% ---------------------------------------------------------------- (b) power cut before the first line of session 2
try
    root_bb = make_root(test_dir, 'results_b', fullfile(snap, 'after_s1'), name_a);
    res_bb = run_resume(ctx, root_bb, 2);
    mbb = load(fullfile(root_bb, name_b, 'meta.mat'), 'meta');
    ms1 = load_ms(fullfile(snap, 'after_s1'), 1);
    results = add(results, 'b', sprintf(['R1 b, R5: no line of session 2: resume %s, %d reused, %d run, elapsed of the cut ' ...
                  'session %.1f s, cumulative before the resume = meta_session1'], res_bb.status, res_bb.n_reused, res_bb.n_run, ...
                  mbb.meta.elapsed_interrupted_s), strcmp(res_bb.status, 'SESSION_COMPLETE') && res_bb.n_reused == 2 && ...
                  res_bb.n_run == 2 && mbb.meta.elapsed_interrupted_s == 0 && ...
                  abs(mbb.meta.elapsed_prior_s - ms1.elapsed_cumulative_s) < 1e-9 && strcmp(mbb.meta.resume_case, 'NO_META'));
catch ME
    err_lines{end+1} = sprintf('(b)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'b', 'part (b) completed without error', false);
end

% ---------------------------------------------------------------- (c) ERROR in session 4, resume, session 5; R10
snap_err = fullfile(snap, 'err_s4');
try
    root_c = make_root(test_dir, 'results_c', fullfile(snap, 'after_s3'), name_a);
    ctx_bad = ctx;
    ctx_bad.p.cp_mode = 'invalid_for_test';
    res_c4 = run_session(ctx_bad, root_c, 4);
    copyfile(fullfile(root_c, name_a), snap_err);
    ms4 = load_ms(fullfile(root_c, name_a), 4);
    ms3 = load_ms(fullfile(snap, 'after_s3'), 3);
    results = add(results, 'c', sprintf('session 4 with an invalid cp_mode: %s, %s at %s; meta_session4 %s %s', res_c4.status, ...
                  res_c4.reason, res_c4.trial_id, ms4.status, ms4.reason), strcmp(res_c4.status, 'INTERRUPTED') && ...
                  strcmp(res_c4.reason, 'ERROR') && strcmp(res_c4.trial_id, 'C5_targets') && strcmp(ms4.reason, 'ERROR'));
    res_r4 = run_resume(ctx, root_c, 4);
    mc = load(fullfile(root_c, name_b, 'meta.mat'), 'meta');
    res_c5 = run_session(ctx, root_c, 5);
    rows_c = e5_records('read', fullfile(root_c, name_b));
    sel_c = read_lines(fullfile(root_c, name_b, 'selection.csv'));
    results = add(results, 'c', sprintf(['R1 a, R6: resume of session 4 (case %s): %s, %d reused, %d run; session 5 in -b: %s; ' ...
                  'trials.csv of -b 8 lines, selection.csv 7 families'], mc.meta.resume_case, res_r4.status, res_r4.n_reused, ...
                  res_r4.n_run, res_c5.status), strcmp(mc.meta.resume_case, 'ERROR') && strcmp(res_r4.status, 'SESSION_COMPLETE') && ...
                  res_r4.n_reused == 6 && res_r4.n_run == 1 && strcmp(res_c5.status, 'COMPLETE') && numel(rows_c) == 8 && ...
                  numel(sel_c) == 8);
    results = add(results, 'c', sprintf(['S5, R5: cumulative before the resume = meta_session3 + elapsed of the interrupted ' ...
                  'session 4 from meta_session4 (%.1f s)'], ms4.elapsed_session_s), ...
                  abs(mc.meta.elapsed_prior_s - (ms3.elapsed_cumulative_s + ms4.elapsed_session_s)) < 1e-9);
    root_c2 = make_root(test_dir, 'results_c2', snap_err, name_a);
    fid = fopen(fullfile(root_c2, name_a, 'log.txt'), 'a');
    fprintf(fid, '%s C5 targets: training rows excluded 999 of 1800, selection rows excluded 0 of 1200, 0.1 s | elapsed_s 5.0\n', ...
            char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    fclose(fid);
    res_c2 = run_resume(ctx, root_c2, 4);
    results = add(results, 'c', sprintf('R10: a C5 count different from the interrupted log: %s, %s, %s at %s', res_c2.status, ...
                  res_c2.reason, res_c2.error_id, res_c2.trial_id), strcmp(res_c2.status, 'INTERRUPTED') && ...
                  strcmp(res_c2.reason, 'ERROR') && strcmp(res_c2.error_id, 'e5_campaign_run:c5Count') && ...
                  strcmp(res_c2.trial_id, 'C5_targets'));
catch ME
    err_lines{end+1} = sprintf('(c)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'c', 'part (c) completed without error', false);
end

% ---------------------------------------------------------------- (d) refusals
cases = {'A4 end of session 4', 'err', 4, 'e5_campaign_run:resumeStart'; ...
         'CEILING end of session 2', 'ceil', 2, 'e5_campaign_run:resumeStart'; ...
         'second resume of session 2 (R7)', 'second', 2, 'e5_campaign_run:resumeStart'; ...
         'HEAD different', 'err', 4, 'e5_campaign_run:resumeStart'; ...
         'spec SHA-256 of session 1 different', 'err', 4, 'e5_campaign_run:resumeStart'; ...
         'plan different', 'err', 4, 'e5_campaign_run:resumeStart'; ...
         'a record of session 1 changed', 'err', 4, 'e5_campaign_run:resumeStart'; ...
         'a selection of session 1 changed (R4)', 'err', 4, 'e5_campaign_run:resumeStart'; ...
         'resume of the SESSION_COMPLETE session 3', 's3', 3, 'e5_campaign_run:resumeStart'; ...
         'resume of session 3 when session 2 did not end (out of order)', 's1', 3, 'e5_campaign_run:resumeStart'; ...
         'the resume folder exists (R8)', 'err', 4, 'e5_session_paths:folder'; ...
         'normal launch of the started session 2 (R6)', 'cut', 2, 'e5_campaign_run:sessionStart'};
for c = 1:size(cases, 1)
    try
        root_d = fullfile(test_dir, sprintf('results_d%02d', c));
        ctx_d = ctx;
        switch cases{c, 2}
            case 'err'
                make_root(test_dir, sprintf('results_d%02d', c), snap_err, name_a);
            case 'cut'
                make_root(test_dir, sprintf('results_d%02d', c), snap_cut, name_a);
            case 's3'
                make_root(test_dir, sprintf('results_d%02d', c), fullfile(snap, 'after_s3'), name_a);
            case 's1'
                make_root(test_dir, sprintf('results_d%02d', c), fullfile(snap, 'after_s1'), name_a);
            case 'ceil'
                make_root(test_dir, sprintf('results_d%02d', c), fullfile(snap, 'after_s1'), name_a);
                set_cumulative(fullfile(root_d, name_a), 1, 47.9*3600);
                res_ceil = run_session(ctx, root_d, 2);
                if ~strcmp(res_ceil.reason, 'CEILING')
                    error('test_e5_P4d:ceiling', 'The crafted session 2 did not stop at the ceiling (%s).', res_ceil.reason);
                end
            case 'second'
                copyfile(fullfile(snap, 'root_a_after_resume'), root_d);
                delete(fullfile(root_d, name_b, 'meta_session2.mat'));
                delete(fullfile(root_d, name_b, 'meta_session2.txt'));
        end
        switch c
            case 1
                ms = load_ms(fullfile(root_d, name_a), 4);
                ms.reason = 'A4';
                delete(fullfile(root_d, name_a, 'meta_session4.mat'));
                save(fullfile(root_d, name_a, 'meta_session4.mat'), 'ms', '-v7');
            case 4
                ctx_d.head = repmat('0', 1, 40);
            case 5
                mm = load(fullfile(root_d, name_a, 'meta.mat'), 'meta');
                meta = mm.meta;
                meta.spec_sha = repmat('0', 1, 64);
                save(fullfile(root_d, name_a, 'meta.mat'), 'meta', '-v7');
            case 6
                ctx_d.plan = plan_d([1:7, 7]);
                ctx_d.plan(end).trial_id = 'C5_c01_s35002';
                ctx_d.plan(end).seed = 35002;
            case 7
                append_byte(fullfile(root_d, name_a, 'records', 'MLP_c01_s35001.mat'));
            case 8
                append_byte(fullfile(root_d, name_a, 'selection_MLP.mat'));
            case 11
                mkdir(fullfile(root_d, name_b));
        end
        before = root_digest(root_d);
        if strcmp(cases{c, 4}, 'e5_campaign_run:sessionStart')
            [ok_ref, msg_ref] = expect_error_msg(@() run_session(ctx_d, root_d, cases{c, 3}), cases{c, 4});
        else
            [ok_ref, msg_ref] = expect_error_msg(@() run_resume(ctx_d, root_d, cases{c, 3}), cases{c, 4});
        end
        results = add(results, 'd', sprintf('refusal (%s): %s, campaign folders unchanged; message: %s', cases{c, 1}, cases{c, 4}, ...
                      short_text(msg_ref)), ok_ref && isequal(before, root_digest(root_d)));
    catch ME
        err_lines{end+1} = sprintf('(d%02d)\n%s', c, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'd', sprintf('refusal case %d completed without error', c), false);
    end
end

% ---------------------------------------------------------------- (e) cumulative ceiling in a resume
try
    root_e = make_root(test_dir, 'results_e', fullfile(snap, 'after_s1'), name_a);
    set_cumulative(fullfile(root_e, name_a), 1, 47.9*3600);
    res_e = run_resume(ctx, root_e, 2);
    ms2e = load_ms(fullfile(root_e, name_b), 2);
    results = add(results, 'e', sprintf(['S5, R5: meta_session1 cumulative 47.9 h, resume of session 2: %s, %s at %s, ' ...
                  'meta_session2 of -b %s %s'], res_e.status, res_e.reason, res_e.trial_id, ms2e.status, ms2e.reason), ...
                  strcmp(res_e.status, 'INTERRUPTED') && strcmp(res_e.reason, 'CEILING') && strcmp(res_e.trial_id, 'C2_c01_s35001') && ...
                  res_e.n_run == 0 && strcmp(ms2e.reason, 'CEILING') && isfile(fullfile(root_e, name_b, 'stop.txt')));
    before = root_digest(root_e);
    [ok_ref, msg_ref] = expect_error_msg(@() run_resume(ctx, root_e, 2), 'e5_campaign_run:resumeStart');
    results = add(results, 'e', sprintf('R1, R7: the resume stopped at the ceiling is not resumed again, folders unchanged; message: %s', ...
                  short_text(msg_ref)), ok_ref && isequal(before, root_digest(root_e)));
catch ME
    err_lines{end+1} = sprintf('(e)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'e', 'part (e) completed without error', false);
end

% ---------------------------------------------------------------- (f) truncated last line of trials.csv (R9)
try
    root_f = make_root(test_dir, 'results_f', snap_cut, name_a);
    csv_f = fullfile(root_f, name_a, 'trials.csv');
    txt_f = fileread(csv_f);
    csv_l = read_lines(csv_f);
    cut_txt = txt_f(1:numel(txt_f) - ceil(numel(csv_l{end})/2) - 1);           % last line cut in its middle, no final LF
    fid = fopen(csv_f, 'w');
    fwrite(fid, cut_txt);
    fclose(fid);
    res_f = run_resume(ctx, root_f, 2);
    log_f = fileread(fullfile(root_f, name_b, 'log.txt'));
    mf = load(fullfile(root_f, name_b, 'meta.mat'), 'meta');
    results = add(results, 'f', sprintf('R9: truncated last line (C2_c01_s35001) dropped and run again: %s, %d reused, %d run', ...
                  res_f.status, res_f.n_reused, res_f.n_run), strcmp(res_f.status, 'SESSION_COMPLETE') && res_f.n_reused == 2 && ...
                  res_f.n_run == 2 && mf.meta.n_dropped == 1 && contains(log_f, 'truncated last line of trials.csv'));
    root_f2 = make_root(test_dir, 'results_f2', snap_cut, name_a);
    csv_f2 = fullfile(root_f2, name_a, 'trials.csv');
    csv_l = read_lines(csv_f2);
    csv_l{2} = csv_l{2}(1:ceil(numel(csv_l{2})/2));
    write_lines(csv_f2, csv_l);
    before = root_digest(root_f2);
    [ok_ref, msg_ref] = expect_error_msg(@() run_resume(ctx, root_f2, 2), 'e5_campaign_run:resumeStart');
    results = add(results, 'f', sprintf('R9: a malformed line that is not the last refuses the resume, folders unchanged; message: %s', ...
                  short_text(msg_ref)), ok_ref && isequal(before, root_digest(root_f2)));
catch ME
    err_lines{end+1} = sprintf('(f)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'f', 'part (f) completed without error', false);
end

% ---------------------------------------------------------------- (g) e5_campaign in the mode resume, refused before any folder
threads_before = maxNumCompThreads;
try
    res_dir = fullfile(repo_root, 'results');
    listing = dir(res_dir);
    list_before = sort({listing.name});
    refused = expect_error(@() e5_campaign(repmat('0', 1, 40), 'resume', 2), 'e5_campaign:prereq') && ...
              expect_error(@() e5_campaign(repmat('0', 1, 40), 'resume', 7), 'e5_campaign:mode');
    maxNumCompThreads(threads_before);
    listing = dir(res_dir);
    list_after = sort({listing.name});
    results = add(results, 'g', sprintf(['e5_campaign(wrong head, resume 2) raises e5_campaign:prereq, resume 7 e5_campaign:mode; ' ...
                  'listing of results/ unchanged (%d entries); maxNumCompThreads restored to %d'], numel(list_after), threads_before), ...
                  refused && isequal(list_before, list_after) && maxNumCompThreads == threads_before);
catch ME
    maxNumCompThreads(threads_before);
    err_lines{end+1} = sprintf('(g)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'g', 'part (g) completed without error', false);
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
lines{end+1} = ['TEST E5 P4d RESUME OF A SESSION: ' verdict];
write_lines(fullfile(test_dir, 'verdict_test_e5_P4d.txt'), lines);
if isempty(err_lines)
    write_lines(fullfile(test_dir, 'errors.txt'), {'errors caught by test_e5_P4d: 0'});
else
    write_lines(fullfile(test_dir, 'errors.txt'), err_lines);
end
save(fullfile(test_dir, 'results.mat'), 'results', 'lines');
fprintf('%s\n', lines{end-1:end});
end

% ================================================================ helpers
function [res, P] = run_session(ctx, res_root, k)
% one session as launch_E5_session runs it (folder and chain of e5_session_paths, console log)
P = e5_session_paths(res_root, k);
ctx.mode = 'session';
ctx.dir = P.dir;
ctx.chain = P.chain;
ctx.prev_dir = '';
[res, P] = run_logged(ctx, k, P);
end

function [res, P] = run_resume(ctx, res_root, k)
% one resume as launch_E5_resume runs it (new folder of the chain, console log)
P = e5_session_paths(res_root, k, 'resume');
ctx.mode = 'resume';
ctx.dir = P.dir;
ctx.chain = P.chain;
ctx.prev_dir = P.prev_dir;
[res, P] = run_logged(ctx, k, P);
end

function [res, P] = run_logged(ctx, k, P)
% e5_campaign_run with the console log of S3; the diary of the caller, if any, is restored
if isfile(P.console)
    error('test_e5_P4d:console', 'The console log already exists: %s', P.console);
end
outer_file = get(0, 'DiaryFile');
outer_on = strcmp(get(0, 'Diary'), 'on');
diary(P.console);
try
    fprintf('test_e5_P4d: %s of session %d, folder %s\n', ctx.mode, k, P.dir);
    ctx.session = k;
    ctx.t0 = tic;
    res = e5_campaign_run(ctx);
catch ME
    fprintf('test_e5_P4d: %s of session %d raised %s\n%s\n', ctx.mode, k, ME.identifier, getReport(ME, 'extended', 'hyperlinks', 'off'));
    diary('off');
    restore_diary(outer_file, outer_on);
    rethrow(ME);
end
diary('off');
restore_diary(outer_file, outer_on);
end

function restore_diary(outer_file, outer_on)
if outer_on
    diary(outer_file);
end
end

function root = make_root(test_dir, name, src_folder, camp_name)
% a synthetic results folder holding a copy of a campaign folder
root = fullfile(test_dir, name);
mkdir(root);
copyfile(src_folder, fullfile(root, camp_name));
end

function ms = load_ms(folder, k)
loaded = load(fullfile(folder, sprintf('meta_session%d.mat', k)), 'ms');
ms = loaded.ms;
end

function set_cumulative(folder, k, elapsed_s)
% meta_session<k> with the given elapsed time of the session (and its cumulative time)
ms = load_ms(folder, k);
ms.elapsed_session_s = elapsed_s;
ms.elapsed_cumulative_s = ms.elapsed_prior_s + elapsed_s;
delete(fullfile(folder, sprintf('meta_session%d.mat', k)));
save(fullfile(folder, sprintf('meta_session%d.mat', k)), 'ms', '-v7');
end

function append_byte(file_path)
fid = fopen(file_path, 'a');
fwrite(fid, uint8(0));
fclose(fid);
end

function D = folder_digest(folder)
% relative path and SHA-256 of every file of a folder, sorted
listing = dir(fullfile(folder, '**', '*'));
listing = listing(~[listing.isdir]);
D = cell(numel(listing), 2);
for i = 1:numel(listing)
    full_path = fullfile(listing(i).folder, listing(i).name);
    D{i, 1} = strrep(full_path(numel(folder) + 2:end), '\', '/');
    D{i, 2} = e5_sha256(full_path);
end
D = sortrows(D, 1);
end

function D = root_digest(root)
% digest of every campaign folder of a results folder (console logs excluded)
listing = dir(fullfile(root, 'Q1-E5-TRAIN-*'));
listing = listing([listing.isdir]);
D = cell(0, 2);
for i = 1:numel(listing)
    d_i = folder_digest(fullfile(root, listing(i).name));
    d_i(:, 1) = strcat(listing(i).name, '/', d_i(:, 1));
    D = [D; d_i]; %#ok<AGROW>
end
end

function L = read_lines(file_path)
L = splitlines(strtrim(fileread(file_path)));
end

function L = strip_date(L)
L = regexprep(L, '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} ', '');
end

function e = entry(fam, cfg_index, seed, cfg)
e = struct('trial_id', sprintf('%s_c%02d_s%d', fam, cfg_index, seed), 'family', fam, 'cfg_index', cfg_index, ...
           'seed', seed, 'cfg', cfg);
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

function [ok, msg] = expect_error_msg(fn, identifier)
ok = false;
msg = 'no error';
try
    fn();
catch ME
    ok = strcmp(ME.identifier, identifier);
    msg = sprintf('%s: %s', ME.identifier, ME.message);
end
end

function s = short_text(text)
s = regexprep(text, '\s+', ' ');
if numel(s) > 220
    s = [s(1:220) '...'];
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
