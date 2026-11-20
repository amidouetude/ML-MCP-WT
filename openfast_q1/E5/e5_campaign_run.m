function res = e5_campaign_run(ctx)
%E5_CAMPAIGN_RUN  Core of the E5 campaign driver (package P4b): the trials of a plan with the
%ceiling check, the records, the stops and the resume of a campaign -b (spec_E5 amendment 4 A3 to
%A6, A10, A11, A14 to A20; interruption, E5 l.154; framework_decisions.ceiling, l.38). Called by
%e5_campaign (E4 data) and by test_e5_P4b (synthetic data); every value of the campaign comes from
%ctx.C = e5_campaign_settings(), passed unchanged to the trainers.
%
%   res = e5_campaign_run(ctx)
%
%   ctx.dir        campaign folder, created here (refused if it exists); written: meta.mat and
%                  meta.txt (with the gpuDevice name and the threads, A7), trials.csv, models/,
%                  records/, errors/, selection_<family>.mat, selection.csv, stop.txt (on a stop),
%                  log.txt; no file outside ctx.dir
%   ctx.mode       'a' (new campaign), 'b' (resume of ctx.prev_dir) or 'session' (amendment 5)
%   ctx.session    session number 1 to 5 (mode 'session' only)
%   ctx.prev_dir   campaign -a folder for mode 'b' (else '')
%   ctx.runs, ctx.part (e5_partition masks: train_filtered, selection, validation), ctx.nrm,
%   ctx.p (rom_params, cp_mode nmpc), ctx.S (e5_settings), ctx.C, ctx.plan (e5_campaign_plan or a
%   plan of the same form), ctx.head, ctx.facts (A7 facts, recorded), ctx.data_info (recorded),
%   ctx.t0 (tic of the first line of the launch: the elapsed time of A3 and A5)
%   Version 3 (package P4c, spec_E5 amendment 5): the mode 'session' below; stop.txt appended.
%   Version 2 (supervisor review of 20/11/2026, K1 to K5): one try around everything after the
%   creation of ctx.dir (K1); a record that triggers e5_stop_rule is never reused (K2); the C5
%   targets when the loop reaches the first pending C5 trial (K3); the fields of l.150 in every
%   record (K4); the data cache cleared when the family changes (K5).
%   Order of a trial (A3, A5, A14, A15, A20): ceiling check with the elapsed time (for -b, plus the
%   time_total of the record file of every reused trial, reading P4b-3) and the scaled time of the trial;
%   training (e5_train_nn with C.train_opts, e5_train_c4 with C.c4_opts, e5_train_c6); evaluation on
%   the selection subset, wind cases (a) and (b), e5_metrics; criterion (e5_criterion); prediction
%   cost (e5_prediction_cost, A14); time flags (A5); model file, record and line of trials.csv
%   (e5_records, A15). Stops, each an interruption written in stop.txt (status FAILED_KEPT): the
%   ceiling (A3), an A4 FAIL of either comparison after its record is written (A4), any error raised
%   after the creation of ctx.dir (initialisation, meta, resume, C5 targets, a trial, its record, the
%   stop rule, a selection) with getReport(ME, 'extended') in errors/<where>.txt, where = init, meta,
%   resume, C5_targets, the trial id or selection_<family> (A20, K1). NO_FINITE_LOSS is not a stop
%   (A10): no model, every segment failed, criterion +Inf, cost NaN.
%   After the last trial of a family, if every trial of the family is complete: e5_select (A19) and,
%   for the retained model, the runs of ctx.part.validation not in the selection subset in both
%   wind cases and e5_plausibility on ctx.part.validation (A17), in selection_<family>.mat and a
%   line of selection.csv.
%   Mode 'b' (l.154): meta.mat of prev_dir must have the same head, spec SHA-256 and plan trial ids;
%   a line of the trials.csv of prev_dir is reused only if e5_records verify holds (SHA-256 of its
%   record and model files unchanged) and its record does not trigger e5_stop_rule (K2); its files
%   are copied to ctx.dir, checked again, and the line
%   appended with reused = 1; every other trial of the plan runs.
%   Mode 'session' (spec_E5 amendment 5, package P4c): ctx.session = k, 1 to 5, the families of
%   session k fixed by e5_sessions (S1); only the trials of these families run, in the plan order.
%   k = 1 creates ctx.dir as in mode 'a' (meta.mat, meta.txt, trials.csv written once). k >= 2:
%   before anything is written, e5_session_check (S2, S4) on ctx.dir, the folder of session 1; a
%   refusal raises e5_campaign_run:sessionStart and writes nothing; the elapsed time of A3 is the
%   sum of the elapsed times of the earlier sessions (their meta_session files) plus toc(ctx.t0)
%   (S5); files of earlier sessions are never rewritten, trials.csv, selection.csv, log.txt and
%   stop.txt only appended to (S3). At any end of session k: meta_session<k>.mat and .txt (S3,
%   S6), written once. Normal end: res.status SESSION_COMPLETE (k < 5) or COMPLETE (k = 5), also in
%   log.txt (S6); the stops of A3, A4 and A20 are interruptions as in mode 'a'.
%   res.status ('COMPLETE', 'SESSION_COMPLETE' or 'INTERRUPTED'), res.reason ('', 'CEILING', 'A4',
%   'ERROR'), res.trial_id (where of the stop), res.n_run, res.n_reused, res.elapsed_s (cumulative
%   in mode 'session'), res.error_id (ERROR), res.session (k, or 0 in the modes 'a' and 'b')

C = ctx.C;
% ---------------------------------------------------------------- session mode (amendment 5, S1 to S6)
SS = e5_sessions();
session_k = 0;
session_fams = {};
elapsed_prior = 0;
if strcmp(ctx.mode, 'session')
    session_k = ctx.session;
    if ~(isnumeric(session_k) && isscalar(session_k) && any(session_k == 1:numel(SS)))
        error('e5_campaign_run:session', 'ctx.session must be 1 to %d in the mode session.', numel(SS));
    end
    session_fams = SS(session_k).families;     % S1: fixed in e5_sessions, never passed by hand
elseif ~any(strcmp(ctx.mode, {'a', 'b'}))
    error('e5_campaign_run:mode', 'ctx.mode must be a, b or session.');
end
session_start = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
if session_k >= 2
    % S2, S4: start checks of the session; a refusal writes nothing in the campaign folder
    [fails, prior] = e5_session_check(ctx.dir, session_k, ctx.plan, ctx.head, C.spec_sha);
    if ~isempty(fails)
        error('e5_campaign_run:sessionStart', 'Session %d refused (amendment 5, S2 and S4): %s.', session_k, strjoin(fails, '; '));
    end
    elapsed_prior = prior.elapsed_s;            % S5: elapsed times of the earlier sessions
else
    if exist(ctx.dir, 'dir')
        error('e5_campaign_run:exists', 'Campaign folder already exists: %s', ctx.dir);
    end
    mkdir(ctx.dir);
end
log_file = fullfile(ctx.dir, 'log.txt');
res = struct('status', 'RUNNING', 'reason', '', 'trial_id', '', 'n_run', 0, 'n_reused', 0, 'elapsed_s', 0, 'error_id', '', ...
             'session', session_k);
where = 'init';
try
    plan = ctx.plan;
    plan_ids = {plan.trial_id};
    in_scope = true(1, numel(plan));
    if session_k >= 1
        in_scope = ismember({plan.family}, session_fams);
        log_line(log_file, sprintf('session %d start: families %s, %d trials, elapsed of the earlier sessions %.1f s (S5)', ...
                 session_k, strjoin(session_fams, ' '), nnz(in_scope), elapsed_prior));
    end
    if session_k <= 1                           % S3: meta.mat and trials.csv written once, by session 1
        e5_records('init', ctx.dir);
        where = 'meta';
        meta = struct('mode', ctx.mode, 'prev_dir', ctx.prev_dir, 'head', ctx.head, 'spec_sha', C.spec_sha, ...
                      'settings', C, 'plan_ids', {plan_ids}, 'plan', {plan}, 'draws', {e5_search_space(C)}, ...
                      'facts', ctx.facts, 'data_info', ctx.data_info, 'start', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
        meta.gpu_name = '';                            % A7: name of the GPU of the trainings
        if canUseGPU
            gpu_info = gpuDevice;
            meta.gpu_name = gpu_info.Name;
        end
        meta.threads = maxNumCompThreads;
        meta.sessions = SS;
        save(fullfile(ctx.dir, 'meta.mat'), 'meta', '-v7');
        write_meta_txt(fullfile(ctx.dir, 'meta.txt'), meta);
    end
    completed = false(1, numel(plan));
    % ------------------------------------------------------------ resume (-b), l.154
    if strcmp(ctx.mode, 'b')
        where = 'resume';
        prev = load(fullfile(ctx.prev_dir, 'meta.mat'), 'meta');
        if ~strcmpi(prev.meta.head, ctx.head) || ~strcmp(prev.meta.spec_sha, C.spec_sha) || ~isequal(prev.meta.plan_ids, plan_ids)
            error('e5_campaign_run:resume', 'The campaign -a was run with another code commit, spec or plan (l.154).');
        end
        rows = e5_records('read', ctx.prev_dir);
        for i_row = 1:numel(rows)
            row = rows(i_row);
            idx = find(strcmp(plan_ids, row.trial_id), 1);
            if isempty(idx) || completed(idx) || ~any(strcmp(row.status, {'COMPLETE', 'NO_FINITE_LOSS'})) || ...
                    ~e5_records('verify', ctx.prev_dir, row)
                log_line(log_file, sprintf('resume: line %s not reused (unknown, repeated, not complete or SHA-256 changed)', row.trial_id));
                continue
            end
            prev_rec = load(fullfile(ctx.prev_dir, row.record_file), 'rec');
            if strcmp(e5_stop_rule(prev_rec.rec), 'A4')           % K2: a record of an A4 stop is never reused
                log_line(log_file, sprintf('resume: line %s not reused (A4 stop rule, the trial runs again)', row.trial_id));
                continue
            end
            copy_checked(ctx.prev_dir, ctx.dir, row.record_file, row.record_sha);
            if ~isempty(row.model_file)
                copy_checked(ctx.prev_dir, ctx.dir, row.model_file, row.model_sha);
            end
            row.reused = 1;
            e5_records('append', ctx.dir, row);
            completed(idx) = true;
            elapsed_prior = elapsed_prior + prev_rec.rec.time_total;   % time of the hashed record file (P4b-3)
            res.n_reused = res.n_reused + 1;
            log_line(log_file, sprintf('resume: %s reused, time_total %.1f s', row.trial_id, prev_rec.rec.time_total));
        end
    end
    % ------------------------------------------------------------ trials
    c5 = struct('tr', [], 'sel', []);
    cache = containers.Map();
    cache_family = '';
    for i = 1:numel(plan)
        if ~in_scope(i)                         % S1: only the families of the session
            continue
        end
        tr_def = plan(i);
        if ~strcmp(tr_def.family, cache_family)          % K5 (A18): data reused only inside a family
            cache = containers.Map();
            cache_family = tr_def.family;
            log_line(log_file, sprintf('data cache cleared at the start of family %s', cache_family));
        end
        if ~completed(i)
            if strcmp(tr_def.family, 'C5') && isempty(c5.tr)  % K3 (A11): at the start of the family C5
                where = 'C5_targets';
                c5 = c5_targets(ctx, log_file);
            end
            where = tr_def.trial_id;
            T = e5_scaled_time(C, tr_def.family, tr_def.cfg_index);
            elapsed = elapsed_prior + toc(ctx.t0);
            [ok, margin] = e5_ceiling_check(elapsed, T.total, C.ceiling_s);
            if ~ok
                res = stop_campaign(res, ctx.dir, log_file, 'CEILING', tr_def.trial_id, sprintf(['elapsed %.1f s + scaled time %.1f s ' ...
                           '> ceiling %.1f s (margin %.1f s)'], elapsed, T.total, C.ceiling_s, margin));
                res.elapsed_s = elapsed;
                res = end_session(res, ctx, session_k, session_fams, session_start, elapsed_prior, log_file);
                return
            end
            [payload, rec, cache] = run_trial(tr_def, ctx, c5, cache, T);
            e5_records('write', ctx.dir, payload, rec);
            res.n_run = res.n_run + 1;
            log_line(log_file, sprintf('%s %s: training %.1f s, evaluation %.1f s, cost %.1f s, n_failed %d, criterion %.6g, flags %d %d', ...
                     tr_def.trial_id, rec.status, rec.time_train, rec.time_eval, rec.time_cost, rec.n_failed_a, rec.criterion_a, ...
                     rec.flag_train, rec.flag_eval));
            if strcmp(e5_stop_rule(rec), 'A4')
                res = stop_campaign(res, ctx.dir, log_file, 'A4', tr_def.trial_id, sprintf('identity %s, identity_max %s', ...
                                    rec.identity, rec.identity_max));
                res.elapsed_s = elapsed_prior + toc(ctx.t0);
                res = end_session(res, ctx, session_k, session_fams, session_start, elapsed_prior, log_file);
                return
            end
            completed(i) = true;
        end
        fam_idx = find(strcmp({plan.family}, tr_def.family));
        if i == fam_idx(end) && all(completed(fam_idx))
            where = ['selection_' tr_def.family];
            select_family(tr_def.family, ctx, plan(fam_idx), log_file);
        end
    end
    if session_k >= 1 && ~all(completed(in_scope))
        where = 'session_end';
        error('e5_campaign_run:sessionEnd', 'Session %d: %d of its %d trials are not complete.', session_k, ...
              nnz(in_scope & ~completed), nnz(in_scope));
    end
catch ME
    % K1 (A20): every error raised once the campaign folder exists is an interruption with its report
    report = getReport(ME, 'extended', 'hyperlinks', 'off');
    res.error_id = ME.identifier;
    try
        if ~isfolder(fullfile(ctx.dir, 'errors'))
            mkdir(fullfile(ctx.dir, 'errors'));
        end
        e5_records('error', ctx.dir, where, 'ERROR', report);
    catch ME_record
        report = sprintf('%s\n(the error record could not be written: %s)', report, ME_record.message);
    end
    res = stop_campaign(res, ctx.dir, log_file, 'ERROR', where, report);
    res.elapsed_s = elapsed_prior + toc(ctx.t0);
    res = end_session(res, ctx, session_k, session_fams, session_start, elapsed_prior, log_file);
    return
end
res.elapsed_s = elapsed_prior + toc(ctx.t0);
if session_k == 0
    res.status = 'COMPLETE';
    log_line(log_file, sprintf('campaign COMPLETE: %d trials run, %d reused, elapsed %.1f s', res.n_run, res.n_reused, res.elapsed_s));
else
    if session_k == numel(SS)
        res.status = 'COMPLETE';                % S6: the campaign is COMPLETE at the end of session 5
    else
        res.status = 'SESSION_COMPLETE';        % S6: normal end of a session, not an interruption
    end
    log_line(log_file, sprintf('session %d %s: %d trials run, elapsed of the session %.1f s, cumulative elapsed %.1f s (S5)', ...
             session_k, res.status, res.n_run, res.elapsed_s - elapsed_prior, res.elapsed_s));
    res = end_session(res, ctx, session_k, session_fams, session_start, elapsed_prior, log_file);
end
end

% ================================================================ end of a session (S3, S5, S6)
function res = end_session(res, ctx, session_k, session_fams, session_start, elapsed_prior, log_file)
% meta_session<k>.mat and .txt, written once at the end of session k (any end: SESSION_COMPLETE,
% COMPLETE or INTERRUPTED); never raises: a failure is an interruption with its error record
if session_k == 0
    return
end
try
    ms.session = session_k;
    ms.families = session_fams;
    ms.start = session_start;
    ms.end = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    ms.elapsed_session_s = toc(ctx.t0);         % S5: from the first line of the launch (ctx.t0) to its end
    ms.elapsed_prior_s = elapsed_prior;
    ms.elapsed_cumulative_s = elapsed_prior + ms.elapsed_session_s;
    ms.status = res.status;
    ms.reason = res.reason;
    ms.where = res.trial_id;
    ms.error_id = res.error_id;
    ms.n_run = res.n_run;
    ms.threads = maxNumCompThreads;
    ms.gpu_name = '';
    if canUseGPU
        gpu_info = gpuDevice;
        ms.gpu_name = gpu_info.Name;
    end
    ms.head = ctx.head;
    ms.spec_sha = ctx.C.spec_sha;
    SS = e5_sessions();
    ms.planned_h = SS(session_k).planned_h;
    ms_mat = fullfile(ctx.dir, sprintf('meta_session%d.mat', session_k));
    ms_txt = fullfile(ctx.dir, sprintf('meta_session%d.txt', session_k));
    if isfile(ms_mat) || isfile(ms_txt)
        error('e5_campaign_run:metaSession', 'meta_session%d exists and is never rewritten (S3).', session_k);
    end
    save(ms_mat, 'ms', '-v7');
    fid = fopen(ms_txt, 'w');
    fprintf(fid, 'session %d\nfamilies %s\nstart %s\nend %s\n', ms.session, strjoin(ms.families, ' '), ms.start, ms.end);
    fprintf(fid, 'elapsed of the session %.1f s, of the earlier sessions %.1f s, cumulative %.1f s (S5); planned %.2f h (S1)\n', ...
            ms.elapsed_session_s, ms.elapsed_prior_s, ms.elapsed_cumulative_s, ms.planned_h);
    fprintf(fid, 'status %s\nreason %s\nwhere %s\nerror_id %s\ntrials run %d\n', ms.status, ms.reason, ms.where, ms.error_id, ms.n_run);
    fprintf(fid, 'maxNumCompThreads %d\ngpu %s\nhead %s\nspec_sha %s\n', ms.threads, ms.gpu_name, ms.head, ms.spec_sha);
    fclose(fid);
    log_line(log_file, sprintf('meta_session%d written: status %s', session_k, ms.status));
catch ME
    report = getReport(ME, 'extended', 'hyperlinks', 'off');
    try
        e5_records('error', ctx.dir, sprintf('meta_session%d', session_k), 'ERROR', report);
    catch ME_record
        report = sprintf('%s\n(the error record could not be written: %s)', report, ME_record.message);
    end
    if ~strcmp(res.status, 'INTERRUPTED')
        res.error_id = ME.identifier;
        res = stop_campaign(res, ctx.dir, log_file, 'ERROR', sprintf('meta_session%d', session_k), report);
    else
        log_line(log_file, sprintf('meta_session%d not written: %s', session_k, ME.message));
    end
end
end

% ================================================================ C5 targets (A11)
function c5 = c5_targets(ctx, log_file)
% once, when the loop reaches the first pending C5 trial (K3), on every training and selection row
t_c5 = tic;
rows_tr = e5_rows(ctx.runs, ctx.part.train_filtered, 'current', 1);
rows_sel = e5_rows(ctx.runs, ctx.part.selection, 'current', 1);
[y_tr, keep_tr] = e5_c5_targets(ctx.runs, rows_tr, ctx.nrm, ctx.p);
[y_sel, keep_sel] = e5_c5_targets(ctx.runs, rows_sel, ctx.nrm, ctx.p);
c5.tr = struct('rows', rows_tr, 'Y', y_tr, 'keep', keep_tr);
c5.sel = struct('rows', rows_sel, 'Y', y_sel, 'keep', keep_sel);
log_line(log_file, sprintf('C5 targets: training rows excluded %d of %d, selection rows excluded %d of %d, %.1f s', ...
         nnz(~keep_tr), numel(keep_tr), nnz(~keep_sel), numel(keep_sel), toc(t_c5)));
end

% ================================================================ one trial
function [payload, rec, cache] = run_trial(tr_def, ctx, c5, cache, T)
C = ctx.C;
S = ctx.S;
fam = tr_def.family;
cfg = tr_def.cfg;
rec = struct('trial_id', tr_def.trial_id, 'family', fam, 'cfg_index', tr_def.cfg_index, 'seed', tr_def.seed, 'cfg', cfg);
rec.scaled = T;
rec.partitions = struct('train_filtered', {{ctx.runs(ctx.part.train_filtered).id}}, ...
                        'selection', {{ctx.runs(ctx.part.selection).id}});           % K4 (l.150)
rec.loss = ['framework_decisions.loss (E5 l.34): mean of the squared errors of the two normalised outputs, ' ...
            'equal weights (networks: e5_train_nn; C4: local weighted least squares and selection MSE; ' ...
            'C6: marginal likelihood of fitrgp); C5 targets of e5_c5_targets (D7, A11)'];
rec.normalisation_sha = ctx.nrm.sha;
L_model = [];
t_trial = tic;
switch fam
    case {'MLP', 'C1', 'C2', 'C3', 'C5'}
        if any(strcmp(fam, {'C1', 'C2', 'C3'}))
            L_model = cfg.L;
        end
        key = sprintf('%s_%d', fam, max([L_model, 1]));
        if ~isKey(cache, key)
            t_data = tic;
            if strcmp(fam, 'C5')
                d_tr = e5_nn_data(ctx.runs, ctx.part.train_filtered, fam, 1, ctx.nrm, c5.tr);
                d_sel = e5_nn_data(ctx.runs, ctx.part.selection, fam, 1, ctx.nrm, c5.sel);
            else
                d_tr = e5_nn_data(ctx.runs, ctx.part.train_filtered, fam, max([L_model, 1]), ctx.nrm);
                d_sel = e5_nn_data(ctx.runs, ctx.part.selection, fam, max([L_model, 1]), ctx.nrm);
            end
            cache(key) = struct('tr', d_tr, 'sel', d_sel, 'time', toc(t_data));
        end
        dat = cache(key);
        [net, model_struct, trec] = e5_train_nn(fam, cfg, tr_def.seed, dat.tr, dat.sel, C.train_opts);
        rec.train = trec;
        rec.train_opts = C.train_opts;
        rec.optimiser = sprintf(['Adam (adamupdate defaults: beta1 0.9, beta2 0.999, epsilon 1e-8), learning rate %g, ' ...
                                 'batch %d, at most %d epochs, rows shuffled every epoch (A9)'], cfg.lr, C.train_opts.batch, C.train_opts.max_epochs);
        rec.stopping_rule = sprintf(['selection-subset loss after every epoch, stop after %d epochs without strict ' ...
                                     'improvement or at epoch %d, best epoch restored (A10, D11)'], C.train_opts.patience, C.train_opts.max_epochs);
        rec.status = trec.status;
        rec.best_epoch = trec.best_epoch;
        rec.n_excluded = dat.tr.n_excluded;
        rec.n_warn = NaN;
        if strcmp(trec.status, 'COMPLETE')
            payload = struct('family', fam, 'cfg', cfg, 'seed', tr_def.seed, 'model_struct', model_struct, 'net', net);
        else
            payload = [];
        end
    case 'C4'
        L_model = cfg.L;
        [~, fit, crec] = e5_train_c4(ctx.runs, ctx.part, cfg, ctx.nrm, S, C.c4_opts);
        model_struct = crec.Lm;
        rec.train = rmfield(crec, 'Lm');
        rec.c4_opts = C.c4_opts;
        rec.optimiser = sprintf(['LOLIMOT (e5_lolimot), local weighted least squares, ' ...
                                 'scheduling %s, L %d, k_sigma 1/3, up to %d local models (A12)'], cfg.sched, cfg.L, C.c4_opts.m_max);
        rec.stopping_rule = sprintf('all %d sizes built, size = first argmin of the selection MSE (D6, A12)', C.c4_opts.m_max);
        rec.status = crec.status;
        rec.n_warn = crec.n_warn;                    % A6
        rec.identity = crec.identity.verdict;        % A4
        rec.identity_max = crec.identity_max.verdict;
        payload = struct('family', fam, 'cfg', cfg, 'seed', 0, 'model_struct', model_struct, 'fit', fit);
    case 'C6'
        [~, G, grec] = e5_train_c6(ctx.runs, ctx.part, cfg, tr_def.seed, ctx.nrm);
        model_struct = G;
        rec.train = grec;
        rec.optimiser = sprintf(['fitrgp per state component, ARD squared exponential kernel, FitMethod and PredictMethod fic, ' ...
                                 'BasisFunction none, Standardize false, subsample %d, active set %d (D5, A13)'], cfg.n_sub, cfg.n_act);
        rec.stopping_rule = 'fitrgp hyperparameter optimiser and stopping rule at their defaults (no option passed, D5)';
        rec.status = grec.status;
        rec.n_warn = NaN;
        payload = struct('family', fam, 'cfg', cfg, 'seed', tr_def.seed, 'model_struct', G, 'sub_rows', grec.sub_rows, ...
                         'act_pos', grec.act_pos);
    otherwise
        error('e5_campaign_run:family', 'Unknown family %s.', fam);
end
rec.time_train = toc(t_trial);
if ~isfield(rec, 'identity')
    rec.identity = '';
    rec.identity_max = '';
end
n_seg = numel(e5_segments(S.n_rows_run, S))*nnz(ctx.part.selection);
if strcmp(rec.status, 'COMPLETE')
    model = e5_model(fam, model_struct, ctx.nrm, struct('L', L_model, 'p', ctx.p));
    t_eval = tic;
    seg_a = e5_eval_segments(ctx.runs, ctx.part.selection, model, S, 'a');
    met_a = e5_metrics(seg_a, S);
    seg_b = e5_eval_segments(ctx.runs, ctx.part.selection, model, S, 'b');
    met_b = e5_metrics(seg_b, S);
    rec.time_eval = toc(t_eval);
    [rec.criterion_a, rec.n_failed_a] = e5_criterion(seg_a, S);
    rec.n_failed_b = nnz(seg_b.failed);
    rec.metrics_a = met_a;
    rec.metrics_b = met_b;
    rec.seg_a = seg_a;
    rec.seg_b = seg_b;
    t_cost = tic;
    rec.cost = e5_prediction_cost(ctx.runs, ctx.part.selection, model, S);   % A14
    rec.time_cost = toc(t_cost);
    rec.cost_median = rec.cost.median;
else
    rec.time_eval = 0;
    rec.criterion_a = Inf;
    rec.n_failed_a = n_seg;
    rec.n_failed_b = n_seg;
    rec.time_cost = 0;
    rec.cost_median = NaN;
end
rec.time_total = rec.time_train + rec.time_eval + rec.time_cost;
rec.flag_train = double(rec.time_train > T.train);                           % A5
rec.flag_eval = double(rec.time_eval > T.eval);
rec.finished = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

% ================================================================ selection of a family (A19, A17)
function select_family(fam, ctx, plan_fam, log_file)
S = ctx.S;
rows = e5_records('read', ctx.dir);
rows = rows(strcmp({rows.family}, fam));
if numel(rows) ~= numel(plan_fam)
    error('e5_campaign_run:selection', 'Family %s has %d records, %d trials planned.', fam, numel(rows), numel(plan_fam));
end
crit = [rows.criterion_a]';
crit(isnan(crit)) = Inf;
T = table([rows.cfg_index]', [rows.seed]', [rows.n_failed_a]', crit, [rows.cost_median]', ...
          'VariableNames', {'cfg_index', 'seed', 'n_failed', 'criterion', 'cost'});
sel = e5_select(T);
win = rows(sel.retained_row);
out = struct('family', fam, 'selection', sel, 'retained_trial', win.trial_id, 'validation_other', [], 'plausibility', []);
if strcmp(win.status, 'COMPLETE') && ~isempty(win.model_file)
    pay = load(fullfile(ctx.dir, win.model_file));
    L_model = [];
    if isfield(pay.cfg, 'L')
        L_model = pay.cfg.L;
    end
    model = e5_model(fam, pay.model_struct, ctx.nrm, struct('L', L_model, 'p', ctx.p));
    other = ctx.part.validation(:) & ~ctx.part.selection(:);
    if any(other)
        seg_a = e5_eval_segments(ctx.runs, other, model, S, 'a');
        seg_b = e5_eval_segments(ctx.runs, other, model, S, 'b');
        out.validation_other = struct('seg_a', seg_a, 'seg_b', seg_b, 'metrics_a', e5_metrics(seg_a, S), ...
                                      'metrics_b', e5_metrics(seg_b, S));
    end
    out.plausibility = e5_plausibility(ctx.runs, ctx.part.validation, model, S);    % D14
end
save(fullfile(ctx.dir, ['selection_' fam '.mat']), 'out', '-v7');
sel_csv = fullfile(ctx.dir, 'selection.csv');
if ~isfile(sel_csv)
    fid = fopen(sel_csv, 'w');
    fprintf(fid, 'family;retained_trial;cfg_index;seed;n_failed;criterion;cost;n_tie\n');
    fclose(fid);
end
fid = fopen(sel_csv, 'a');
fprintf(fid, '%s;%s;%d;%d;%d;%.17g;%.17g;%d\n', fam, win.trial_id, sel.retained_cfg, sel.retained_seed, ...
        win.n_failed_a, win.criterion_a, win.cost_median, nnz(sel.configs.in_tie));
fclose(fid);
log_line(log_file, sprintf('selection %s: retained %s (%d configurations in the tie)', fam, win.trial_id, nnz(sel.configs.in_tie)));
end

% ================================================================ helpers
function res = stop_campaign(res, camp_dir, log_file, reason, where, text)
res.status = 'INTERRUPTED';
res.reason = reason;
res.trial_id = where;
fid = fopen(fullfile(camp_dir, 'stop.txt'), 'a');          % appended, never rewritten (S3)
fprintf(fid, 'status FAILED_KEPT\nreason %s\nwhere %s\n%s\n', reason, where, text);
fclose(fid);
log_line(log_file, sprintf('campaign INTERRUPTED (%s) at %s', reason, where));
end

function copy_checked(src_dir, dst_dir, rel, sha)
copyfile(fullfile(src_dir, rel), fullfile(dst_dir, rel));
if ~strcmp(e5_sha256(fullfile(dst_dir, rel)), sha)
    error('e5_campaign_run:copy', 'The copy of %s has another SHA-256.', rel);
end
end

function log_line(log_file, text)
fprintf('%s\n', text);
fid = fopen(log_file, 'a');
fprintf(fid, '%s %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), text);
fclose(fid);
end

function write_meta_txt(file_path, meta)
SP = meta.draws;
fid = fopen(file_path, 'w');
fprintf(fid, 'mode %s\nprevious %s\nhead %s\nspec_sha %s\nstart %s\n', meta.mode, meta.prev_dir, meta.head, meta.spec_sha, meta.start);
fprintf(fid, 'gpu %s, maxNumCompThreads %d\n', meta.gpu_name, meta.threads);
fprintf(fid, 'ceiling %.1f s, allowance %.2f, P3 record %s\n', meta.settings.ceiling_s, meta.settings.allowance, meta.settings.p3_record_sha);
fprintf(fid, 'train_opts exec %s, max_epochs %d, patience %d, batch %d; c4 m_max %d\n', meta.settings.train_opts.exec, ...
        meta.settings.train_opts.max_epochs, meta.settings.train_opts.patience, meta.settings.train_opts.batch, meta.settings.c4_opts.m_max);
for f = 1:numel(SP)
    fprintf(fid, 'draws %s (%d configurations, %s): %s\n', SP(f).family, size(SP(f).values, 1), strjoin(SP(f).names, ', '), ...
            mat2str(SP(f).drawn));
end
fprintf(fid, 'plan %d trials: %s\n', numel(meta.plan_ids), strjoin(meta.plan_ids, ' '));
fclose(fid);
end
