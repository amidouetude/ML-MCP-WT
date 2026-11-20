function SS = e5_sessions()
%E5_SESSIONS  The five sessions of the E5 campaign (spec_E5 amendment 5, framework_decisions.
%amendment_5.S1): whole families in the order of D12, fixed here and never passed by hand.
%
%   SS = e5_sessions()
%
%   SS(k).session     k = 1 to 5
%   SS(k).families    cell of family names of session k: {MLP, C1}, {C2}, {C3}, {C4, C5}, {C6}
%   SS(k).planned_h   planned scaled time of S1 (h): 7.69, 8.96, 8.80, 9.89, 5.30
%   SS(k).raw_h       planned unscaled time of S1 (h): 5.13, 5.97, 5.87, 6.59, 3.53
%   The planned times are estimates and not bounds (S1); no ceiling per session (S5).

SS = struct('session', {1, 2, 3, 4, 5}, ...
            'families', {{'MLP', 'C1'}, {'C2'}, {'C3'}, {'C4', 'C5'}, {'C6'}}, ...
            'planned_h', {7.69, 8.96, 8.80, 9.89, 5.30}, ...
            'raw_h', {5.13, 5.97, 5.87, 6.59, 3.53});
end
