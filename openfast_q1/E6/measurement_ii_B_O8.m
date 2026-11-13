function final = measurement_ii_B_O8(expected_head, out_dir)
%MEASUREMENT_II_B_O8  Measurement (ii) of arm B, brought forward by spec_E6_solver_O8 amendment 5 of
%12/11/2026 (cost_measurement_protocol.amendment_5 with ii_selected and amendment_4): open-loop
%replay of O8 on recorded states of the E4 dataset, before budget_rule step (1).
%
%   final = measurement_ii_B_O8(expected_head, out_dir)
%
%   expected_head: commit of the code; out_dir: existing run folder under results/work_Q1 (created by
%   the launch block). Writes only in out_dir, after every window: measurement_ii_B_O8.txt,
%   measurement_ii_B_O8.mat (with T_arm), speeds.csv, windows.csv, calls.csv, errors.txt.
%   final: 'MEASUREMENT (ii) B COMPLETE' if the 21 windows were done, 'MEASUREMENT (ii) B
%   INCOMPLETE' if the total limit stopped it (amendment_5.ii_B_early).
%
%   Points (ii_selected, amendment_5.ii_B_early): the X0 run of the training seed 34001 at the seven
%   mean speeds 12 to 24 m/s, tables results/Q1-E4-DATA-2026-10-28-a/dataset/U<v>_S34001_X0_
%   Ts0p050.mat checked against the SHA-256 of o8_points_B.m l.29-49; in each run three windows of
%   100 consecutive calls starting at t = 60, 300 and 540 s (rows t_k = t_0 + (k - 1) x 0.05 s);
%   at each call x = [omega_r; omega_f] and d = d_RtVAvgxh of the row t_k, lastMV = u_deg of the
%   row t_k - 0.05 s (o8_points_B.m l.75-91); the first call of the window at t = 60 s takes
%   lastMV = u_deg of its own row (supervisor decision P2 of 03/11/2026, as o8_points_B with
%   'u_deg_same_row', declared in the output). No plant step: the next call takes the next
%   recorded row.
%   Warm start: uz0 = lastMV x ones(Nc, 1) at the first call of each window (warm_start.first_call),
%   then sol.uz_next of the previous call of the same window (warm_start.O8_rule).
%   Model: o8_model_B(p) with p.cp_mode = 'nmpc' (prediction.cp_fallback), unchanged; o8_solve
%   unchanged; cfg = o8_settings() with the cap OutputFcn added to a copy of cfg.options
%   (amendment_4.cap, cap_fcn below as in measurement_i_O8.m); a call is CAPPED if the OutputFcn
%   stopped it or if rec.time_s > 300 s.
%   Limits (amendment_5.ii_B_early, time_limits): 90 min in total; a call is started only if at least
%   CAP_S + MARGIN_S = 330 s remain; otherwise the measurement stops, the window in progress is
%   marked partial and the measurement INCOMPLETE; the statistics per speed use the complete
%   windows only.
%   Threads (amendment_4.threads): maxNumCompThreads set to feature('numcores'), recorded, restored
%   by onCleanup. Memory guard (memory_guard): the upper bound 8 x Np x (nz^2 + nz + nz Nc) bytes
%   against memory().MemAvailableAllArrays, checked once (one model).
%   Per call: the record of o8_solve (as measurement_i_O8.m), CAPPED, the outer tic/toc, u_apply,
%   fval, and the point (speed, window, t, row, x, d, lastMV and its source).
%   Per speed (amendment_5.reporting), over all the calls of its complete windows, none excluded:
%   number of calls, mean, median, P95 (as timing_E6_nlmpc.m l.449-450) and max of rec.time_s,
%   CAPPED count, exit-code counts, status counts, share of calls with n_out_region3_final > 0,
%   clamp counts (final prediction and all evaluations, lambda and beta), median iterations.
%   T_arm(B) = sum over the seven speeds of (T_plant(v) + 13200 x mean(v)), T_plant = 741, 772, 862,
%   791, 409, 319, 302 s (F3_campaign_cost.estimate); reported only if every speed has three
%   complete windows; no decision (budget_rule step (1) belongs to the author). No statistic of
%   control quality is computed (amendment_5.reporting). Caveat of ii_selected written in the
%   output. Every catch records getReport(ME, 'extended').

LIMIT_S = 90*60;   CAP_S = 300;   MARGIN_S = 30;   % time_limits, amendment_5.ii_B_early
TS = 0.05;                                        % s, sample time of the E4 tables
SPEEDS = 12:2:24;                                 % m/s, ii_selected
SEED = 34001;                                     % ii_selected: training seed
WINDOW_STARTS = [60 300 540];                     % s, ii_selected
NCALL_WINDOW = 100;                               % ii_selected
T_PLANT = [741 772 862 791 409 319 302];          % s, F3_campaign_cost.estimate (12 to 24 m/s)
CALLS_PER_RUN = 13200;                            % F3_campaign_cost.estimate
TABLE_SHA = {12, '528d9999a605779469a94cb02e7e1d29f2734ffa59ed71f4ac923cfa9ddbdc13';   % o8_points_B.m l.29
             14, '4de833bc62d9691e61ef4bb1df15219098736c1b661a1123e7553f5322de4a03';   % l.32
             16, 'f3e1885e648ccc1216de350b2d5182e6d6aea56029443bc562df5f5eb1a2d9f9';   % l.35
             18, '096df2714c38ae444d83fbeade0f250daa425490317813f397c79af7398ce3f5';   % l.38
             20, '6fb688ad3314ea2f2776df6c8a6523ce4391f1ac93e37a2ca8297bc0fad8b267';   % l.41
             22, '8e77d3c835714e6606ee83427a8834fe36be860bb2839868033c12095ab2f44e';   % l.44
             24, '94c309408e4aef408d3cb5fb70bff2f465dc5807fed41380b7edf6dac701dbc6'};  % l.47

t0 = tic;
[root, txt_lines] = preflight_measurement_ii_B(expected_head, out_dir);
txt_file = fullfile(out_dir, 'measurement_ii_B_O8.txt');
mat_file = fullfile(out_dir, 'measurement_ii_B_O8.mat');
if isfile(txt_file) || isfile(mat_file)
    error('measurement_ii_B_O8:exists', 'Output files already exist in %s.', out_dir);
end
e2_dir = fullfile(root, 'openfast_q1', 'E2');
e6_dir = fullfile(root, 'openfast_q1', 'E6');
test_src = fullfile(e6_dir, 'tests');
addpath(e2_dir, e6_dir, test_src);
names_check = {'rom_step', e2_dir; 'o8_solve', e6_dir; 'o8_cost', e6_dir; 'o8_model_B', e6_dir; 'o8_settings', e6_dir; ...
               'o8_sha256', test_src};
for k = 1:size(names_check, 1)
    if ~strcmp(which(names_check{k, 1}), fullfile(names_check{k, 2}, [names_check{k, 1} '.m']))
        error('measurement_ii_B_O8:path', '%s resolves to %s.', names_check{k, 1}, which(names_check{k, 1}));
    end
end

% ---------------------------------------------------------------- points, read only
data_dir = fullfile(root, 'results', 'Q1-E4-DATA-2026-10-28-a', 'dataset');
pts = struct('speed', {}, 'window', {}, 'k', {}, 't', {}, 'row', {}, 'x', {}, 'd', {}, 'lastmv', {}, 'lastmv_source', {});
for iv = 1:numel(SPEEDS)
    speed = SPEEDS(iv);
    run_id = sprintf('U%d_S%d', speed, SEED);
    file_v = fullfile(data_dir, [run_id '_X0_Ts0p050.mat']);
    sha_v = o8_sha256(file_v);
    sha_expect = TABLE_SHA{[TABLE_SHA{:, 1}] == speed, 2};
    if ~strcmp(sha_v, sha_expect)
        error('measurement_ii_B_O8:sha', '%s has SHA-256 %s, expected %s.', file_v, sha_v, sha_expect);
    end
    txt_lines{end+1} = sprintf('E4 table %s_X0_Ts0p050.mat %s: OK', run_id, sha_v); %#ok<AGROW>
    loaded = load(file_v, 'T');
    tbl = loaded.T;
    for iw = 1:numel(WINDOW_STARTS)
        for k = 1:NCALL_WINDOW
            t_k = WINDOW_STARTS(iw) + (k - 1)*TS;
            row_k = find(abs(tbl.t - t_k) < TS/100);
            if ~isscalar(row_k)
                error('measurement_ii_B_O8:row', '%s: %d rows at t = %g s, expected 1.', run_id, numel(row_k), t_k);
            end
            row_prev = find(abs(tbl.t - (t_k - TS)) < TS/100);
            if isscalar(row_prev)
                lastmv = tbl.u_deg(row_prev);
                src = sprintf('u_deg at t = %.2f s (row %d)', tbl.t(row_prev), row_prev);
            elseif isempty(row_prev) && k == 1 && WINDOW_STARTS(iw) == 60
                lastmv = tbl.u_deg(row_k);
                src = sprintf('NO ROW k-1: u_deg at t = %.2f s (row %d), P2 u_deg_same_row', tbl.t(row_k), row_k);
            else
                error('measurement_ii_B_O8:lastmv', '%s t = %g s: no row at t - Ts for lastMV.', run_id, t_k);
            end
            pts(end+1) = struct('speed', speed, 'window', WINDOW_STARTS(iw), 'k', k, 't', tbl.t(row_k), 'row', row_k, ...
                                'x', [tbl.omega_r(row_k); tbl.omega_f(row_k)], 'd', tbl.d_RtVAvgxh(row_k), ...
                                'lastmv', lastmv, 'lastmv_source', src); %#ok<AGROW>
        end
    end
end
n_p2 = nnz(startsWith({pts.lastmv_source}, 'NO ROW'));
txt_lines{end+1} = sprintf('points built: %d (%d speeds x %d windows x %d calls); lastMV from its own row (P2) at %d calls', ...
    numel(pts), numel(SPEEDS), numel(WINDOW_STARTS), NCALL_WINDOW, n_p2);

% ---------------------------------------------------------------- settings
nthr0 = maxNumCompThreads;
restore_threads = onCleanup(@() maxNumCompThreads(nthr0));
maxNumCompThreads(feature('numcores'));
txt_lines{end+1} = sprintf('measurement_ii_B_O8 start %s | CPU threads %d (session default %d, restored at the end)', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), maxNumCompThreads, nthr0);
p = rom_params(fullfile(root, 'results', 'Q1-E2-ROM-2026-10-16-b', 'verification', 'cp_table_E2.mat'));
p.cp_mode = 'nmpc';
cfg = o8_settings();
if p.Ts ~= cfg.Ts || cfg.Ts ~= TS
    error('measurement_ii_B_O8:Ts', 'rom_params Ts %g, o8_settings Ts %g and table Ts %g differ.', p.Ts, cfg.Ts, TS);
end
cfg_meas = cfg;                                  % amendment_4.cap: copy of cfg.options with an OutputFcn
cfg_meas.options = optimoptions(cfg.options, 'OutputFcn', @(x, ov, st) cap_fcn(CAP_S));
model = o8_model_B(p);
mem = memory;
mem_estimate = 8*cfg.Np*(model.nz^2 + model.nz + model.nz*cfg.Nc);
if mem_estimate > mem.MemAvailableAllArrays
    error('measurement_ii_B_O8:memory', 'Memory estimate %.3g bytes above %.3g bytes available.', mem_estimate, mem.MemAvailableAllArrays);
end
txt_lines{end+1} = sprintf('memory estimate %.3g MB, available %.3g GB', mem_estimate/2^20, mem.MemAvailableAllArrays/2^30);
txt_lines{end+1} = sprintf('settings: model o8_model_B, p.cp_mode = ''nmpc'' (prediction.cp_fallback); Np %d, Nc %d, Ts %g s, MV [%g, %g] deg, rate %g deg, wy [%g %g], wdu %g', ...
    cfg.Np, cfg.Nc, cfg.Ts, cfg.u_min, cfg.u_max, cfg.rate_max, cfg.wy(1), cfg.wy(2), cfg.wdu);
txt_lines{end+1} = sprintf('limits: total %d s, cap %d s per call (OutputFcn on a copy of cfg.options), margin %d s; no plant step; warm start reset at each window', ...
    LIMIT_S, CAP_S, MARGIN_S);
txt_lines{end+1} = ['declared (amendment_5.ii_B_early): the first call of each window at t = 60 s takes lastMV = u_deg of its own row ' ...
    '(P2 of 03/11/2026); statistics over all the calls of the complete windows, no call excluded'];

% ---------------------------------------------------------------- replay
calls = struct('speed', {}, 'window', {}, 'k', {}, 't', {}, 'row', {}, 'x_omega_r', {}, 'x_omega_f', {}, 'd', {}, ...
               'lastmv', {}, 'lastmv_p2', {}, 'status', {}, 'exitflag', {}, 'exitflag_raw', {}, 'iterations', {}, ...
               'funccount', {}, 'constrviolation', {}, 'time_s', {}, 't_outer_s', {}, 'capped', {}, 'n_model_eval', {}, ...
               'n_jac_eval', {}, 'n_clamp_lambda', {}, 'n_clamp_beta', {}, 'n_clamp_lambda_final', {}, ...
               'n_clamp_beta_final', {}, 'n_out_region3_final', {}, 'n_nonfinite_eval', {}, 'u_apply', {}, 'fval', {}, ...
               'err_recorded', {});
W = struct('speed', {}, 'window', {}, 'n_calls', {}, 'complete', {}, 'mean_s', {}, 'max_s', {});
err_lines = {};
stopped = false;
for iv = 1:numel(SPEEDS)
    for iw = 1:numel(WINDOW_STARTS)
        sel = find([pts.speed] == SPEEDS(iv) & [pts.window] == WINDOW_STARTS(iw));
        n_done = 0;
        uz0 = [];
        for ip = sel
            if LIMIT_S - toc(t0) < CAP_S + MARGIN_S
                stopped = true;
                break
            end
            pt = pts(ip);
            if pt.k == 1
                uz0 = pt.lastmv*ones(cfg.Nc, 1);           % warm_start.first_call, at each window
            end
            try
                [calls, uz0, err_lines] = one_call(model, pt, uz0, cfg_meas, CAP_S, calls, err_lines);
            catch ME
                err_lines{end+1} = sprintf('speed %d window %d call %d\n%s', pt.speed, pt.window, pt.k, ...
                                           getReport(ME, 'extended', 'hyperlinks', 'off')); %#ok<AGROW>
                uz0 = pt.lastmv*ones(cfg.Nc, 1);
            end
            n_done = n_done + 1;
        end
        in_win = [calls.speed] == SPEEDS(iv) & [calls.window] == WINDOW_STARTS(iw);
        t_win = [calls(in_win).time_s];
        W(end+1) = struct('speed', SPEEDS(iv), 'window', WINDOW_STARTS(iw), 'n_calls', nnz(in_win), ...
                          'complete', n_done == NCALL_WINDOW && nnz(in_win) == NCALL_WINDOW, ...
                          'mean_s', mean([t_win, NaN(1, isempty(t_win))]), 'max_s', max([t_win, NaN])); %#ok<AGROW>
        txt_lines{end+1} = sprintf('window U%d t0 %3d s: calls %3d | complete %d | mean %.4f s | max %.4f s', ...
            W(end).speed, W(end).window, W(end).n_calls, W(end).complete, W(end).mean_s, W(end).max_s); %#ok<AGROW>
        fprintf('%s\n', txt_lines{end});
        write_out(out_dir, txt_lines, [], W, calls, err_lines, toc(t0), NaN);
        if stopped, break, end
    end
    if stopped, break, end
end

% ---------------------------------------------------------------- per speed, T_arm(B)
V = speed_summary(SPEEDS, W, calls, numel(WINDOW_STARTS));
for iv = 1:numel(V)
    txt_lines{end+1} = speed_line(V(iv)); %#ok<AGROW>
end
all_speeds_complete = all([V.n_windows_complete] == numel(WINDOW_STARTS));
if all_speeds_complete
    T_arm = sum(T_PLANT + CALLS_PER_RUN*[V.mean_s]);
    txt_lines{end+1} = sprintf('T_arm(B) = sum over the 7 speeds of (T_plant(v) + %d x mean(v)) = %.1f s = %.3f h (amendment_5.reporting; reported only, C_arm is fixed by the author, budget_rule step (1))', ...
        CALLS_PER_RUN, T_arm, T_arm/3600);
else
    T_arm = NaN;
    txt_lines{end+1} = 'T_arm(B) not reported: not every speed has three complete windows (amendment_5.ii_B_early: measurement incomplete)';
end
n_le0 = nnz([calls.exitflag] <= 0);
n_noef = nnz(isnan([calls.exitflag]));
txt_lines{end+1} = sprintf('all calls: %d | ExitFlag <= 0: %d | no ExitFlag: %d | CAPPED: %d | n_out_region3_final > 0: %d | errors caught %d', ...
    numel(calls), n_le0, n_noef, nnz([calls.capped]), nnz([calls.n_out_region3_final] > 0), numel(err_lines));
txt_lines{end+1} = ['caveat (ii_selected): the recorded states come from trajectories driven by DISCON, so the per-call time ' ...
    'in closed loop can differ (number of iterations); the estimate is an approximation and not a bound'];
txt_lines{end+1} = 'no statistic of control quality is computed (amendment_5.reporting)';
if stopped || ~all_speeds_complete
    final = 'MEASUREMENT (ii) B INCOMPLETE';
else
    final = 'MEASUREMENT (ii) B COMPLETE';
end
txt_lines{end+1} = sprintf('measurement_ii_B_O8 end %s, elapsed %.0f s', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), toc(t0));
txt_lines{end+1} = final;
write_out(out_dir, txt_lines, V, W, calls, err_lines, toc(t0), T_arm);
fprintf('%s\n', txt_lines{end-numel(V)-5:end});
fprintf('text SHA-256: %s\nmat SHA-256: %s\n', o8_sha256(txt_file), o8_sha256(mat_file));
end

% =============================================================================================
function [calls, uz0, err_lines] = one_call(model, pt, uz0, cfg_meas, cap, calls, err_lines)
% one O8 call at a recorded point, no plant step
setappdata(0, 'O8M_t0', tic);
setappdata(0, 'O8M_capped', false);
t_outer = tic;
[u_apply, sol, rec] = o8_solve(model, pt.x, pt.d, pt.lastmv, uz0, cfg_meas);
t_out = toc(t_outer);
capped = getappdata(0, 'O8M_capped') || rec.time_s > cap;
calls(end+1) = struct('speed', pt.speed, 'window', pt.window, 'k', pt.k, 't', pt.t, 'row', pt.row, ...
    'x_omega_r', pt.x(1), 'x_omega_f', pt.x(2), 'd', pt.d, 'lastmv', pt.lastmv, ...
    'lastmv_p2', startsWith(pt.lastmv_source, 'NO ROW'), 'status', rec.status, 'exitflag', rec.exitflag, ...
    'exitflag_raw', rec.exitflag_raw, 'iterations', rec.iterations, 'funccount', rec.funccount, ...
    'constrviolation', rec.constrviolation, 'time_s', rec.time_s, 't_outer_s', t_out, 'capped', capped, ...
    'n_model_eval', rec.n_model_eval, 'n_jac_eval', rec.n_jac_eval, 'n_clamp_lambda', rec.n_clamp_lambda, ...
    'n_clamp_beta', rec.n_clamp_beta, 'n_clamp_lambda_final', rec.n_clamp_lambda_final, ...
    'n_clamp_beta_final', rec.n_clamp_beta_final, 'n_out_region3_final', rec.n_out_region3_final, ...
    'n_nonfinite_eval', rec.n_nonfinite_eval, 'u_apply', u_apply, 'fval', sol.fval, 'err_recorded', ~isempty(rec.err));
if ~isempty(rec.err)
    err_lines{end+1} = sprintf('speed %d window %d call %d O8 record\n%s', pt.speed, pt.window, pt.k, rec.err);
end
uz0 = sol.uz_next;                              % warm_start.O8_rule, inside the window
end

function stop = cap_fcn(cap)
% OutputFcn of the measurement only (amendment_4.cap; as measurement_i_O8.m)
stop = toc(getappdata(0, 'O8M_t0')) > cap;
if stop, setappdata(0, 'O8M_capped', true); end
end

function V = speed_summary(speeds, W, calls, n_windows)
% statistics per speed over all the calls of its complete windows (amendment_5.reporting)
V = struct('speed', {}, 'n_windows_complete', {}, 'n_calls', {}, 'mean_s', {}, 'median_s', {}, 'p95_s', {}, 'max_s', {}, ...
           'n_capped', {}, 'exitflag_counts', {}, 'status_counts', {}, 'share_out_region3', {}, ...
           'clamp_lambda_final', {}, 'clamp_beta_final', {}, 'clamp_lambda_all', {}, 'clamp_beta_all', {}, ...
           'median_iterations', {});
for iv = 1:numel(speeds)
    win_ok = [W.window];
    win_ok = win_ok([W.speed] == speeds(iv) & [W.complete]);
    sel = [calls.speed] == speeds(iv) & ismember([calls.window], win_ok);
    cs = calls(sel);
    v = struct('speed', speeds(iv), 'n_windows_complete', numel(win_ok), 'n_calls', numel(cs), 'mean_s', NaN, ...
               'median_s', NaN, 'p95_s', NaN, 'max_s', NaN, 'n_capped', 0, 'exitflag_counts', '', 'status_counts', '', ...
               'share_out_region3', NaN, 'clamp_lambda_final', 0, 'clamp_beta_final', 0, 'clamp_lambda_all', 0, ...
               'clamp_beta_all', 0, 'median_iterations', NaN);
    if ~isempty(cs)
        t_all = [cs.time_s];
        ts = sort(t_all);
        v.mean_s = mean(t_all);
        v.median_s = median(t_all);
        v.p95_s = ts(ceil(0.95*numel(ts)));
        v.max_s = max(t_all);
        v.n_capped = nnz([cs.capped]);
        ef = [cs.exitflag];
        ef_list = unique(ef(~isnan(ef)));
        ef_text = arrayfun(@(e) sprintf('%d:%d', e, nnz(ef == e)), ef_list, 'UniformOutput', false);
        if any(isnan(ef)), ef_text{end+1} = sprintf('none:%d', nnz(isnan(ef))); end %#ok<AGROW>
        v.exitflag_counts = strjoin(ef_text, ' ');
        st_list = unique({cs.status});
        v.status_counts = strjoin(cellfun(@(s) sprintf('%s:%d', s, nnz(strcmp({cs.status}, s))), st_list, 'UniformOutput', false), ' ');
        v.share_out_region3 = nnz([cs.n_out_region3_final] > 0)/numel(cs);
        v.clamp_lambda_final = sum([cs.n_clamp_lambda_final], 'omitnan');
        v.clamp_beta_final = sum([cs.n_clamp_beta_final], 'omitnan');
        v.clamp_lambda_all = sum([cs.n_clamp_lambda]);
        v.clamp_beta_all = sum([cs.n_clamp_beta]);
        v.median_iterations = median([cs.iterations], 'omitnan');
    end
    if v.n_windows_complete < n_windows
        v.status_counts = [v.status_counts ' (incomplete speed)'];
    end
    V(end+1) = v; %#ok<AGROW>
end
end

function s = speed_line(v)
s = sprintf(['U%d | windows complete %d | calls %3d | mean %.4f s, median %.4f s, P95 %.4f s, max %.4f s | CAPPED %d | ' ...
             'ExitFlag %s | status %s | share n_out_region3_final > 0: %.3f | clamps final lambda %d beta %d, all lambda %d beta %d | ' ...
             'median iterations %g'], v.speed, v.n_windows_complete, v.n_calls, v.mean_s, v.median_s, v.p95_s, v.max_s, ...
    v.n_capped, v.exitflag_counts, v.status_counts, v.share_out_region3, v.clamp_lambda_final, v.clamp_beta_final, ...
    v.clamp_lambda_all, v.clamp_beta_all, v.median_iterations);
end

function write_out(out_dir, txt_lines, V, W, calls, err_lines, elapsed, T_arm)
% text, .mat, CSV and errors, rewritten after every window
fid = fopen(fullfile(out_dir, 'measurement_ii_B_O8.txt'), 'w');
fprintf(fid, '%s\n', txt_lines{:});
fprintf(fid, 'elapsed %.0f s\n', elapsed);
fclose(fid);
save(fullfile(out_dir, 'measurement_ii_B_O8.mat'), 'V', 'W', 'calls', 'txt_lines', 'err_lines', 'elapsed', 'T_arm');
if ~isempty(V)
    writetable(struct2table(V, 'AsArray', true), fullfile(out_dir, 'speeds.csv'), 'Delimiter', ';');
end
if ~isempty(W)
    writetable(struct2table(W, 'AsArray', true), fullfile(out_dir, 'windows.csv'), 'Delimiter', ';');
end
if ~isempty(calls)
    writetable(struct2table(calls, 'AsArray', true), fullfile(out_dir, 'calls.csv'), 'Delimiter', ';');
end
fid = fopen(fullfile(out_dir, 'errors.txt'), 'w');
fprintf(fid, 'errors caught by measurement_ii_B_O8: %d\n', numel(err_lines));
fprintf(fid, '%s\n', err_lines{:});
fclose(fid);
end

function [root, pre_lines] = preflight_measurement_ii_B(expected_head, out_dir)
% copy of o8_test_preflight.m l.27-96 with the SHA-256 of spec_E6_solver_O8 after amendment 5 and
% of o8_solve.m with the region-3 counter (as preflight_measurement_i of measurement_i_O8.m)
EXPECT = {'openfast_q1/E2/spec_E2.yaml',             'a3942e9c2f96dd31693a2f63963a57cf770e6a8392f80101f9f6728ec7650311';
          'openfast_q1/E6/spec_E6_solver_O8.yaml',   '38b5edb37c79ecee7428f75a73ff5217b14fe6beb196a490514be2c918751e02';
          'openfast_q1/E6/o8_solve.m',               '3ce4d5ac156d8c3cafacd0e7e499b958702d048772b66f57ba6e99a6713383cd';
          'openfast_q1/E2/rom_rhs.m',                'debc86ca1aa535aa6a0d913e78cce8e489fd296f8d1727b0ce6e6b6e03479480';
          'openfast_q1/E2/rom_step.m',               'fb1df96d44be04ea8fdc632092326394490869e1b3419ec6e696498f4309bf46';
          'openfast_q1/E2/rom_params.m',             '0b886331556bbb069238ec80709ac0d476824f81666813f6890e2444442f59b8';
          'openfast_q1/E2/rom_torque_law.m',         '4a769a46f09900013a7f02dbdb1fd6c418fc250871af788cf89eb1e4db1f6b5d';
          'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat', ...
                                                     '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2'};
TOOLBOX = {'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getDecisions.m',         '9c469ae3e5d3f08c684742c81896a152e14336e40f611ea4471a3ce82e3348db';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getXUe.m',               'a0d06cf4b9dc4f43e3b1e93ef725e0fad5aa488f105d95edfb801711b2daa0e6';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/objfun.m',               '05cf21efaeb1a734a3002fb4b208495cccd1400e2e19f53132a2391f92c391b3';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/confun.m',               '0da1523fc0a8c3caafa9d1bc53884afdbf163fa918afd3df1d934d592a9e36e6';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getUBounds.m',           '70160e41cd9b5de728025af0fa97f025e037f0f31ab0cf8cca4424979374f9e8';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/getZBounds.m',           '2f0bb356be05457f806d4fbbc9f58f082d51e4ef3a38eb86978c574e6437fd1d';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/computeJacobianState.m', 'f60c0b6b73bf1d4a00e6303025a1bb15b6a18fecb9174073feb311dd0a89d816';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/computeInfo.m',          'a211bca4d2043237b5befa05708d071f8dbdc51ab03d389ec91ef5577d031930';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/setDecisions.m',         'cf35db6fca5cbc0fd0931a28d165661bbe83e19a63904108e448e4ea9a3995bb';
           'toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/generateRuntimeData.m',  'f401ed4de996f432c3f68a2e02d67db0f2911702ebe2019a811f7d3b7768ef6e';
           'toolbox/mpc/mpc/@nlmpc/nlmpcmove.m',                                '2ebefec71ab3cdb61acfcc487937d18c9e838d7c64fc11462b75f75a25dca883';
           'toolbox/mpc/mpc/@nlmpc/private/nlmpc_getDefault.m',                 'a416b03324e1947f49db1c4450e74c118b66e76b030ca1d70218dd744f68c82f';
           'toolbox/mpc/mpc/@nlmpc/private/nlmpc_getCoreData.m',                '563ab0a1efd9c536043d5dfa74e6a693c1e117f148cb9c549e345a6e9acdc066';
           'toolbox/shared/optimlib/fmincon.m',                                 '924970840a47a87b3f35e7d82a631f0add1e381706e1f2da9aed0af8bf81f38b'};
if ~(ischar(expected_head) && isrow(expected_head) && numel(expected_head) == 40 && all(isstrprop(expected_head, 'xdigit')))
    error('measurement_ii_B_O8:head', 'expected_head must be a 40-character commit SHA.');
end
here = fileparts(mfilename('fullpath'));
root = fileparts(fileparts(here));
work_root = fullfile(root, 'results', 'work_Q1');
pre_lines = {sprintf('MATLAB %s | machine %s | working folder %s', version, getenv('COMPUTERNAME'), pwd)};
if ~(ischar(out_dir) && isfolder(out_dir) && startsWith(lower(out_dir), lower([work_root filesep])))
    error('measurement_ii_B_O8:outdir', 'The output folder must exist under %s.', work_root);
end
if startsWith(lower(pwd), lower(root)) && ~startsWith(lower(pwd), lower(work_root))
    error('measurement_ii_B_O8:pwd', 'The working folder %s is inside the repository %s and not under results/work_Q1.', pwd, root);
end
pre_lines{end+1} = sprintf('output folder %s: OK', out_dir);
[st_top, out_top] = system(sprintf('git -C "%s" rev-parse --show-toplevel', root));
if st_top ~= 0 || ~strcmpi(strrep(strtrim(out_top), '/', filesep), root)
    error('measurement_ii_B_O8:root', 'Repository root %s not confirmed by git (%s).', root, strtrim(out_top));
end
[st_head, out_head] = system(sprintf('git -C "%s" rev-parse HEAD', root));
if st_head ~= 0 || ~strcmpi(strtrim(out_head), expected_head)
    error('measurement_ii_B_O8:head', 'Repository HEAD is %s, expected %s.', strtrim(out_head), expected_head);
end
pre_lines{end+1} = sprintf('repository %s HEAD %s: OK', root, lower(expected_head));
[st_stat, out_stat] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st_stat ~= 0 || ~isempty(strtrim(out_stat))
    error('measurement_ii_B_O8:status', 'git status of openfast_q1 is not empty: %s', strtrim(out_stat));
end
pre_lines{end+1} = 'git status --porcelain -- openfast_q1: empty: OK';
for k = 1:size(EXPECT, 1)
    file_k = fullfile(root, strrep(EXPECT{k, 1}, '/', filesep));
    sha_k = o8_sha256(file_k);
    if ~strcmp(sha_k, EXPECT{k, 2})
        error('measurement_ii_B_O8:sha', '%s has SHA-256 %s, expected %s.', EXPECT{k, 1}, sha_k, EXPECT{k, 2});
    end
    pre_lines{end+1} = sprintf('%s %s: OK', EXPECT{k, 1}, sha_k); %#ok<AGROW>
end
for k = 1:size(TOOLBOX, 1)
    file_k = fullfile(matlabroot, strrep(TOOLBOX{k, 1}, '/', filesep));
    try
        sha_k = o8_sha256(file_k);
        if strcmp(sha_k, TOOLBOX{k, 2}), same_k = 'same as spec'; else, same_k = 'DIFFERENT from spec'; end
    catch ME
        sha_k = 'not read';
        same_k = getReport(ME, 'extended', 'hyperlinks', 'off');
    end
    pre_lines{end+1} = sprintf('recorded only: %s %s (%s)', TOOLBOX{k, 1}, sha_k, same_k); %#ok<AGROW>
end
end
