function run_E2_V4()
%RUN_E2_V4  Single execution of E2 V4, turbulent segments, offline on the runs of E3b-d
%(openfast_q1/E2/spec_E2.yaml, validation.V4_turbulent_segments, amendment 6; no OpenFAST run).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E2');  run_E2_V4
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; spec_E2.yaml
%   differs from SPEC_E2_SHA; the Cp table differs from CP_SHA; the V0-V2 verdict differs from V02_SHA
%   or lacks 'OVERALL V0-V2: SATISFAIT'; the V3 verdict differs from V3_SHA or lacks 'retained: ii' or
%   'VERDICT E2 V3: SATISFAIT' (validation.V3_pitch_steps.variant_rule; author decision of 22/10/2026,
%   R6); summary_E3b.csv of E3b-d differs from SUM_SHA or does not list exactly the 21 runs rep = 1;
%   one of the 21 .outb used differs from its outb_sha256 in summary_E3b.csv; matlab-toolbox
%   (ReadFASTbinary) is not at TB_COMMIT; the campaign folder already exists.
%
%   Steps, each run once, never retried:
%     runs    for each of the 21 runs of Q1-E3-QUAL-2026-10-22-d (repetition excluded,
%             validation.V4_turbulent_segments.data), inside try/catch: .outb read with ReadFASTbinary,
%             OutList checked against runs/<run>/channels.txt of the case and units checked (RotSpeed and
%             GenSpeed in rpm, BldPitch1 in deg, Wind1VelX in m/s); omega_f rebuilt at every output step
%             from t = 0 from GenSpeed (rad/s) with the DISCON filter of validation.V3_pitch_steps.compare;
%             400 segments of T_H = 1.5 s starting at 60 + 1.5 j s, j = 0..399
%             (validation.V4_turbulent_segments.protocol); at the start of each segment the model is
%             re-initialised on x0 = [RotSpeed x pi/30; omega_f]; 30 steps of rom_step with variant 'ii'
%             (R6), BldPitch1 held over each Ts at its value at the start of the step; wind (a) Wind1VelX
%             held over each Ts in the same way, (b) Wind1VelX at the start of the segment held over the
%             whole segment; the instants are found by index and checked against Time within DT/100;
%             per segment and per wind case, on k = 1..30 (R3): e = (omega_r model - RotSpeed x pi/30) /
%             omega_r_rated, e_max = max |e| ('includenan'), RMSE, MAE, bias = mean(e), n_domain, n_guard
%     analyse analyse_E2_V4 (R1-R5, inside try/catch)
%   Every catch appends getReport(ME, 'extended') to errors_E2_V4.txt.
%   Writes in results/Q1-E2-V4-<date>-a/: meta_E2_V4.txt, V4_segments.mat, V4_per_speed.csv,
%   verdict_E2_V4.txt, errors_E2_V4.txt if any.

SPEC_E2_SHA = '49468fb0c9185d186419c1f6acd881bee891b546954f095e80519fe293e7b95f';   % spec_E2, amendment 6
CP_REL    = 'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat';                                % Cp table of V0-V2
CP_SHA    = '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2';
V02_REL   = 'results/Q1-E2-ROM-2026-10-16-b/verification/verdict_E2_V0-V2.txt';                           % exit_decision (R5)
V02_SHA   = '0bb467957fb1837ec1b7c1e9710218da0dc95fc17c9449a4c3041fa0a1a46003';
V3_REL    = 'results/Q1-E2-V3-2026-10-22-a/verdict_E2_V3.txt';                                            % variant_rule, exit_decision (R5, R6)
V3_SHA    = '6204b8769d32835e287f1162453574ed866dc5d6ad9664c58b14ff8f8f796c68';
E3_REL    = 'results/Q1-E3-QUAL-2026-10-22-d';                                                            % validation.V4_turbulent_segments.data
SUM_SHA   = '538e67cb3f56c9c549718f72c3020fe27ae5e945a4a524ed753df45edc528d67';                           % summary_E3b.csv of E3b-d
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
VARIANT   = 'ii';                     % retained by V3 (validation.V3_pitch_steps.variant_rule; R6)
T_START   = 60;                       % s, validation.V4_turbulent_segments.data (spec_E3 duration)
T_H       = 1.5;                      % s, spec_E2 nmpc_interface.horizon (amendment 6)
N_SEG     = 400;                      % segments per run, 60 to 660 s (author decision of 22/10/2026, R1)
N_STEP    = 30;                       % Ts steps per segment (T_H / Ts, nmpc_interface.horizon)
DT        = 0.00625;                  % s, spec_E3 channels.output_format (DT_Out = DT)
CODE = {'run_E2_V4.m', 'analyse_E2_V4.m', 'rom_params.m', 'rom_rhs.m', 'rom_step.m', 'rom_torque_law.m', 'spec_E2.yaml'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E2_V4:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED2, 'spec_E2.yaml')), SPEC_E2_SHA)
    error('run_E2_V4:spec', 'spec_E2.yaml SHA-256 differs from %s.', SPEC_E2_SHA);
end
if ~strcmp(sha256_file(abs_(CP_REL)), CP_SHA), error('run_E2_V4:cp', 'Cp table SHA-256 differs from %s.', CP_SHA); end
need_text(abs_(V02_REL), V02_SHA, {'OVERALL V0-V2: SATISFAIT'});
need_text(abs_(V3_REL), V3_SHA, {'retained: ii', 'VERDICT E2 V3: SATISFAIT'});
sum_f = fullfile(abs_(E3_REL), 'summary_E3b.csv');
if ~strcmp(sha256_file(sum_f), SUM_SHA), error('run_E2_V4:summary', 'summary_E3b.csv SHA-256 differs from %s.', SUM_SHA); end
T = readtable(sum_f, 'Delimiter', ';', 'TextType', 'string');
T = T(T.rep == 1, :);                                           % repetition excluded (V4_turbulent_segments.data)
if height(T) ~= 21 || numel(unique(T.run)) ~= 21
    error('run_E2_V4:runs', 'summary_E3b.csv does not list 21 distinct runs with rep = 1.');
end
outb = cell(height(T), 1);
for k = 1:height(T)
    outb{k} = fullfile(abs_(E3_REL), 'runs', char(T.run(k)), '5MW_Land_DLL_WTurb', '5MW_Land_DLL_WTurb.SFunc.outb');
    if ~exist(outb{k}, 'file') || ~strcmp(sha256_file(outb{k}), char(T.outb_sha256(k)))
        error('run_E2_V4:outb', '.outb of %s is missing or differs from outb_sha256 of summary_E3b.csv.', T.run(k));
    end
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E2_V4:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E2-V4-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E2_V4:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E2/spec_E2.yaml %s', SPEC_E2_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E2/%s %s', CODE{k}, sha256_file(fullfile(ED2, CODE{k}))); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s (Cp table)', CP_REL, CP_SHA), sprintf('input: %s %s', V02_REL, V02_SHA), ...
         sprintf('input: %s %s (variant retained: %s)', V3_REL, V3_SHA, VARIANT), ...
         sprintf('input: %s/summary_E3b.csv %s', E3_REL, SUM_SHA)}];
for k = 1:height(T), M{end+1} = sprintf('input: %s/runs/%s .outb %s', E3_REL, T.run(k), T.outb_sha256(k)); end %#ok<AGROW>
M = [M, {sprintf('protocol: %d segments of %.1f s per run from %d s, %d steps of Ts, variant %s, wind cases (a) and (b)', ...
                 N_SEG, T_H, T_START, N_STEP, VARIANT), ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), ...
         sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E2_V4.txt'), M);

% --- environment (session only) ---------------------------------------------------------------
addpath(ED2);  addpath(fullfile(TB_DIR, 'Utilities'));
ERRF = fullfile(OUT, 'errors_E2_V4.txt');
p  = rom_params(abs_(CP_REL));
Ts = p.Ts;                                                       % 0.05 s, nmpc_interface.Ts

% --- segments ---------------------------------------------------------------------------------
nr = height(T);
RUNS = struct('run', cellstr(T.run), 'speed', num2cell(T.speed), 'seed', num2cell(T.seed), 'outb', outb, ...
              'status', 'not read', 'wall_s', NaN);
G = cell(nr, 1);
for k = 1:nr
    w = tic;
    try
        G{k} = segments_of_run(RUNS(k), fullfile(abs_(E3_REL), 'runs', RUNS(k).run, 'channels.txt'), p, ...
                               VARIANT, T_START, T_H, N_SEG, N_STEP, Ts, DT, ERRF);
        RUNS(k).status = 'read';
    catch ME
        log_error(ERRF, ['run ' RUNS(k).run], ME);
        RUNS(k).status = ['error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E2_V4.txt)'];
    end
    RUNS(k).wall_s = toc(w);
    fprintf('%s: %s, %.1f s\n', RUNS(k).run, RUNS(k).status, RUNS(k).wall_s);
end
G = vertcat(G{:});
if isempty(G), G = segments_table(0); end
save(fullfile(OUT, 'V4_segments.mat'), 'G', 'RUNS');

% --- analysis and end -------------------------------------------------------------------------
extra = {};
try
    analyse_E2_V4(OUT, G, RUNS, true);                           % V0-V2 and V3 SATISFAIT: checked above (R5)
catch ME
    log_error(ERRF, 'analyse_E2_V4', ME);
    extra{end+1} = ['analysis: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E2_V4.txt)'];
end
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E2_V4.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function G = segments_of_run(r, chan_file, p, variant, t_start, t_h, n_seg, n_step, Ts, DT, errf)
% the n_seg segments of one run, wind cases (a) and (b) (validation.V4_turbulent_segments.protocol)
[D, N] = read_checked(r, chan_file, errf);
col = @(name) D(:, strcmpi(N, name));
t  = col('Time');  rs = col('RotSpeed');  bp = col('BldPitch1');  vx = col('Wind1VelX');
gs = col('GenSpeed')*pi/30;                                      % rpm -> rad/s
alpha = exp(-DT*p.CornerFreq);                                   % Alpha (DISCON.F90 l.355, constant DT; V3_pitch_steps.compare)
gsf = zeros(size(gs));  gsf(1) = gs(1);                          % initial GenSpeedF = first GenSpeed (l.303)
for m = 2:numel(gs), gsf(m) = (1 - alpha)*gs(m) + alpha*gsf(m-1); end   % l.360
G = segments_table(n_seg);
G.run(:) = string(r.run);  G.speed(:) = r.speed;  G.seed(:) = r.seed;
for j = 0:n_seg-1
    t0 = t_start + t_h*j;
    tk = t0 + (0:n_step)'*Ts;                                    % instants t0 + k Ts, k = 0..30
    ik = round(tk/DT) + 1;
    if ik(end) > numel(t) || any(abs(t(ik) - tk) > DT/100)
        error('run_E2_V4:time', 'Output times of %s do not contain the instants of the segment starting at %.2f s.', r.run, t0);
    end
    om_of = rs(ik(2:end))*pi/30;                                 % k = 1..30 (R3)
    G.t0(j+1) = t0;
    for c = 1:2                                                  % (a) wind held over each Ts, (b) wind held over the segment
        x = [rs(ik(1))*pi/30; gsf(ik(1))];
        om = zeros(n_step, 1);  nd = 0;  ng = 0;
        for q = 1:n_step
            if c == 1, v = vx(ik(q)); else, v = vx(ik(1)); end
            [x, info] = rom_step(x, bp(ik(q)), v, variant, p);
            om(q) = x(1);  nd = nd + info.n_domain;  ng = ng + info.n_guard;
        end
        e = (om - om_of)/p.omega_r_rated;
        s = char('a' + c - 1);
        G.(['emax_' s])(j+1)    = max(abs(e), [], 'includenan');
        G.(['rmse_' s])(j+1)    = sqrt(mean(e.^2));
        G.(['mae_' s])(j+1)     = mean(abs(e));
        G.(['bias_' s])(j+1)    = mean(e);
        G.(['ndomain_' s])(j+1) = nd;
        G.(['nguard_' s])(j+1)  = ng;
    end
end
end

function G = segments_table(n)
names = {'run', 'speed', 'seed', 't0', 'emax_a', 'rmse_a', 'mae_a', 'bias_a', 'ndomain_a', 'nguard_a', ...
         'emax_b', 'rmse_b', 'mae_b', 'bias_b', 'ndomain_b', 'nguard_b'};
G = table('Size', [n numel(names)], 'VariableTypes', [{'string'}, repmat({'double'}, 1, numel(names) - 1)], ...
          'VariableNames', names);
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
    error('run_E2_V4:outlist', 'OutList of %s differs from %s.', r.outb, chan_file);
end
UNITS = {'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'BldPitch1', 'deg'; 'Wind1VelX', 'm/s'};
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if numel(u) ~= 1 || ~strcmp(u{1}, UNITS{k,2})
        error('run_E2_V4:units', 'Channel %s not found once with unit %s in %s.', UNITS{k,1}, UNITS{k,2}, r.outb);
    end
end
if isempty(D), error('run_E2_V4:empty', 'Empty .outb: %s.', r.outb); end
end

function need_text(f, sha, lines)
% verdict file with its SHA-256 and the required lines (exact substrings)
if ~exist(f, 'file') || ~strcmp(sha256_file(f), sha)
    error('run_E2_V4:verdict', '%s is missing or its SHA-256 differs from %s.', f, sha);
end
s = fileread(f);
for k = 1:numel(lines)
    if ~contains(s, lines{k}), error('run_E2_V4:verdict', '%s does not contain ''%s''.', f, lines{k}); end
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
