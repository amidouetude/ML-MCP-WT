function analyse_E2_V4(OUT, G, RUNS, prev_ok)
%ANALYSE_E2_V4  Criterion, metrics and exit decision of E2 V4 (openfast_q1/E2/spec_E2.yaml,
%validation.V4_turbulent_segments and validation.exit_decision, amendment 6).
%
%   analyse_E2_V4(OUT, G, RUNS, prev_ok)    called once by run_E2_V4 at the end of the campaign
%
%   G: one row per segment (run_E2_V4); RUNS: the 21 runs and their status; prev_ok: true when V0-V2
%   and V3 are SATISFAIT (checked by run_E2_V4 before the start).
%   Rules (author decision of 22/10/2026, R1-R5):
%   R1  the criterion is judged per mean wind speed, the 3 seeds pooled (400 segments per run, 1200
%       per speed): (a) passes if median(e_max) <= 2 % and P95(e_max) <= 5 % of rated rotor speed
%       (validation.V4_turbulent_segments.pass); (b) reported only. A speed with a run not read, or
%       with a number of segments other than 1200, fails (a) and is listed as not evaluated.
%   R2  median: MATLAB median; P95: nearest rank, element ceil(0.95 n) of the values sorted in
%       ascending order.
%   R3  e_max, RMSE, MAE and bias of each segment are computed by run_E2_V4 on k = 1..30, as fractions
%       of omega_r_rated (12.1 rpm).
%   R4  a segment with a NaN error (model outside the Cp table domain) counts as a failure: e_max =
%       +Inf in the median and the P95; the number of such segments is reported per speed; RMSE, MAE
%       and bias statistics are computed on the finite segments.
%   R5  exit decision: GO if V0-V2 and V3 are SATISFAIT and V4 (a) passes at the 7 speeds; GO WITH
%       CONDITIONS if V4 (a) fails at some speeds and passes at least one (failing speeds listed);
%       NO-GO if V4 (a) fails at every speed or V0-V3 are not SATISFAIT.
%   metrics (validation.V4_turbulent_segments.metrics): RMSE, MAE, e_max and bias per wind speed,
%   median and P95 over segments, for (a) and (b), pooled and per seed.
%   Writes OUT/V4_per_speed.csv and OUT/verdict_E2_V4.txt.

SPEEDS   = [12 14 16 18 20 22 24];  % m/s, spec_E3 E3b_region3_qualification.mean_speeds (V4_turbulent_segments.data)
N_EXP    = 1200;                    % segments per speed (R1)
MED_PASS = 0.02;                    % validation.V4_turbulent_segments.pass (median e_max)
P95_PASS = 0.05;                    % validation.V4_turbulent_segments.pass (P95 e_max)
CASES    = {'a', 'b'};

[~, ID] = fileparts(OUT);
V = {sprintf('campaign: %s', ID), 'spec: openfast_q1/E2/spec_E2.yaml (validation.V4_turbulent_segments, exit_decision)', ...
     'variant: ii (validation.V3_pitch_steps.variant_rule, retained in Q1-E2-V3-2026-10-22-a)'};
for k = 1:numel(RUNS)
    V{end+1} = sprintf('run %-11s %s, %.1f s', RUNS(k).run, RUNS(k).status, RUNS(k).wall_s); %#ok<AGROW>
end

rows = {};
pass_a = false(size(SPEEDS));
for iu = 1:numel(SPEEDS)
    u = SPEEDS(iu);
    ru = RUNS([RUNS.speed] == u);
    all_read = numel(ru) == 3 && all(strcmp({ru.status}, 'read'));
    gu = G(G.speed == u, :);
    seeds = unique(gu.seed)';
    groups = [{'all'}, arrayfun(@(s) sprintf('S%d', s), seeds, 'UniformOutput', false)];
    for ig = 1:numel(groups)
        if ig == 1, sel = true(height(gu), 1); else, sel = gu.seed == seeds(ig - 1); end
        r = struct('speed', u, 'group', groups{ig}, 'n_segments', nnz(sel));
        for c = 1:numel(CASES)
            s = CASES{c};
            em = gu.(['emax_' s])(sel);
            r.(['n_nan_' s]) = nnz(isnan(em));
            em(isnan(em)) = Inf;                                           % R4
            r.(['median_emax_' s]) = median(em);                           % R2
            r.(['p95_emax_' s])    = p95(em);                              % R2
            for m = {'rmse', 'mae', 'bias'}
                v = gu.([m{1} '_' s])(sel);  v = v(isfinite(v));           % R4: finite segments
                r.(['median_' m{1} '_' s]) = median(v);
                r.(['p95_' m{1} '_' s])    = p95(v);
            end
            r.(['ndomain_' s]) = sum(gu.(['ndomain_' s])(sel));
            r.(['nguard_' s])  = sum(gu.(['nguard_' s])(sel));
        end
        if ig == 1
            evaluated = all_read && r.n_segments == N_EXP;                 % R1
            pass_a(iu) = evaluated && r.median_emax_a <= MED_PASS && r.p95_emax_a <= P95_PASS;
            r.evaluated = evaluated;  r.pass_a = pass_a(iu);
        else
            r.evaluated = NaN;  r.pass_a = NaN;                            % criterion judged on the pooled seeds only (R1)
        end
        rows{end+1} = r; %#ok<AGROW>
    end
    r1 = rows{end - numel(groups) + 1};
    V{end+1} = sprintf(['%2d m/s: %d segments (evaluated %d) | (a) median e_max %.5f, P95 e_max %.5f, NaN segments %d -> %s | ' ...
        '(b) median e_max %.5f, P95 e_max %.5f, NaN segments %d (reported only) | (a) median RMSE %.5f, MAE %.5f, bias %.5f, P95 bias %.5f'], ...
        u, r1.n_segments, r1.evaluated, r1.median_emax_a, r1.p95_emax_a, r1.n_nan_a, pf(pass_a(iu)), ...
        r1.median_emax_b, r1.p95_emax_b, r1.n_nan_b, r1.median_rmse_a, r1.median_mae_a, r1.median_bias_a, r1.p95_bias_a); %#ok<AGROW>
end
S = struct2table([rows{:}]', 'AsArray', true);
writetable(S, fullfile(OUT, 'V4_per_speed.csv'), 'Delimiter', ';');

% --- verdict and exit decision (R5) ---------------------------------------------------------------
failing = SPEEDS(~pass_a);
if isempty(failing)
    V{end+1} = 'VERDICT E2 V4: SATISFAIT';
else
    V{end+1} = sprintf('VERDICT E2 V4: NON SATISFAIT (speeds failing: %s m/s)', mat2str(failing));
end
if ~prev_ok || isempty(SPEEDS(pass_a))
    V{end+1} = 'EXIT DECISION E2: NO-GO';
elseif isempty(failing)
    V{end+1} = 'EXIT DECISION E2: GO';
else
    V{end+1} = sprintf('EXIT DECISION E2: GO WITH CONDITIONS (V4 fails at %s m/s)', mat2str(failing));
end
write_lines(fullfile(OUT, 'verdict_E2_V4.txt'), V);
fprintf('%s\n', V{:});
end

% =============================================================================================
function v = p95(x)
% nearest-rank P95: element ceil(0.95 n) of x sorted in ascending order (R2); NaN if x is empty
x = sort(x(:));
if isempty(x), v = NaN; else, v = x(ceil(0.95*numel(x))); end
end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end
