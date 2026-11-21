function [fails, info] = e5_resume_check(chain, k, plan, head, C, new_dir)
%E5_RESUME_CHECK  Start checks and inputs of the resume of session k (spec_E5 amendment 6, R1, R3,
%R4, R5, R7, R8, R9, R10). Read only: nothing is written; the caller refuses the resume if fails is
%not empty.
%
%   [fails, info] = e5_resume_check(chain, k, plan, head, C, new_dir)
%
%   chain      cell of the campaign folders, oldest first (e5_session_paths P.chain); the last
%              folder F holds the interrupted session k
%   k          session number 1 to 5; plan, head: of the launch; C: e5_campaign_settings()
%   new_dir    the resume folder (e5_session_paths P.dir), which must not exist (R8)
%   fails      cell of messages, empty when the resume may start:
%              e5_session_check(chain, k, ..., 'resume') (S2, S4 for the sessions 1 to k - 1, no
%              session after k, R4 selections, R9 lenient last line);
%              R7  no folder of the chain is already a resume of session k;
%              R1  session k ended in F with ERROR (meta_session<k> INTERRUPTED, reason ERROR, or no
%                  meta_session<k> and stop.txt with reason ERROR), or without meta_session<k> and
%                  without stop.txt; A4, CEILING, SESSION_COMPLETE and COMPLETE are refused
%   info       case ('ERROR' or 'NO_META'), prev_dir (F), elapsed_interrupted_s (R5: elapsed_session_s
%              of meta_session<k>, or the last elapsed_s of the lines of session k in log.txt plus the
%              scaled time of a trial started and not in trials.csv, or 0 without such lines),
%              elapsed_prior_s (S5 prior + elapsed_interrupted_s), rows (lines of trials.csv of F to
%              reuse: every line of an earlier family, and the lines of the families of session k
%              that verify, are COMPLETE or NO_FINITE_LOSS and do not trigger e5_stop_rule, R3),
%              not_reused (messages), selections (family, file, sha, csv_line of the earlier
%              families, from their meta_session, R4), c5_counts ([] or the four exclusion counts of
%              the C5 targets in the lines of session k, R10), n_dropped (R9), log_truncated (R9)

if ischar(chain)
    chain = {chain};
end
SS = e5_sessions();
info = struct('case', '', 'prev_dir', chain{end}, 'elapsed_interrupted_s', 0, 'elapsed_prior_s', 0, 'rows', struct([]), ...
              'not_reused', {{}}, 'selections', struct('family', {}, 'file', {}, 'sha', {}, 'csv_line', {}), ...
              'c5_counts', [], 'n_dropped', 0, 'log_truncated', false);
[fails, prior] = e5_session_check(chain, k, plan, head, C.spec_sha, 'resume');
info.n_dropped = prior.n_dropped;
F = chain{end};
if isfolder(new_dir)
    fails{end+1} = sprintf('the resume folder %s exists (R8)', new_dir);
end
% ---------------------------------------------------------------- R7: one resume per session
for i = 2:numel(chain)
    mm = load(fullfile(chain{i}, 'meta.mat'), 'meta');
    if isfield(mm.meta, 'resume_session') && isequal(mm.meta.resume_session, k)
        fails{end+1} = sprintf('session %d was already resumed in %s; a second interruption ends the campaign (R7)', k, chain{i}); %#ok<AGROW>
    end
end
% ---------------------------------------------------------------- R1: case of the end of session k in F
ms_file = fullfile(F, sprintf('meta_session%d.mat', k));
stop_file = fullfile(F, 'stop.txt');
if isfile(ms_file)
    loaded = load(ms_file, 'ms');
    ms = loaded.ms;
    if strcmp(ms.status, 'INTERRUPTED') && strcmp(ms.reason, 'ERROR')
        info.case = 'ERROR';
        info.elapsed_interrupted_s = ms.elapsed_session_s;     % S5
    else
        fails{end+1} = sprintf('session %d ended with %s %s: not resumed (R1: only ERROR or no meta_session)', k, ms.status, ms.reason);
    end
else
    reason = '';
    if isfile(stop_file)
        stop_lines = splitlines(fileread(stop_file));
        reason_lines = stop_lines(startsWith(stop_lines, 'reason '));
        if ~isempty(reason_lines)
            reason = strtrim(extractAfter(reason_lines{end}, 'reason '));
        end
    end
    if isempty(reason)
        info.case = 'NO_META';
    elseif strcmp(reason, 'ERROR')
        info.case = 'ERROR';
    else
        fails{end+1} = sprintf('session %d stopped with reason %s: not resumed (R1)', k, reason);
    end
end
% ---------------------------------------------------------------- R5, R9, R10: lines of session k in log.txt
block = {};
log_file = fullfile(F, 'log.txt');
if isfile(log_file)
    log_text = fileread(log_file);
    log_lines = splitlines(log_text);
    if ~isempty(log_lines) && isempty(log_lines{end})
        log_lines(end) = [];                     % text ends with LF: last element empty
    elseif ~isempty(log_lines)
        log_lines(end) = [];                     % R9: last line without LF (truncated) ignored
        info.log_truncated = true;
    end
    i_start = find(~cellfun(@isempty, regexp(log_lines, sprintf('^\\S+ \\S+ session %d start:', k), 'once')), 1, 'last');
    if ~isempty(i_start)
        block = log_lines(i_start:end);
    end
end
if ~isempty(block)
    c5_tok = regexp(block, 'C5 targets: training rows excluded (\d+) of (\d+), selection rows excluded (\d+) of (\d+)', 'tokens', 'once');
    c5_tok = c5_tok(~cellfun(@isempty, c5_tok));
    if ~isempty(c5_tok)
        info.c5_counts = str2double(c5_tok{end});
    end
end
if strcmp(info.case, 'NO_META') || (strcmp(info.case, 'ERROR') && ~isfile(ms_file))
    info.elapsed_interrupted_s = 0;              % R5: no line of session k
    if ~isempty(block)
        el_tok = regexp(block, '\| elapsed_s (\d+(?:\.\d+)?)$', 'tokens', 'once');
        el_tok = el_tok(~cellfun(@isempty, el_tok));
        if ~isempty(el_tok)
            info.elapsed_interrupted_s = str2double(el_tok{end}{1});
        end
        ts_tok = regexp(block, '^\S+ \S+ trial start (\S+) ', 'tokens', 'once');
        ts_tok = ts_tok(~cellfun(@isempty, ts_tok));
        if ~isempty(ts_tok)
            id_started = ts_tok{end}{1};
            done_ids = {};
            if ~isempty(prior.rows)
                done_ids = {prior.rows.trial_id};
            end
            idx = find(strcmp({plan.trial_id}, id_started), 1);
            if ~any(strcmp(done_ids, id_started)) && ~isempty(idx)
                T = e5_scaled_time(C, plan(idx).family, plan(idx).cfg_index);
                info.elapsed_interrupted_s = info.elapsed_interrupted_s + T.total;   % R5: trial started, not recorded
            end
        end
    end
end
info.elapsed_prior_s = prior.elapsed_s + info.elapsed_interrupted_s;
% ---------------------------------------------------------------- R3: lines to reuse
fams_k = SS(k).families;
earlier = [SS(1:k-1).families];
rows = prior.rows;
keep = false(1, numel(rows));
seen = {};
for i = 1:numel(rows)
    row = rows(i);
    if any(strcmp(row.trial_id, seen))
        info.not_reused{end+1} = sprintf('%s: repeated line', row.trial_id);
        continue
    end
    if any(strcmp(row.family, earlier))
        keep(i) = true;                          % verified by e5_session_check
    elseif any(strcmp(row.family, fams_k))
        if ~any(strcmp(row.status, {'COMPLETE', 'NO_FINITE_LOSS'})) || ~e5_records('verify', F, row)
            info.not_reused{end+1} = sprintf('%s: not complete or SHA-256 changed, run again', row.trial_id);
            continue
        end
        loaded = load(fullfile(F, row.record_file), 'rec');
        if strcmp(e5_stop_rule(loaded.rec), 'A4')
            info.not_reused{end+1} = sprintf('%s: A4 stop rule, run again (K2)', row.trial_id);
            continue
        end
        keep(i) = true;
    end
    if keep(i)
        seen{end+1} = row.trial_id; %#ok<AGROW>
    end
end
info.rows = rows(keep);
% ---------------------------------------------------------------- R4: selections of the earlier families
for j = 1:k-1
    ms = struct([]);
    for i = numel(chain):-1:1
        f_ms = fullfile(chain{i}, sprintf('meta_session%d.mat', j));
        if isfile(f_ms)
            loaded = load(f_ms, 'ms');
            ms = loaded.ms;
            break
        end
    end
    if isempty(ms) || ~isfield(ms, 'selections')
        continue                                 % already a failure of e5_session_check
    end
    for f = 1:numel(ms.selections)
        info.selections(end+1) = struct('family', ms.selections(f).family, 'file', ms.selections(f).file, ...
                                        'sha', ms.selections(f).sha, 'csv_line', ms.selections(f).csv_line);
    end
end
end
