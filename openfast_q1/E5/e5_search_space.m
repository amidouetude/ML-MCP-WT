function SP = e5_search_space(C)
%E5_SEARCH_SPACE  Lexicographic enumeration of the search space of each drawn family and the draws of
%amendment_3.D1 (d) (search, E5 l.37; amendment 2; amendment_4.A8, A16).
%
%   SP = e5_search_space(C)        C = e5_campaign_settings()
%
%   For each family in the order MLP, C1, C2, C3, C5: the hyperparameters of the family in the order
%   history L, number of hidden layers, width, kernel size, channels, hidden size, LSTM layers,
%   learning rate, each with its values in increasing order; the enumeration is lexicographic (the
%   first hyperparameter varies slowest); C3 without (hidden size 128, 2 layers) (amendment 2);
%   then rng(C.search_seed, 'twister') reset, p = randperm(n) over the n configurations and the first
%   C.n_draw indices of p kept, in the order of p (reading P4b-1).
%   SP(f).family, SP(f).names (cell), SP(f).values (n x k double), SP(f).drawn (1 x C.n_draw indices
%   into the rows of values). The state of the global random stream is saved and restored.

fam_list = {'MLP', 'C1', 'C2', 'C3', 'C5'};
lr_values = [3e-4 1e-3];
rng_saved = rng;
restore_rng = onCleanup(@() rng(rng_saved));
SP = struct('family', {}, 'names', {}, 'values', {}, 'drawn', {});
for f = 1:numel(fam_list)
    switch fam_list{f}
        case {'MLP', 'C5'}
            names = {'n_hidden', 'n_units', 'lr'};
            grids = {1:3, [16 32 64 128], lr_values};
        case 'C1'
            names = {'L', 'n_hidden', 'n_units', 'lr'};
            grids = {[4 8 16 34], 1:3, [16 32 64 128], lr_values};
        case 'C2'
            names = {'L', 'kernel', 'channels', 'lr'};
            grids = {[4 8], [2 3], [16 32 64], lr_values};
        otherwise
            names = {'L', 'hidden', 'n_layers', 'lr'};
            grids = {[4 8 16 34], [16 32 64 128], [1 2], lr_values};
    end
    values = lex_grid(grids);
    if strcmp(fam_list{f}, 'C3')
        values = values(~(values(:, 2) == 128 & values(:, 3) == 2), :);
    end
    rng(C.search_seed, 'twister');
    perm = randperm(size(values, 1));
    SP(end+1) = struct('family', fam_list{f}, 'names', {names}, 'values', values, 'drawn', perm(1:C.n_draw)); %#ok<AGROW>
end
delete(restore_rng);
end

function values = lex_grid(grids)
% every combination, the first grid varying slowest
n_par = numel(grids);
counts = cellfun(@numel, grids);
values = zeros(prod(counts), n_par);
for row = 1:prod(counts)
    rem_index = row - 1;
    for j = n_par:-1:1
        values(row, j) = grids{j}(mod(rem_index, counts(j)) + 1);
        rem_index = floor(rem_index/counts(j));
    end
end
end
