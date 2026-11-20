function plan = e5_campaign_plan(C)
%E5_CAMPAIGN_PLAN  The 136 trials of the campaign in their order (amendment_4.A2, A16): families in
%the order of D12; MLP, C1, C2, C3, C5: the drawn configurations of e5_search_space in the order of
%the draw, the seeds C.seeds inside each configuration; C4: the grid of A12, one run each (seed 0);
%C6: C.c6_cfgs in their order, the seeds inside each configuration.
%
%   plan = e5_campaign_plan(C)
%
%   plan(i).trial_id ('<family>_c<cfg_index>_s<seed>'), family, cfg_index (row of the enumeration
%   for the drawn families, row of the grid for C4 and C6), seed, cfg (struct of the trainer)

SP = e5_search_space(C);
plan = struct('trial_id', {}, 'family', {}, 'cfg_index', {}, 'seed', {}, 'cfg', {});
for f = 1:numel(C.families)
    fam = C.families{f};
    switch fam
        case 'C4'
            for g = 1:size(C.c4_grid, 1)
                plan(end+1) = entry(fam, g, 0, struct('sched', C.c4_grid{g, 1}, 'L', C.c4_grid{g, 2})); %#ok<AGROW>
            end
        case 'C6'
            for g = 1:size(C.c6_cfgs, 1)
                for s = C.seeds
                    plan(end+1) = entry(fam, g, s, struct('n_sub', C.c6_cfgs(g, 1), 'n_act', C.c6_cfgs(g, 2))); %#ok<AGROW>
                end
            end
        otherwise
            sp = SP(strcmp({SP.family}, fam));
            for d = sp.drawn
                cfg = cell2struct(num2cell(sp.values(d, :)), sp.names, 2);
                for s = C.seeds
                    plan(end+1) = entry(fam, d, s, cfg); %#ok<AGROW>
                end
            end
    end
end
end

function e = entry(fam, cfg_index, seed, cfg)
e = struct('trial_id', sprintf('%s_c%02d_s%d', fam, cfg_index, seed), 'family', fam, 'cfg_index', cfg_index, ...
           'seed', seed, 'cfg', cfg);
end
