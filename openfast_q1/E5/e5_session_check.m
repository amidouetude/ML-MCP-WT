function [fails, prior] = e5_session_check(camp_dir, k, plan, head, spec_sha)
%E5_SESSION_CHECK  Start checks of session k >= 2 of the E5 campaign (spec_E5 amendment 5, S2, S3,
%S4, S5). Read only: nothing is written; the caller refuses the start if fails is not empty.
%
%   [fails, prior] = e5_session_check(camp_dir, k, plan, head, spec_sha)
%
%   camp_dir   the campaign folder written by session 1 (e5_session_paths)
%   k          session number, 2 to numel(e5_sessions())
%   plan       the plan of the current launch (e5_campaign_plan, or a synthetic plan in the test)
%   head       HEAD of the current launch; spec_sha: C.spec_sha of the current launch
%   fails      cell of messages, empty when every check holds:
%              S2  meta.mat of session 1 has the same head, spec SHA-256 and plan trial ids;
%              S4  sessions 1 to k - 1 have meta_session<j>.mat with the status SESSION_COMPLETE and
%                  the same head and spec SHA-256; every trial of their families has exactly one
%                  line in trials.csv; e5_records verify holds for every line; selection_<family>.mat
%                  and one line of selection.csv exist for every such family;
%              S3  no meta_session<j>.mat for j >= k (a session runs once, in order); no line of
%                  trials.csv for a family of session k or later; no stop.txt and no errors/*.txt
%                  (an interruption ends the campaign, S6)
%   prior      prior.elapsed_s: sum of elapsed_session_s of meta_session1 to meta_session<k-1>
%              (S5); prior.n_sessions = k - 1

SS = e5_sessions();
if ~(isnumeric(k) && isscalar(k) && any(k == 2:numel(SS)))
    error('e5_session_check:session', 'The start checks apply to the sessions 2 to %d.', numel(SS));
end
fails = {};
prior = struct('elapsed_s', 0, 'n_sessions', k - 1);
if ~isfolder(camp_dir) || ~isfile(fullfile(camp_dir, 'meta.mat'))
    fails{end+1} = sprintf('no campaign folder of session 1 with meta.mat (%s)', camp_dir);
    return
end
% ---------------------------------------------------------------- S2: same commit, spec and plan as session 1
mm = load(fullfile(camp_dir, 'meta.mat'), 'meta');
plan_ids = {plan.trial_id};
if ~strcmpi(mm.meta.head, head)
    fails{end+1} = sprintf('HEAD %s differs from the HEAD %s of session 1', head, mm.meta.head);
end
if ~strcmp(mm.meta.spec_sha, spec_sha)
    fails{end+1} = sprintf('spec SHA-256 %s differs from the spec SHA-256 %s of session 1', spec_sha, mm.meta.spec_sha);
end
if ~isequal(mm.meta.plan_ids, plan_ids)
    fails{end+1} = 'the plan (trial ids) differs from the plan of session 1';
end
% ---------------------------------------------------------------- S4, S3: earlier sessions, order
for j = 1:numel(SS)
    ms_file = fullfile(camp_dir, sprintf('meta_session%d.mat', j));
    if j < k
        if ~isfile(ms_file)
            fails{end+1} = sprintf('session %d has no meta_session%d.mat', j, j); %#ok<AGROW>
            continue
        end
        ms = load(ms_file, 'ms');
        if ~isequal(ms.ms.session, j) || ~strcmp(ms.ms.status, 'SESSION_COMPLETE')
            fails{end+1} = sprintf('session %d ended with the status %s, SESSION_COMPLETE required', j, ms.ms.status); %#ok<AGROW>
        end
        if ~strcmpi(ms.ms.head, head) || ~strcmp(ms.ms.spec_sha, spec_sha)
            fails{end+1} = sprintf('session %d ran with another HEAD or spec SHA-256', j); %#ok<AGROW>
        end
        prior.elapsed_s = prior.elapsed_s + ms.ms.elapsed_session_s;
    elseif isfile(ms_file)
        fails{end+1} = sprintf('meta_session%d.mat exists: session %d has already run', j, j); %#ok<AGROW>
    end
end
if isfile(fullfile(camp_dir, 'stop.txt'))
    fails{end+1} = 'stop.txt exists: the campaign was interrupted (S6)';
end
if ~isempty(dir(fullfile(camp_dir, 'errors', '*.txt')))
    fails{end+1} = 'errors/ holds an error record (S6)';
end
% ---------------------------------------------------------------- S4: lines, files, selections of the earlier families
earlier = [SS(1:k-1).families];
later = [SS(k:end).families];
try
    rows = e5_records('read', camp_dir);
catch ME
    fails{end+1} = sprintf('trials.csv cannot be read: %s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    return
end
row_ids = {};
if ~isempty(rows)
    row_ids = {rows.trial_id};
end
for i = 1:numel(plan)
    if any(strcmp(plan(i).family, earlier)) && nnz(strcmp(row_ids, plan(i).trial_id)) ~= 1
        fails{end+1} = sprintf('trial %s of an earlier session has %d lines in trials.csv, 1 required', plan(i).trial_id, ...
                               nnz(strcmp(row_ids, plan(i).trial_id))); %#ok<AGROW>
    end
end
for i = 1:numel(rows)
    row = rows(i);
    if any(strcmp(row.family, later))
        fails{end+1} = sprintf('trials.csv holds %s of a family of session %d or later', row.trial_id, k); %#ok<AGROW>
    elseif ~any(strcmp(row.trial_id, plan_ids))
        fails{end+1} = sprintf('trials.csv holds %s, not in the plan', row.trial_id); %#ok<AGROW>
    elseif ~any(strcmp(row.status, {'COMPLETE', 'NO_FINITE_LOSS'}))
        fails{end+1} = sprintf('trial %s has the status %s', row.trial_id, row.status); %#ok<AGROW>
    elseif ~e5_records('verify', camp_dir, row)
        fails{end+1} = sprintf('trial %s: a record or model file is missing or has another SHA-256', row.trial_id); %#ok<AGROW>
    end
end
sel_csv = fullfile(camp_dir, 'selection.csv');
sel_fams = {};
if isfile(sel_csv)
    sel_lines = splitlines(strtrim(fileread(sel_csv)));
    sel_fams = cellfun(@(s) strtok(s, ';'), sel_lines(2:end), 'UniformOutput', false);
end
for f = 1:numel(earlier)
    fam = earlier{f};
    if ~isfile(fullfile(camp_dir, ['selection_' fam '.mat'])) || nnz(strcmp(sel_fams, fam)) ~= 1
        fails{end+1} = sprintf('the selection of %s (selection_%s.mat and one line of selection.csv) is missing', fam, fam); %#ok<AGROW>
    end
end
end
