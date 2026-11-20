function verdict = test_e5_P4c(out_dir)
%TEST_E5_P4C  Test of package P4c of E5 (campaign in sessions, spec_E5 amendment 5, S8), written
%before any run, on synthetic data only (e5_synthetic_runs); no E4 file is read; the Cp table of the
%repository is read for C5. The settings of e5_campaign_settings are used unchanged.
%
%   verdict = test_e5_P4c(out_dir)
%
%   out_dir: existing folder under results/work_Q1. Writes only in out_dir/test_e5_P4c_<stamp>/
%   (synthetic results folders with their campaign folders and console logs), results.mat,
%   errors.txt, verdict_test_e5_P4c.txt. verdict 'PASS' if every check passes.
%   (a) e5_sessions (S1): five sessions, the families of D12 in order, planned times recomputed
%       from e5_scaled_time on the plan of 136 trials.
%   (b) e5_session_paths (S3): name of session 1, refusals.
%   (c) a synthetic campaign of the five sessions, one trial per family (7 trials): sessions 1 to 4
%       SESSION_COMPLETE, session 5 COMPLETE (S6); meta_session<k> and console log of each session
%       (S3); files of earlier sessions never rewritten, trials.csv, selection.csv and log.txt only
%       appended to (S3); cumulative elapsed time (S5); every record verified.
%   (d) refusals of the start of a session, each leaving the campaign folder unchanged (S2, S4):
%       previous session not SESSION_COMPLETE; a record file changed; a trial of an earlier session
%       missing; HEAD, spec SHA-256 or plan different; sessions out of order; a session run twice;
%       a second session 1.
%   (e) the cumulative ceiling of S5 reached in session 2 (CEILING, meta_session2 INTERRUPTED),
%       then session 3 refused.
%   (f) e5_campaign in the mode session with a wrong expected_head: e5_campaign:prereq before any
%       folder; the listing of results/ unchanged; maxNumCompThreads restored.
%   Every catch records getReport(ME, 'extended').

stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
test_dir = fullfile(out_dir, ['test_e5_P4c_' stamp]);
if exist(test_dir, 'dir')
    error('test_e5_P4c:exists', 'Output folder already exists: %s', test_dir);
end
mkdir(test_dir);
repo_root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
addpath(fullfile(repo_root, 'openfast_q1', 'E2'));
lines = {sprintf('test_e5_P4c start %s, repository %s, canUseGPU %d', stamp, repo_root, canUseGPU)};
err_lines = {};
results = struct('part', {}, 'check', {}, 'pass', {});
C = e5_campaign_settings();
SS = e5_sessions();

% ---------------------------------------------------------------- (a) S1
try
    plan_full = e5_campaign_plan(C);
    ok_fam = isequal([SS.families], C.families) && isequal([SS.session], 1:5);
    tot = zeros(1, 5);
    raw = zeros(1, 5);
    for i = 1:numel(plan_full)
        T = e5_scaled_time(C, plan_full(i).family, plan_full(i).cfg_index);
        k = find(cellfun(@(f) any(strcmp(plan_full(i).family, f)), {SS.families}));
        tot(k) = tot(k) + T.total;
        raw(k) = raw(k) + T.train_raw + T.eval_raw;
    end
    results = add(results, 'a', sprintf(['S1: five sessions {MLP C1} {C2} {C3} {C4 C5} {C6} in the order of D12; planned scaled ' ...
                  'time recomputed %s h (S1 %s h), raw %s h (S1 %s h), within 0.01 h; total %.1f s'], mat2str(round(tot/3600, 3)), ...
                  mat2str([SS.planned_h]), mat2str(round(raw/3600, 3)), mat2str([SS.raw_h]), sum(tot)), ...
                  ok_fam && numel(plan_full) == 136 && all(abs(tot/3600 - [SS.planned_h]) <= 0.01) && ...
                  all(abs(raw/3600 - [SS.raw_h]) <= 0.01) && abs(sum(tot) - 146345.4) < 1e-6);
catch ME
    err_lines{end+1} = sprintf('(a)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'a', 'part (a) completed without error', false);
end

% ---------------------------------------------------------------- (b) e5_session_paths
try
    root_b = fullfile(test_dir, 'results_b');
    mkdir(root_b);
    P1 = e5_session_paths(root_b, 1);
    ok_name = strcmp(P1.name, sprintf('Q1-E5-TRAIN-%s-a', char(datetime('now', 'Format', 'yyyy-MM-dd')))) && ...
              strcmp(P1.console, fullfile(root_b, [P1.name '_console_s1.txt'])) && ~isfolder(P1.dir);
    ref_none = expect_error(@() e5_session_paths(root_b, 2), 'e5_session_paths:folder');
    ref_k = expect_error(@() e5_session_paths(root_b, 6), 'e5_session_paths:session') && ...
            expect_error(@() e5_session_paths(root_b, 0), 'e5_session_paths:session');
    mkdir(fullfile(root_b, 'Q1-E5-TRAIN-2000-01-01-a'));
    ref_exists = expect_error(@() e5_session_paths(root_b, 1), 'e5_session_paths:exists');
    ref_nos1 = expect_error(@() e5_session_paths(root_b, 2), 'e5_session_paths:folder');
    results = add(results, 'b', ['S3: e5_session_paths: name and console log of session 1; session 1 refused when a campaign folder ' ...
                  'exists; session k >= 2 refused without exactly one folder holding meta_session1.mat; k outside 1 to 5 refused'], ...
                  ok_name && ref_none && ref_k && ref_exists && ref_nos1);
catch ME
    err_lines{end+1} = sprintf('(b)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'b', 'part (b) completed without error', false);
end

% ---------------------------------------------------------------- synthetic context
S = e5_settings();
S.n_rows_run = 600;
p = rom_params(fullfile(repo_root, strrep(S.cp_table_rel, '/', filesep)));
p.cp_mode = 'nmpc';
nrm = struct('mu', [1.263110277; 122.5211024; 13.37803117; 17.65675016], ...
             'sd', [0.05276818504; 4.964281324; 6.938685982; 4.395360763], ...
             'mux', [4.508361182e-07; 4.654321233e-05], 'sdx', [0.001625369198; 0.1024837435], ...
             'sha', 'synthetic normalisation of test_e5_P4c');
runs = [e5_synthetic_runs(3, 600, 7101, S, 'training'), e5_synthetic_runs(3, 600, 7102, S, 'validation')];
part = struct('train_filtered', logical([1 1 1 0 0 0])', 'selection', logical([0 0 0 1 1 0])', 'validation', logical([0 0 0 1 1 1])');
[~, head_out] = system(sprintf('git -C "%s" rev-parse HEAD', repo_root));
nn_cfg = struct('n_hidden', 1, 'n_units', 16, 'lr', 1e-3);
plan_s = [entry('MLP', 1, 35001, nn_cfg), entry('C1', 1, 35001, struct('L', 4, 'n_hidden', 1, 'n_units', 16, 'lr', 1e-3)), ...
          entry('C2', 1, 35001, struct('L', 4, 'kernel', 2, 'channels', 16, 'lr', 1e-3)), ...
          entry('C3', 1, 35001, struct('L', 4, 'hidden', 16, 'n_layers', 1, 'lr', 1e-3)), ...
          entry('C4', 1, 0, struct('sched', 'du', 'L', 1)), entry('C5', 1, 35001, nn_cfg), ...
          entry('C6', 1, 35001, struct('n_sub', 300, 'n_act', 40))];
ctx = struct('dir', '', 'mode', 'session', 'session', 1, 'prev_dir', '', 'runs', {runs}, 'part', part, 'nrm', nrm, 'p', p, ...
             'S', S, 'C', C, 'plan', {plan_s}, 'head', strtrim(head_out), ...
             'facts', struct('note', 'test_e5_P4c, synthetic data'), 'data_info', struct('note', 'e5_synthetic_runs 7101, 7102'), 't0', tic);
root_c = fullfile(test_dir, 'results_c');
mkdir(root_c);
snap_dir = fullfile(test_dir, 'snapshots');
mkdir(snap_dir);
camp_name = '';

% ---------------------------------------------------------------- (c) five sessions
try
    res_s = cell(1, 5);
    for k = 1:5
        [res_s{k}, Pk] = run_session(ctx, root_c, k);
        camp_name = Pk.name;
        copyfile(Pk.dir, fullfile(snap_dir, sprintf('after_s%d', k)));
    end
    camp_dir = fullfile(root_c, camp_name);
    st = cellfun(@(r) r.status, res_s, 'UniformOutput', false);
    n_run = cellfun(@(r) r.n_run, res_s);
    results = add(results, 'c', sprintf('S6: five sessions: %s; trials run per session %s', strjoin(st, ' '), mat2str(n_run)), ...
                  isequal(st, {'SESSION_COMPLETE', 'SESSION_COMPLETE', 'SESSION_COMPLETE', 'SESSION_COMPLETE', 'COMPLETE'}) && ...
                  isequal(n_run, [2 1 1 2 1]) && all(cellfun(@(r) isempty(r.reason), res_s)));
    rows = e5_records('read', camp_dir);
    ver_ok = all(arrayfun(@(r) e5_records('verify', camp_dir, r), rows));
    sel_lines = splitlines(strtrim(fileread(fullfile(camp_dir, 'selection.csv'))));
    sel_fams = cellfun(@(s) strtok(s, ';'), sel_lines(2:end), 'UniformOutput', false);
    results = add(results, 'c', sprintf(['S3: one folder %s; trials.csv %d lines in the plan order, every record verified; ' ...
                  'selection.csv %s; no stop.txt'], camp_name, numel(rows), strjoin(sel_fams', ' ')), ...
                  isequal({rows.trial_id}, {plan_s.trial_id}) && ver_ok && isequal(sel_fams', C.families) && ...
                  ~isfile(fullfile(camp_dir, 'stop.txt')) && isscalar(dir(fullfile(root_c, 'Q1-E5-TRAIN-*-a'))));
    ms_ok = true;
    cum_ok = true;
    prior_sum = 0;
    for k = 1:5
        ms = load(fullfile(camp_dir, sprintf('meta_session%d.mat', k)), 'ms');
        ms = ms.ms;
        ms_txt = fileread(fullfile(camp_dir, sprintf('meta_session%d.txt', k)));
        console = fileread(fullfile(root_c, sprintf('%s_console_s%d.txt', camp_name, k)));
        ms_ok = ms_ok && ms.session == k && isequal(ms.families, SS(k).families) && strcmp(ms.status, st{k}) && ...
                strcmp(ms.head, ctx.head) && strcmp(ms.spec_sha, C.spec_sha) && ms.threads >= 1 && ~isempty(ms.start) && ...
                ~isempty(ms.end) && contains(ms_txt, sprintf('session %d', k)) && contains(ms_txt, ['status ' st{k}]) && ...
                contains(ms_txt, ['spec_sha ' C.spec_sha]) && contains(console, sprintf('session %d start', k));
        cum_ok = cum_ok && abs(ms.elapsed_prior_s - prior_sum) < 1e-9 && ...
                 abs(ms.elapsed_cumulative_s - (prior_sum + ms.elapsed_session_s)) < 1e-9 && ...
                 abs(res_s{k}.elapsed_s - ms.elapsed_cumulative_s) < 5;
        prior_sum = prior_sum + ms.elapsed_session_s;
    end
    results = add(results, 'c', ['S3: meta_session1 to 5 (.mat and .txt: session, families, start, end, elapsed, status, threads, ' ...
                  'GPU, HEAD, spec SHA-256) and the console log of each session'], ms_ok);
    results = add(results, 'c', sprintf('S5: cumulative elapsed time: each session adds its elapsed time to the earlier ones (total %.1f s)', ...
                  prior_sum), cum_ok);
    keep_ok = true;
    for k = 1:4
        before = folder_digest(fullfile(snap_dir, sprintf('after_s%d', k)));
        after = folder_digest(camp_dir);
        for j = 1:size(before, 1)
            rel = before{j, 1};
            if any(strcmp(rel, {'trials.csv', 'selection.csv', 'log.txt'}))
                txt_before = fileread(fullfile(snap_dir, sprintf('after_s%d', k), rel));
                keep_ok = keep_ok && startsWith(fileread(fullfile(camp_dir, rel)), txt_before);
            else
                j_after = find(strcmp(after(:, 1), rel), 1);
                keep_ok = keep_ok && ~isempty(j_after) && strcmp(after{j_after, 2}, before{j, 2});
            end
        end
    end
    results = add(results, 'c', ['S3: no file written by an earlier session is rewritten; trials.csv, selection.csv and log.txt ' ...
                  'only appended to (checked after each of the sessions 1 to 4)'], keep_ok);
    log_c = fileread(fullfile(camp_dir, 'log.txt'));
    results = add(results, 'c', 'S6: log.txt holds SESSION_COMPLETE for the sessions 1 to 4 and COMPLETE for session 5', ...
                  all(arrayfun(@(k) contains(log_c, sprintf('session %d SESSION_COMPLETE', k)), 1:4)) && ...
                  contains(log_c, 'session 5 COMPLETE'));
catch ME
    err_lines{end+1} = sprintf('(c)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'c', 'part (c) completed without error', false);
end

% ---------------------------------------------------------------- (d) refusals of a start (S2, S4)
cases = {'previous session not SESSION_COMPLETE', 1, 2; 'a record file of session 1 changed', 1, 2; ...
         'a trial of session 1 missing in trials.csv', 1, 2; 'HEAD different', 1, 2; 'spec SHA-256 of session 1 different', 1, 2; ...
         'plan different', 1, 2; 'session 3 after session 1 (out of order)', 1, 3; 'session 2 run twice', 2, 2};
for c = 1:size(cases, 1)
    try
        root_d = fullfile(test_dir, sprintf('results_d%d', c));
        mkdir(root_d);
        if isempty(camp_name)
            error('test_e5_P4c:noCampaign', 'Part (c) gave no campaign folder.');
        end
        dir_d = fullfile(root_d, camp_name);
        copyfile(fullfile(snap_dir, sprintf('after_s%d', cases{c, 2})), dir_d);
        ctx_d = ctx;
        switch c
            case 1
                ms = load(fullfile(dir_d, 'meta_session1.mat'), 'ms');
                ms = ms.ms;
                ms.status = 'INTERRUPTED';
                delete(fullfile(dir_d, 'meta_session1.mat'));
                save(fullfile(dir_d, 'meta_session1.mat'), 'ms', '-v7');
            case 2
                fid = fopen(fullfile(dir_d, 'records', 'MLP_c01_s35001.mat'), 'a');
                fwrite(fid, uint8(0));
                fclose(fid);
            case 3
                csv_lines = splitlines(strtrim(fileread(fullfile(dir_d, 'trials.csv'))));
                write_lines(fullfile(dir_d, 'trials.csv'), csv_lines(1:end - 1));
            case 4
                ctx_d.head = repmat('0', 1, 40);
            case 5
                mm = load(fullfile(dir_d, 'meta.mat'), 'meta');
                meta = mm.meta;
                meta.spec_sha = repmat('0', 1, 64);
                save(fullfile(dir_d, 'meta.mat'), 'meta', '-v7');
            case 6
                ctx_d.plan = plan_s([1:6, 6]);
                ctx_d.plan(end).trial_id = 'C5_c01_s35002';
                ctx_d.plan(end).seed = 35002;
        end
        before = folder_digest(dir_d);
        [ok_ref, msg_ref] = expect_error_msg(@() run_session(ctx_d, root_d, cases{c, 3}), 'e5_campaign_run:sessionStart');
        after = folder_digest(dir_d);
        results = add(results, 'd', sprintf('S4 refusal (%s): e5_campaign_run:sessionStart, campaign folder unchanged; message: %s', ...
                      cases{c, 1}, short_text(msg_ref)), ok_ref && isequal(before, after));
    catch ME
        err_lines{end+1} = sprintf('(d%d)\n%s', c, getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
        results = add(results, 'd', sprintf('refusal case %d completed without error', c), false);
    end
end
try
    root_d = fullfile(test_dir, 'results_d9');
    mkdir(root_d);
    copyfile(fullfile(snap_dir, 'after_s1'), fullfile(root_d, camp_name));
    before = folder_digest(fullfile(root_d, camp_name));
    ok_ref = expect_error(@() run_session(ctx, root_d, 1), 'e5_session_paths:exists');
    results = add(results, 'd', 'S3: a second session 1 refused when the campaign folder exists (e5_session_paths:exists), folder unchanged', ...
                  ok_ref && isequal(before, folder_digest(fullfile(root_d, camp_name))));
catch ME
    err_lines{end+1} = sprintf('(d9)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'd', 'refusal case 9 completed without error', false);
end

% ---------------------------------------------------------------- (e) cumulative ceiling (S5)
try
    root_e = fullfile(test_dir, 'results_e');
    mkdir(root_e);
    dir_e = fullfile(root_e, camp_name);
    copyfile(fullfile(snap_dir, 'after_s1'), dir_e);
    ms = load(fullfile(dir_e, 'meta_session1.mat'), 'ms');
    ms = ms.ms;
    ms.elapsed_session_s = 47.9*3600;
    ms.elapsed_cumulative_s = ms.elapsed_prior_s + ms.elapsed_session_s;
    delete(fullfile(dir_e, 'meta_session1.mat'));
    save(fullfile(dir_e, 'meta_session1.mat'), 'ms', '-v7');
    res_e = run_session(ctx, root_e, 2);
    stop_e = fileread(fullfile(dir_e, 'stop.txt'));
    ms2 = load(fullfile(dir_e, 'meta_session2.mat'), 'ms');
    rows_e = e5_records('read', dir_e);
    results = add(results, 'e', sprintf(['S5: session 1 recorded with 47.9 h; session 2 stops before its first trial: %s, %s at %s; ' ...
                  'meta_session2 %s; cumulative %.1f s'], res_e.status, res_e.reason, res_e.trial_id, ms2.ms.status, res_e.elapsed_s), ...
                  strcmp(res_e.status, 'INTERRUPTED') && strcmp(res_e.reason, 'CEILING') && strcmp(res_e.trial_id, 'C2_c01_s35001') && ...
                  res_e.n_run == 0 && contains(stop_e, 'FAILED_KEPT') && strcmp(ms2.ms.status, 'INTERRUPTED') && ...
                  strcmp(ms2.ms.reason, 'CEILING') && res_e.elapsed_s >= 47.9*3600 && numel(rows_e) == 2);
    before = folder_digest(dir_e);
    [ok_ref, msg_ref] = expect_error_msg(@() run_session(ctx, root_e, 3), 'e5_campaign_run:sessionStart');
    results = add(results, 'e', sprintf('S6: after the interruption, session 3 refused, folder unchanged; message: %s', short_text(msg_ref)), ...
                  ok_ref && isequal(before, folder_digest(dir_e)));
catch ME
    err_lines{end+1} = sprintf('(e)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'e', 'part (e) completed without error', false);
end

% ---------------------------------------------------------------- (f) e5_campaign in the mode session, refused before any folder
threads_before = maxNumCompThreads;
try
    res_dir = fullfile(repo_root, 'results');
    listing = dir(res_dir);
    list_before = sort({listing.name});
    refused = expect_error(@() e5_campaign(repmat('0', 1, 40), 'session', 2), 'e5_campaign:prereq') && ...
              expect_error(@() e5_campaign(repmat('0', 1, 40), 'session', 1), 'e5_campaign:prereq') && ...
              expect_error(@() e5_campaign(repmat('0', 1, 40), 'session', 6), 'e5_campaign:mode');
    maxNumCompThreads(threads_before);
    listing = dir(res_dir);
    list_after = sort({listing.name});
    results = add(results, 'f', sprintf(['e5_campaign(wrong head, session 1 or 2) raises e5_campaign:prereq, session 6 e5_campaign:mode; ' ...
                  'listing of results/ unchanged (%d entries); maxNumCompThreads restored to %d'], numel(list_after), threads_before), ...
                  refused && isequal(list_before, list_after) && maxNumCompThreads == threads_before);
catch ME
    maxNumCompThreads(threads_before);
    err_lines{end+1} = sprintf('(f)\n%s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    results = add(results, 'f', 'part (f) completed without error', false);
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
lines{end+1} = ['TEST E5 P4c CAMPAIGN IN SESSIONS: ' verdict];
write_lines(fullfile(test_dir, 'verdict_test_e5_P4c.txt'), lines);
if isempty(err_lines)
    write_lines(fullfile(test_dir, 'errors.txt'), {'errors caught by test_e5_P4c: 0'});
else
    write_lines(fullfile(test_dir, 'errors.txt'), err_lines);
end
save(fullfile(test_dir, 'results.mat'), 'results', 'lines');
fprintf('%s\n', lines{end-1:end});
end

% ================================================================ helpers
function [res, P] = run_session(ctx, res_root, k)
% one session as the launch block runs it: folder of e5_session_paths, console log of S3 (the
% diary of the caller, if any, is restored afterwards), then e5_campaign_run
P = e5_session_paths(res_root, k);
if isfile(P.console)
    error('test_e5_P4c:console', 'The console log already exists: %s', P.console);
end
outer_file = get(0, 'DiaryFile');
outer_on = strcmp(get(0, 'Diary'), 'on');
diary(P.console);
try
    fprintf('test_e5_P4c: session %d, folder %s\n', k, P.dir);
    ctx.dir = P.dir;
    ctx.session = k;
    ctx.t0 = tic;
    res = e5_campaign_run(ctx);
catch ME
    fprintf('test_e5_P4c: session %d raised %s\n%s\n', k, ME.identifier, getReport(ME, 'extended', 'hyperlinks', 'off'));
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
