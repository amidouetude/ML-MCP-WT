function M = e5_metrics(seg, S)
%E5_METRICS  Statistics over segments of e5_eval_segments (evaluation_offline.metrics, E5 l.115;
%framework_decisions.selection, per_arm, omega_f, V4_thresholds, E5 l.30, l.46-47, l.50), with the
%rules R1-R4 of analyse_E2_V4b.m: median = MATLAB median; P95 = nearest rank, element ceil(0.95 n)
%of the values sorted in ascending order; a failed segment (seg.failed: non-finite prediction or
%bounded evaluation) counts as e_max = +Inf in the median and the P95 of e_max, and the RMSE, MAE
%and bias statistics are taken over the segments that did not fail.
%
%   M = e5_metrics(seg, S)
%
%   M.table   one row per (group, speed): group 'pooled', 'X0' or 'X3' for each speed of S.speeds,
%             then the bands 'core' (S.core_speeds) and 'transition' (S.transition_speeds), pooled
%             arms (speed = NaN); columns n_segments, n_failed, failure_rate, median_emax, p95_emax,
%             median and p95 of rmse, mae and bias (%, omega_r), median_f_rmse, p95_f_rmse (rad/s),
%             v4_pass (pooled rows only: median_emax <= S.v4_median_pct and p95_emax <=
%             S.v4_p95_pct; reported, not used, E5 l.47)
%   M.score   selection criterion (E5 l.50): mean over S.speeds of the per-speed median of e_max
%             (failed = +Inf) over the segments given; meaningful on the selection subset, wind case
%             (a); NaN if a speed has no segment
%   M.n_failed  number of failed segments (first key of the ranking of E5 l.50)

failed = logical(seg.failed);
arm_all = seg.arm;
rows = {};
for g = {'pooled', 'X0', 'X3'}
    for u = S.speeds
        sel = seg.speed == u;
        if ~strcmp(g{1}, 'pooled')
            sel = sel & strcmp(arm_all, g{1});
        end
        rows{end+1} = stats_row(seg, failed, sel, g{1}, u, S); %#ok<AGROW>
    end
end
rows{end+1} = stats_row(seg, failed, ismember(seg.speed, S.core_speeds), 'core', NaN, S);
rows{end+1} = stats_row(seg, failed, ismember(seg.speed, S.transition_speeds), 'transition', NaN, S);
M.table = struct2table([rows{:}]');
per_speed = zeros(1, numel(S.speeds));
for iu = 1:numel(S.speeds)
    sel = seg.speed == S.speeds(iu);
    em = seg.e_max(sel);
    em(failed(sel)) = Inf;
    if isempty(em)
        per_speed(iu) = NaN;
    else
        per_speed(iu) = median(em);
    end
end
M.per_speed_median_emax = per_speed;
M.score = mean(per_speed);
M.n_failed = nnz(failed);
end

function r = stats_row(seg, failed, sel, group_name, speed, S)
r.group = string(group_name);
r.speed = speed;
r.n_segments = nnz(sel);
r.n_failed = nnz(failed & sel);
r.failure_rate = r.n_failed/max(r.n_segments, 1);
em = seg.e_max(sel);
em(failed(sel)) = Inf;
r.median_emax = med(em);
r.p95_emax = p95(em);
ok = sel & ~failed;
for m = {'rmse', 'mae', 'bias'}
    v = seg.(m{1})(ok);
    r.(['median_' m{1}]) = med(v);
    r.(['p95_' m{1}]) = p95(v);
end
r.median_f_rmse = med(seg.f_rmse(ok));
r.p95_f_rmse = p95(seg.f_rmse(ok));
if strcmp(group_name, 'pooled') && r.n_segments > 0
    r.v4_pass = double(r.median_emax <= S.v4_median_pct && r.p95_emax <= S.v4_p95_pct);
else
    r.v4_pass = NaN;
end
end

function v = med(x)
% MATLAB median; NaN if x is empty
if isempty(x), v = NaN; else, v = median(x); end
end

function v = p95(x)
% nearest-rank P95: element ceil(0.95 n) of x sorted in ascending order (analyse_E2_V4b R2); NaN if empty
x = sort(x(:));
if isempty(x), v = NaN; else, v = x(ceil(0.95*numel(x))); end
end
