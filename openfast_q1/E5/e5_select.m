function sel = e5_select(T)
%E5_SELECT  Selection inside one family (framework_decisions.repetitions and selection, E5 l.36,
%l.68; amendment_4.A19, A14). Pure function.
%
%   sel = e5_select(T)
%
%   T   table, one row per completed trial of the family: cfg_index, seed, n_failed (failed
%       segments, wind case (a)), criterion (e5_criterion; +Inf when undefined), cost (median
%       prediction cost of A14, s; NaN when no model)
%   A19: the repetitions of a configuration ordered by the pair (n_failed, criterion),
%   lexicographically, equal pairs by increasing seed; the median repetition is element ceil(n/2)
%   of that order (the middle one of 3; the single run of C4); its pair is the score of the
%   configuration, its cost the cost of the configuration. Configurations ranked by their score
%   (then by cfg_index). Among the configurations with the smallest n_failed, those whose criterion
%   differs from the best criterion by less than 1 % of it are in a tie (a configuration with an
%   infinite criterion is never in a tie); the retained one has the lowest cost (NaN counted as
%   +Inf), equal costs resolved by the lower criterion, then by the lower cfg_index.
%   sel.configs   table: cfg_index, median_seed, median_row (row of T), n_failed, criterion, cost,
%                 rank, in_tie
%   sel.retained_cfg, sel.retained_seed, sel.retained_row

need = {'cfg_index', 'seed', 'n_failed', 'criterion', 'cost'};
if ~istable(T) || ~all(ismember(need, T.Properties.VariableNames)) || height(T) < 1
    error('e5_select:input', 'T must be a non-empty table with cfg_index, seed, n_failed, criterion, cost.');
end
cfg_list = unique(T.cfg_index, 'sorted');
n_cfg = numel(cfg_list);
median_seed = zeros(n_cfg, 1);  median_row = zeros(n_cfg, 1);
n_failed = zeros(n_cfg, 1);  criterion = zeros(n_cfg, 1);  cost = zeros(n_cfg, 1);
for c = 1:n_cfg
    rows = find(T.cfg_index == cfg_list(c));
    [~, order] = sortrows([T.n_failed(rows), T.criterion(rows), T.seed(rows)], [1 2 3]);
    pick = rows(order(ceil(numel(rows)/2)));
    median_row(c) = pick;
    median_seed(c) = T.seed(pick);
    n_failed(c) = T.n_failed(pick);
    criterion(c) = T.criterion(pick);
    cost(c) = T.cost(pick);
end
[~, rank_order] = sortrows([n_failed, criterion, cfg_list], [1 2 3]);
rank_pos = zeros(n_cfg, 1);
rank_pos(rank_order) = (1:n_cfg)';
min_failed = min(n_failed);
cand = find(n_failed == min_failed);
best_crit = min(criterion(cand));
in_tie = false(n_cfg, 1);
if isfinite(best_crit)
    in_tie(cand) = isfinite(criterion(cand)) & ((criterion(cand) - best_crit) < 0.01*abs(best_crit) | criterion(cand) == best_crit);
else
    in_tie(cand(criterion(cand) == best_crit)) = true;
end
tie = find(in_tie);
cost_tie = cost(tie);
cost_tie(isnan(cost_tie)) = Inf;
[~, k] = sortrows([cost_tie, criterion(tie), cfg_list(tie)], [1 2 3]);
win = tie(k(1));
sel.configs = table(cfg_list, median_seed, median_row, n_failed, criterion, cost, rank_pos, in_tie, ...
                    'VariableNames', {'cfg_index', 'median_seed', 'median_row', 'n_failed', 'criterion', 'cost', 'rank', 'in_tie'});
sel.retained_cfg = cfg_list(win);
sel.retained_seed = median_seed(win);
sel.retained_row = median_row(win);
end
