function diag_E2_V4()
%DIAG_E2_V4  Exploratory diagnostic of the E2 V4 failure (Q1-E2-V4-2026-10-22-a, NON SATISFAIT, NO-GO):
%does the error come mainly from the wind input (hub-point Wind1VelX instead of the disk-averaged
%RtVAvgxh)? EXPLORATORY, NOT PUBLISHABLE, NO THRESHOLD, NO VERDICT (supervisor specification of
%22/10/2026, author choice O1).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation),
%   never relaunched:
%       >> addpath('openfast_q1/E2');  diag_E2_V4
%
%   Protocol
%   - Data: the 21 runs of Q1-E3-QUAL-2026-10-22-d (repetition excluded) and the same 400 segments of
%     1.5 s per run from 60 s as V4 (spec_E2 validation.V4_turbulent_segments.protocol); same instants
%     (found by index, checked against Time within DT/100), same omega_f rebuilt from t = 0 with the
%     DISCON filter (validation.V3_pitch_steps.compare), same re-initialisation x0 = [RotSpeed x pi/30;
%     omega_f] at the start of each segment, BldPitch1 held over each Ts, 30 steps of rom_step.
%   - Arms, one element changed at a time:
%       W1  Wind1VelX, variant 'ii', held over each Ts           control arm: must reproduce V4 (a)
%       W2  RtVAvgxh,  variant 'i',  held over each Ts           disk-averaged wind (hub axes)
%       W3  RtVAvgxh,  variant 'i',  value at the segment start  as W2, wind frozen as V4 (b)
%       P   no model: rotor speed kept at RotSpeed(t0)            persistence reference
%   - Per segment and arm, on k = 1..30 (V4 rule R3): e = (omega_r - RotSpeed x pi/30) / omega_r_rated,
%     e_max = max |e| ('includenan'), RMSE, MAE, bias = mean(e), n_domain, n_guard.
%   - Without model: D = max |RotSpeed - GenSpeed/N| / 12.1 rpm over the output steps of each segment
%     (t0 <= t <= t0 + 1.5 s), N = 97 (rom_params, ElastoDyn GBRatio): drivetrain torsion indicator.
%   - Reported per mean speed and arm, the 3 seeds pooled: median and P95 of e_max (V4 rules R2 and R4:
%     NaN -> +Inf, P95 at rank ceil(0.95 n)), median bias on the finite segments, number of NaN
%     segments, n_domain, n_guard; D median and P95 per speed.
%   - W1 control, reported only: number of segments where e_max of W1 differs from emax_a of
%     results/Q1-E2-V4-2026-10-22-a/V4_segments.mat (same run and t0), and largest absolute difference.
%   - Units checked: RotSpeed and GenSpeed in rpm, BldPitch1 in deg, Wind1VelX and RtVAvgxh in m/s;
%     OutList checked against runs/<run>/channels.txt of the case.
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; spec_E2.yaml, the Cp
%   table, summary_E3b.csv, V4_segments.mat or verdict_E2_V4.txt differ from their SHA-256 below; one of
%   the 21 .outb differs from its outb_sha256 in summary_E3b.csv; matlab-toolbox is not at TB_COMMIT; the
%   campaign folder already exists.
%   Functions needed from run_E2_V4.m are copied here; run_E2_V4.m and rom_*.m are not modified.
%   Every catch appends getReport(ME, 'extended') to errors_diagV4.txt.
%   Writes in results/Q1-E2-DIAGV4-<date>-a/: meta_diagV4.txt, report_diagV4.txt, diagV4_per_speed.csv,
%   diagV4_segments.mat, errors_diagV4.txt if any.

SPEC_E2_SHA = '49468fb0c9185d186419c1f6acd881bee891b546954f095e80519fe293e7b95f';   % spec_E2, amendment 6
CP_REL    = 'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat';
CP_SHA    = '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2';
E3_REL    = 'results/Q1-E3-QUAL-2026-10-22-d';
SUM_SHA   = '538e67cb3f56c9c549718f72c3020fe27ae5e945a4a524ed753df45edc528d67';                           % summary_E3b.csv
V4_REL    = 'results/Q1-E2-V4-2026-10-22-a';
SEG_SHA   = 'b44323219746ad3ca989980ec9e4876510b856290bdc5fb9ea8d8b0757d5ab0c';                           % V4_segments.mat
VER_SHA   = '05895879dd69eaa20ac7a2f39a6ab0713696187d7161ac5c101cf016ce96da56';                           % verdict_E2_V4.txt
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
ARMS      = {'W1', 'Wind1VelX', 'ii', 1;            % name, wind channel, variant, 1 = held over each Ts, 0 = segment start
             'W2', 'RtVAvgxh',  'i',  1;
             'W3', 'RtVAvgxh',  'i',  0};
T_START   = 60;  T_H = 1.5;  N_SEG = 400;  N_STEP = 30;  DT = 0.00625;   % as run_E2_V4.m
RATED_RPM = 12.1;                                                        % rpm, rom_params omega_r_rated
CODE = {'diag_E2_V4.m', 'run_E2_V4.m', 'rom_params.m', 'rom_rhs.m', 'rom_step.m', 'rom_torque_law.m', 'spec_E2.yaml'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('diag_E2_V4:dirty', 'openfast_q1/ is not clean in Git.'); end
need_sha(fullfile(ED2, 'spec_E2.yaml'), SPEC_E2_SHA);
need_sha(abs_(CP_REL), CP_SHA);
sum_f = fullfile(abs_(E3_REL), 'summary_E3b.csv');
need_sha(sum_f, SUM_SHA);
need_sha(fullfile(abs_(V4_REL), 'V4_segments.mat'), SEG_SHA);
need_sha(fullfile(abs_(V4_REL), 'verdict_E2_V4.txt'), VER_SHA);
T = readtable(sum_f, 'Delimiter', ';', 'TextType', 'string');
T = T(T.rep == 1, :);
if height(T) ~= 21 || numel(unique(T.run)) ~= 21
    error('diag_E2_V4:runs', 'summary_E3b.csv does not list 21 distinct runs with rep = 1.');
end
outb = cell(height(T), 1);
for k = 1:height(T)
    outb{k} = fullfile(abs_(E3_REL), 'runs', char(T.run(k)), '5MW_Land_DLL_WTurb', '5MW_Land_DLL_WTurb.SFunc.outb');
    if ~exist(outb{k}, 'file') || ~strcmp(sha256_file(outb{k}), char(T.outb_sha256(k)))
        error('diag_E2_V4:outb', '.outb of %s is missing or differs from outb_sha256 of summary_E3b.csv.', T.run(k));
    end
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('diag_E2_V4:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E2-DIAGV4-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('diag_E2_V4:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s (exploratory, not publishable, no threshold, no verdict)', ID), sprintf('head: %s', strtrim(head)), ...
     'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E2/spec_E2.yaml %s', SPEC_E2_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E2/%s %s', CODE{k}, sha256_file(fullfile(ED2, CODE{k}))); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s (Cp table)', CP_REL, CP_SHA), sprintf('input: %s/summary_E3b.csv %s', E3_REL, SUM_SHA), ...
         sprintf('input: %s/V4_segments.mat %s', V4_REL, SEG_SHA), sprintf('input: %s/verdict_E2_V4.txt %s', V4_REL, VER_SHA)}];
for k = 1:height(T), M{end+1} = sprintf('input: %s/runs/%s .outb %s', E3_REL, T.run(k), T.outb_sha256(k)); end %#ok<AGROW>
M = [M, {'arms: W1 Wind1VelX ii held over Ts (control); W2 RtVAvgxh i held over Ts; W3 RtVAvgxh i at segment start; P persistence; D torsion indicator', ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_diagV4.txt'), M);

% --- environment and segments -----------------------------------------------------------------
addpath(ED2);  addpath(fullfile(TB_DIR, 'Utilities'));
ERRF = fullfile(OUT, 'errors_diagV4.txt');
p = rom_params(abs_(CP_REL));
RUNS = struct('run', cellstr(T.run), 'speed', num2cell(T.speed), 'seed', num2cell(T.seed), 'outb', outb, ...
              'status', 'not read', 'wall_s', NaN);
G = cell(height(T), 1);
for k = 1:height(T)
    w = tic;
    try
        G{k} = segments_of_run(RUNS(k), fullfile(abs_(E3_REL), 'runs', RUNS(k).run, 'channels.txt'), p, ARMS, ...
                               T_START, T_H, N_SEG, N_STEP, DT, RATED_RPM, ERRF);
        RUNS(k).status = 'read';
    catch ME
        log_error(ERRF, ['run ' RUNS(k).run], ME);
        RUNS(k).status = ['error: ' strrep(ME.message, newline, ' ') ' (full report in errors_diagV4.txt)'];
    end
    RUNS(k).wall_s = toc(w);
    fprintf('%s: %s, %.1f s\n', RUNS(k).run, RUNS(k).status, RUNS(k).wall_s);
end
G = vertcat(G{:});
if isempty(G), G = segments_table(0, ARMS); end
save(fullfile(OUT, 'diagV4_segments.mat'), 'G', 'RUNS');

% --- report -----------------------------------------------------------------------------------
extra = {};
try
    report(OUT, G, RUNS, ARMS, fullfile(abs_(V4_REL), 'V4_segments.mat'));
catch ME
    log_error(ERRF, 'report', ME);
    extra{end+1} = ['report: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_diagV4.txt)'];
end
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_diagV4.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function G = segments_of_run(r, chan_file, p, arms, t_start, t_h, n_seg, n_step, DT, rated_rpm, errf)
% the n_seg segments of one run for every arm (segments and model drive as run_E2_V4.m)
[D, N] = read_checked(r, chan_file, errf);
col = @(name) D(:, strcmpi(N, name));
t  = col('Time');  rs = col('RotSpeed');  bp = col('BldPitch1');  gr = col('GenSpeed');
gs = gr*pi/30;                                                   % rpm -> rad/s
alpha = exp(-DT*p.CornerFreq);                                   % DISCON.F90 l.355 (V3_pitch_steps.compare)
gsf = zeros(size(gs));  gsf(1) = gs(1);                          % l.303
for m = 2:numel(gs), gsf(m) = (1 - alpha)*gs(m) + alpha*gsf(m-1); end   % l.360
wind = cellfun(col, arms(:,2), 'UniformOutput', false);          % wind channel of each arm
G = segments_table(n_seg, arms);
G.run(:) = string(r.run);  G.speed(:) = r.speed;  G.seed(:) = r.seed;
Ts = p.Ts;
for j = 0:n_seg-1
    t0 = t_start + t_h*j;
    tk = t0 + (0:n_step)'*Ts;
    ik = round(tk/DT) + 1;
    if ik(end) > numel(t) || any(abs(t(ik) - tk) > DT/100)
        error('diag_E2_V4:time', 'Output times of %s do not contain the instants of the segment starting at %.2f s.', r.run, t0);
    end
    om_of = rs(ik(2:end))*pi/30;                                 % k = 1..30
    G.t0(j+1) = t0;
    for a = 1:size(arms, 1)
        vw = wind{a};
        x = [rs(ik(1))*pi/30; gsf(ik(1))];
        om = zeros(n_step, 1);  nd = 0;  ng = 0;
        for q = 1:n_step
            if arms{a,4} == 1, v = vw(ik(q)); else, v = vw(ik(1)); end
            [x, info] = rom_step(x, bp(ik(q)), v, arms{a,3}, p);
            om(q) = x(1);  nd = nd + info.n_domain;  ng = ng + info.n_guard;
        end
        G = put_metrics(G, j+1, arms{a,1}, (om - om_of)/p.omega_r_rated, nd, ng);
    end
    G = put_metrics(G, j+1, 'P', (rs(ik(1))*pi/30 - om_of)/p.omega_r_rated, 0, 0);   % persistence
    sel = ik(1):ik(end);                                         % output steps t0 <= t <= t0 + T_H
    G.D(j+1) = max(abs(rs(sel) - gr(sel)/p.N))/rated_rpm;        % torsion indicator (rpm / rpm)
end
end

function G = put_metrics(G, i, a, e, nd, ng)
G.(['emax_' a])(i)    = max(abs(e), [], 'includenan');
G.(['rmse_' a])(i)    = sqrt(mean(e.^2));
G.(['mae_' a])(i)     = mean(abs(e));
G.(['bias_' a])(i)    = mean(e);
G.(['ndomain_' a])(i) = nd;
G.(['nguard_' a])(i)  = ng;
end

function G = segments_table(n, arms)
names = {'run', 'speed', 'seed', 't0'};
for a = [arms(:,1)', {'P'}]
    names = [names, strcat({'emax_', 'rmse_', 'mae_', 'bias_', 'ndomain_', 'nguard_'}, a{1})]; %#ok<AGROW>
end
names = [names, {'D'}];
G = table('Size', [n numel(names)], 'VariableTypes', [{'string'}, repmat({'double'}, 1, numel(names) - 1)], ...
          'VariableNames', names);
end

function report(OUT, G, RUNS, arms, v4_seg)
% per-speed statistics (3 seeds pooled), W1 control; no threshold, no verdict
[~, ID] = fileparts(OUT);
V = {sprintf('campaign: %s (exploratory, not publishable, no threshold, no verdict)', ID), ...
     'values: fractions of rated rotor speed (12.1 rpm); median and P95 over segments (V4 rules R2, R4)'};
for k = 1:numel(RUNS), V{end+1} = sprintf('run %-11s %s, %.1f s', RUNS(k).run, RUNS(k).status, RUNS(k).wall_s); end %#ok<AGROW>
% W1 control against V4 (a)
S4 = load(v4_seg, 'G');  G4 = S4.G;
[ok, i4] = ismember(strcat(G.run, "|", string(G.t0)), strcat(G4.run, "|", string(G4.t0)));
d = nan(height(G), 1);  d(ok) = G.emax_W1(ok) - G4.emax_a(i4(ok));
same = (isnan(G.emax_W1(ok)) & isnan(G4.emax_a(i4(ok)))) | d(ok) == 0;
V{end+1} = sprintf('W1 control: %d segments matched to V4_segments.mat of %d; %d with e_max different from emax_a; largest |difference| %.3g', ...
                   nnz(ok), height(G), nnz(~same), max(abs(d(ok)), [], 'omitnan'));
arm_names = [arms(:,1)', {'P'}];
rows = {};
for u = unique(G.speed)'
    gu = G(G.speed == u, :);
    for a = arm_names
        em = gu.(['emax_' a{1}]);  nn = nnz(isnan(em));  em(isnan(em)) = Inf;
        b  = gu.(['bias_' a{1}]);  b = b(isfinite(b));
        r = struct('speed', u, 'arm', a{1}, 'n_segments', height(gu), 'median_emax', median(em), 'p95_emax', p95(em), ...
                   'median_bias', median(b), 'n_nan', nn, 'ndomain', sum(gu.(['ndomain_' a{1}])), ...
                   'nguard', sum(gu.(['nguard_' a{1}])), 'D_median', median(gu.D), 'D_p95', p95(gu.D));
        rows{end+1} = r; %#ok<AGROW>
        V{end+1} = sprintf('%2d m/s %-2s: median e_max %.5f, P95 e_max %.5f, median bias %+.5f, NaN segments %d, n_domain %g, n_guard %g (%d segments)', ...
                           u, a{1}, r.median_emax, r.p95_emax, r.median_bias, nn, r.ndomain, r.nguard, r.n_segments); %#ok<AGROW>
    end
    V{end+1} = sprintf('%2d m/s D : median %.5f, P95 %.5f (max |RotSpeed - GenSpeed/N| / 12.1 rpm per segment)', ...
                       u, median(gu.D), p95(gu.D)); %#ok<AGROW>
end
writetable(struct2table([rows{:}]', 'AsArray', true), fullfile(OUT, 'diagV4_per_speed.csv'), 'Delimiter', ';');
write_lines(fullfile(OUT, 'report_diagV4.txt'), V);
fprintf('%s\n', V{:});
end

function v = p95(x)
% nearest-rank P95: element ceil(0.95 n) of x sorted in ascending order (V4 rule R2); NaN if empty
x = sort(x(:));
if isempty(x), v = NaN; else, v = x(ceil(0.95*numel(x))); end
end

function [D, N] = read_checked(r, chan_file, errf)
% read a .outb and check its OutList against channels.txt of the case and the units used
try
    [D, N, U] = ReadFASTbinary(r.outb);
catch ME
    log_error(errf, [r.run ' read .outb'], ME);
    rethrow(ME);
end
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
ch = read_lines(chan_file);
if numel(N) ~= numel(ch) || ~all(strcmpi(N, ch(:)))
    error('diag_E2_V4:outlist', 'OutList of %s differs from %s.', r.outb, chan_file);
end
UNITS = {'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'BldPitch1', 'deg'; 'Wind1VelX', 'm/s'; 'RtVAvgxh', 'm/s'};
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if numel(u) ~= 1 || ~strcmp(u{1}, UNITS{k,2})
        error('diag_E2_V4:units', 'Channel %s not found once with unit %s in %s.', UNITS{k,1}, UNITS{k,2}, r.outb);
    end
end
if isempty(D), error('diag_E2_V4:empty', 'Empty .outb: %s.', r.outb); end
end

function need_sha(f, sha)
if ~exist(f, 'file') || ~strcmp(sha256_file(f), sha)
    error('diag_E2_V4:sha', '%s is missing or its SHA-256 differs from %s.', f, sha);
end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, stamp(), getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function o = git_clean(root)
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', root));
if st ~= 0, o = sprintf('git status failed: %s', o); end
o = strtrim(o);
end

function s = stamp()
s = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function L = read_lines(f)
L = splitlines(fileread(f));
if isempty(L{end}), L(end) = []; end
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function append_lines(f, L)
fid = fopen(f, 'a');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
