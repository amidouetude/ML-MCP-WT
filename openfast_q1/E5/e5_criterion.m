function [crit, n_failed] = e5_criterion(seg, S)
%E5_CRITERION  Selection criterion of framework_decisions.selection (E5 l.68) on the segments without
%failure: for each speed of S.speeds with at least one segment, the median of e_max (omega_r, %) over
%its segments that did not fail (+Inf if all failed); then the mean over those speeds (reading
%P4b-6). n_failed: the number of failed segments (first key of the ranking).
%
%   [crit, n_failed] = e5_criterion(seg, S)       seg of e5_eval_segments (wind case (a))

failed = logical(seg.failed);
n_failed = nnz(failed);
per_speed = [];
for u = S.speeds
    sel = seg.speed == u;
    if ~any(sel)
        continue
    end
    em = seg.e_max(sel & ~failed);
    if isempty(em)
        per_speed(end+1) = Inf; %#ok<AGROW>
    else
        per_speed(end+1) = median(em); %#ok<AGROW>
    end
end
if isempty(per_speed)
    crit = Inf;
else
    crit = mean(per_speed);
end
end
