function [fails, prior] = e5_session_check(chain, k, plan, head, spec_sha, purpose)
%E5_SESSION_CHECK  Start checks of session k >= 2 of the E5 campaign (spec_E5 amendment 5, S2, S3,
%S4, S5), on the chain of folders of amendment 6 (R2, R4, R8). Read only: nothing is written; the
%caller refuses the start if fails is not empty.
%
%   [fails, prior] = e5_session_check(chain, k, plan, head, spec_sha)             start of session k
%   [fails, prior] = e5_session_check(chain, k, plan, head, spec_sha, 'resume')   part of the
%                                                                                 checks of a resume
%
%   chain      cell of the campaign folders, oldest first (e5_session_paths P.chain), or one folder;
%              the last folder F is the folder of the start (S3, S4 apply to it, R2)
%   k          session number: 2 to 5 for a start; 1 to 5 for a resume
%   plan       the plan of the current launch; head: HEAD of the launch; spec_sha: C.spec_sha
%   fails      cell of messages, empty when every check holds:
%              S2  meta.mat of every folder of the chain has the head, spec SHA-256 and plan trial
%                  ids of the launch (the -a folder: those of session 1);
%              S4  sessions 1 to k - 1 have a meta_session<j>.mat (the last one in the chain) with
%                  SESSION_COMPLETE and the same head and spec SHA-256; every trial of their
%                  families has exactly one line in trials.csv of F; e5_records verify holds for
%                  each of these lines; each of their families has selection_<family>.mat in F with
%                  the SHA-256 and the line of selection.csv recorded in meta_session<j> (R4);
%              S3  no meta_session<j>.mat in the chain for j >= k (start) or j > k (resume); no
%                  line in trials.csv of F for a family of session k or later (start) or later than
%                  k (resume); start only: no stop.txt and no errors/*.txt in F, and no line
%                  "session k start" in log.txt of F (a started session is resumed, R1, R6)
%   prior      prior.elapsed_s: elapsed_cumulative_s of the last meta_session<k-1> of the chain (S5;
%              0 for k = 1); prior.n_dropped: truncated last lines of trials.csv dropped (resume,
%              R9); prior.rows: the lines of trials.csv of F as read

if nargin < 6
    purpose = 'start';
end
if ischar(chain)
    chain = {chain};
end
SS = e5_sessions();
for_resume = strcmp(purpose, 'resume');
if ~(isnumeric(k) && isscalar(k) && any(k == (2 - for_resume):numel(SS)))
    error('e5_session_check:session', 'Session %d: the checks apply to the sessions 2 to %d (start) or 1 to %d (resume).', ...
          k, numel(SS), numel(SS));
end
fails = {};
prior = struct('elapsed_s', 0, 'n_dropped', 0, 'rows', struct([]));
F = chain{end};
if ~isfolder(F) || ~isfile(fullfile(F, 'meta.mat'))
    fails{end+1} = sprintf('no campaign folder with meta.mat (%s)', F);
    return
end
% ---------------------------------------------------------------- S2: same commit, spec and plan as session 1
plan_ids = {plan.trial_id};
for i = 1:numel(chain)
    mm = load(fullfile(chain{i}, 'meta.mat'), 'meta');
    if ~strcmpi(mm.meta.head, head)
        fails{end+1} = sprintf('HEAD %s differs from the HEAD %s of %s', head, mm.meta.head, folder_name(chain{i})); %#ok<AGROW>
    end
    if ~strcmp(mm.meta.spec_sha, spec_sha)
        fails{end+1} = sprintf('spec SHA-256 %s differs from the spec SHA-256 %s of %s', spec_sha, mm.meta.spec_sha, ...
                               folder_name(chain{i})); %#ok<AGROW>
    end
    if ~isequal(mm.meta.plan_ids, plan_ids)
        fails{end+1} = sprintf('the plan (trial ids) differs from the plan of %s', folder_name(chain{i})); %#ok<AGROW>
    end
end
% ---------------------------------------------------------------- S4, S3: earlier sessions, order
ms_prev = struct([]);
for j = 1:numel(SS)
    [ms, where_ms] = latest_meta_session(chain, j);
    if j < k
        if isempty(ms)
            fails{end+1} = sprintf('session %d has no meta_session%d.mat in the chain', j, j); %#ok<AGROW>
            continue
        end
        if ~isequal(ms.session, j) || ~strcmp(ms.status, 'SESSION_COMPLETE')
            fails{end+1} = sprintf('session %d ended with the status %s, SESSION_COMPLETE required', j, ms.status); %#ok<AGROW>
        end
        if ~strcmpi(ms.head, head) || ~strcmp(ms.spec_sha, spec_sha)
            fails{end+1} = sprintf('session %d ran with another HEAD or spec SHA-256', j); %#ok<AGROW>
        end
        if j == k - 1
            ms_prev = ms;
        end
    elseif ~isempty(ms) && (j > k || ~for_resume)
        fails{end+1} = sprintf('meta_session%d.mat exists in %s: session %d has already run', j, where_ms, j); %#ok<AGROW>
    end
end
if ~isempty(ms_prev)
    prior.elapsed_s = ms_prev.elapsed_cumulative_s;   % S5: cumulative time recorded by session k - 1
end
if ~for_resume
    if isfile(fullfile(F, 'stop.txt'))
        fails{end+1} = 'stop.txt exists: the campaign was interrupted (S6)';
    end
    if ~isempty(dir(fullfile(F, 'errors', '*.txt')))
        fails{end+1} = 'errors/ holds an error record (S6)';
    end
    if isfile(fullfile(F, 'log.txt'))
        log_lines = splitlines(fileread(fullfile(F, 'log.txt')));
        if any(~cellfun(@isempty, regexp(log_lines, sprintf('^\\S+ \\S+ session %d start:', k), 'once')))
            fails{end+1} = sprintf('log.txt holds the start of session %d: a started session is resumed (amendment 6, R1, R6)', k);
        end
    end
end
% ---------------------------------------------------------------- S4: lines, files, selections of the earlier families
earlier = [SS(1:k-1).families];
if for_resume
    later = [SS(k+1:end).families];
else
    later = [SS(k:end).families];
end
try
    if for_resume
        [rows, prior.n_dropped] = e5_records('read', F, 'lenient_last');
    else
        rows = e5_records('read', F);
    end
catch ME
    fails{end+1} = sprintf('trials.csv cannot be read: %s', getReport(ME, 'extended', 'hyperlinks', 'off'));
    return
end
prior.rows = rows;
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
        fails{end+1} = sprintf('trials.csv holds %s of a family of a later session', row.trial_id); %#ok<AGROW>
    elseif ~any(strcmp(row.trial_id, plan_ids))
        fails{end+1} = sprintf('trials.csv holds %s, not in the plan', row.trial_id); %#ok<AGROW>
    elseif any(strcmp(row.family, earlier))
        if ~any(strcmp(row.status, {'COMPLETE', 'NO_FINITE_LOSS'}))
            fails{end+1} = sprintf('trial %s has the status %s', row.trial_id, row.status); %#ok<AGROW>
        elseif ~e5_records('verify', F, row)
            fails{end+1} = sprintf('trial %s: a record or model file is missing or has another SHA-256', row.trial_id); %#ok<AGROW>
        end
    end
end
sel_csv = fullfile(F, 'selection.csv');
sel_lines = {};
if isfile(sel_csv)
    sel_lines = splitlines(strtrim(fileread(sel_csv)));
    sel_lines = sel_lines(2:end);
end
sel_fams = cellfun(@(s) strtok(s, ';'), sel_lines, 'UniformOutput', false);
for j = 1:k-1
    ms = latest_meta_session(chain, j);
    for f = 1:numel(SS(j).families)
        fam = SS(j).families{f};
        sel_file = fullfile(F, ['selection_' fam '.mat']);
        entry = struct([]);
        if ~isempty(ms) && isfield(ms, 'selections') && ~isempty(ms.selections)
            entry = ms.selections(strcmp({ms.selections.family}, fam));
        end
        if ~isfile(sel_file) || nnz(strcmp(sel_fams, fam)) ~= 1
            fails{end+1} = sprintf('the selection of %s (selection_%s.mat and one line of selection.csv) is missing', fam, fam); %#ok<AGROW>
        elseif ~isscalar(entry)
            fails{end+1} = sprintf('meta_session%d records no SHA-256 for the selection of %s (amendment 6, R4)', j, fam); %#ok<AGROW>
        elseif ~strcmp(e5_sha256(sel_file), entry.sha) || ~strcmp(sel_lines{strcmp(sel_fams, fam)}, entry.csv_line)
            fails{end+1} = sprintf('the selection of %s differs from meta_session%d (SHA-256 or line, R4)', fam, j); %#ok<AGROW>
        end
    end
end
end

% ================================================================ local functions
function [ms, where_ms] = latest_meta_session(chain, j)
% meta_session<j> of the last folder of the chain that holds one (a resume folder supersedes the
% interrupted one, R2)
ms = struct([]);
where_ms = '';
for i = numel(chain):-1:1
    ms_file = fullfile(chain{i}, sprintf('meta_session%d.mat', j));
    if isfile(ms_file)
        loaded = load(ms_file, 'ms');
        ms = loaded.ms;
        where_ms = folder_name(chain{i});
        return
    end
end
end

function name = folder_name(folder)
[~, name] = fileparts(folder);
end
