function run_E2_V3b()
%RUN_E2_V3B  Single execution of E2 V3-b, model v2 (openfast_q1/E2/spec_E2.yaml,
%validation.V3_pitch_steps.V3b_model_v2, amendment 7): offline replay of the 6 runs of
%Q1-E2-V3-2026-10-22-a with the rotor-effective wind RtVAvgxh as V (variant 'i'); no OpenFAST,
%Simulink or DISCON run.
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation),
%   never relaunched:
%       >> addpath('openfast_q1/E2');  run_E2_V3b
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; spec_E2.yaml
%   differs from SPEC_E2_SHA; the Cp table differs from CP_SHA; one of the 6 .outb of V3-a differs from
%   its SHA-256 in V3b_model_v2 (copied in full in RUNS below); matlab-toolbox (ReadFASTbinary) is not
%   at TB_COMMIT; the campaign folder already exists.
%
%   Comparison: as analyse_E2_V3.m (validation.V3_pitch_steps.compare), copied, with three changes
%   only (V3b_model_v2): V = RtVAvgxh held over each Ts at its value at the start of the step; one
%   variant 'i', no variant rule; pass for each of the 6 runs: e_max over k = 0..30 <= 0.02 of
%   omega_r_rated (validation.V3_pitch_steps.pass), V3-b SATISFAIT if the 6 runs pass. Unchanged:
%   omega_f rebuilt at every output step from t = 0 with the DISCON filter, model initialised at 60 s
%   with x0 = [RotSpeed(60 s) x pi/30; omega_f(60 s)], k = 0..199 rom_step with BldPitch1 held over
%   each Ts, instants found by index and checked against Time within DT/100, e_max over 10 s reported
%   only, 'includenan', n_domain and n_guard counts.
%   Reported (validation.V3_pitch_steps.reported_only, as V3-a): realised step BlPitchF -
%   BldPitch1(60 s), with BlPitchF taken from the PITCH table of run_E2_V3.m and checked against
%   BldPitch1(70 s) within 1e-4 deg (a difference is reported, not blocking); max |BldPitch1(t) -
%   BldPitch1(60 s)| over 50-60 s; RotSpeed change at 61.5 s and at 70 s; ratio RtVAvgxh / Wind1VelX
%   over 60-70 s.
%   Every catch appends getReport(ME, 'extended') to errors_E2_V3b.txt.
%   Writes in results/Q1-E2-V3-<date>-b/: meta_E2_V3b.txt, verdict_E2_V3b.txt, V3b_runs.csv,
%   V3b_trajectories.mat, errors_E2_V3b.txt if any.

SPEC_E2_SHA = '6c09b3ef2df0d8dade7123caaa56e22c6ce248578518545793a8a44dd2d00515';   % spec_E2, amendment 7
CP_REL    = 'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat';                                % Cp table of V0-V2
CP_SHA    = '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2';
V3A_REL   = 'results/Q1-E2-V3-2026-10-22-a';                                                              % V3b_model_v2
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
% run, speed (m/s), BlPitchF (deg, PITCH table of run_E2_V3.m), .outb SHA-256 (validation.V3_pitch_steps.V3b_model_v2)
RUNS = {'U14_up', 14, '9.5723',  'a0718d8db1664bb2cda652bd26e0431b16a79db31a2651834050a554128f67b8';
        'U14_dn', 14, '7.5723',  '0d104df5f0c3d91a9c4d56301404ef44543577701bf83ed9778ea768ba3db235';
        'U18_up', 18, '15.9124', 'ba2e3917e08922a94c6d1a4a613f91938a1b784af66b8acae5faca471063dff6';
        'U18_dn', 18, '13.9124', 'a96f1ccab3a4f6f0673566ecb8e3db78bfa9a22e15491b38a1d034ae4c0d1fd0';
        'U22_up', 22, '20.8512', '9dacea0820ac4a7a9ce3fa769ea10bda6071c0f4e7fe2f0db7679fd4590f5dd1';
        'U22_dn', 22, '18.8512', '4abc752203580138bb9d8d997a6f4dc6f02b18dff0a38810eaf0f8d70cf17d74'};
CODE = {'run_E2_V3b.m', 'analyse_E2_V3.m', 'rom_params.m', 'rom_rhs.m', 'rom_step.m', 'rom_torque_law.m', 'spec_E2.yaml'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
outb = @(run) fullfile(abs_(V3A_REL), 'runs', run, '5MW_Land_DLL_WTurb', '5MW_Land_DLL_WTurb.SFunc.outb');

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E2_V3b:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED2, 'spec_E2.yaml')), SPEC_E2_SHA)
    error('run_E2_V3b:spec', 'spec_E2.yaml SHA-256 differs from %s.', SPEC_E2_SHA);
end
if ~strcmp(sha256_file(abs_(CP_REL)), CP_SHA), error('run_E2_V3b:cp', 'Cp table SHA-256 differs from %s.', CP_SHA); end
for k = 1:size(RUNS, 1)
    f = outb(RUNS{k,1});
    if ~exist(f, 'file') || ~strcmp(sha256_file(f), RUNS{k,4})
        error('run_E2_V3b:outb', '.outb of %s is missing or differs from %s (V3b_model_v2).', RUNS{k,1}, RUNS{k,4});
    end
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E2_V3b:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E2-V3-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-b'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E2_V3b:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E2/spec_E2.yaml %s', SPEC_E2_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E2/%s %s', CODE{k}, sha256_file(fullfile(ED2, CODE{k}))); end %#ok<AGROW>
M{end+1} = sprintf('input: %s %s (Cp table)', CP_REL, CP_SHA);
for k = 1:size(RUNS, 1), M{end+1} = sprintf('input: %s/runs/%s .outb %s', V3A_REL, RUNS{k,1}, RUNS{k,4}); end %#ok<AGROW>
M = [M, {'model: v2 (amendment 7), V = RtVAvgxh held over each Ts, variant i', ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E2_V3b.txt'), M);

% --- comparison and report --------------------------------------------------------------------
addpath(ED2);  addpath(fullfile(TB_DIR, 'Utilities'));
ERRF  = fullfile(OUT, 'errors_E2_V3b.txt');
extra = {};
try
    compare_v3b(OUT, RUNS, outb, fullfile(abs_(V3A_REL), 'runs'), abs_(CP_REL), ERRF);
catch ME
    log_error(ERRF, 'compare_v3b', ME);
    extra{end+1} = ['comparison: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E2_V3b.txt)'];
end
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E2_V3b.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function compare_v3b(OUT, RUNS, outb, runs_dir, cp_file, errf)
% comparison of analyse_E2_V3.m with V = RtVAvgxh, variant 'i' (V3b_model_v2)
T0      = 60;                   % s, validation.V3_pitch_steps.maneuver (TPitManS) and .compare
DT      = 0.00625;              % s, spec_E3 channels.output_format (DT_Out = DT)
K_PASS  = 30;                   % steps, first 1.5 s at Ts = 0.05 s (validation.V3_pitch_steps.pass)
K_ALL   = 200;                  % steps, 10 s window (reported only)
E_PASS  = 0.02;                 % fraction of rated rotor speed, validation.V3_pitch_steps.pass
VARIANT = 'i';                  % V3b_model_v2
T_PREV  = [50 60];              % s, validation.V3_pitch_steps.reported_only
T_DROT  = [61.5 70];            % s, validation.V3_pitch_steps.reported_only
TOL_F   = 1e-4;                 % deg, BlPitchF check against BldPitch1(70 s) (supervisor specification)

[~, ID] = fileparts(OUT);
p  = rom_params(cp_file);
Ts = p.Ts;
n  = size(RUNS, 1);
S = table('Size', [n 17], 'VariableTypes', [{'string', 'double', 'string'}, repmat({'double'}, 1, 13), {'logical'}], ...
          'VariableNames', {'run', 'speed', 'status', 'BlPitchF_deg', 'BldPitch1_70s_deg', 'realised_step_deg', ...
                            'max_pitch_dev_50_60_deg', 'dRotSpeed_61p5_rpm', 'dRotSpeed_70_rpm', 'ratio_RtVAvgxh_mean', ...
                            'ratio_RtVAvgxh_min', 'ratio_RtVAvgxh_max', 'emax_1p5s', 'emax_10s', 'n_domain', 'n_guard', 'pass'});
TR = struct('run', {}, 't', {}, 'omega_openfast', {}, 'omega_model', {}, 'beta_deg', {}, 'V_rotor', {});
for k = 1:n
    S.run(k) = RUNS{k,1};  S.speed(k) = RUNS{k,2};  S.BlPitchF_deg(k) = str2double(RUNS{k,3});
    S{k, 5:16} = NaN(1, 12);  S.pass(k) = false;
    try
        [D, ch] = read_checked(outb(RUNS{k,1}), fullfile(runs_dir, RUNS{k,1}, 'channels.txt'), RUNS{k,1}, errf);
        col = @(name) D(:, strcmpi(ch, name));
        t = col('Time');
        tk = T0 + (0:K_ALL)'*Ts;                                   % instants 60 + k Ts
        ik = round(tk/DT) + 1;
        if ik(end) > numel(t) || any(abs(t(ik) - tk) > DT/100)
            error('run_E2_V3b:time', 'Output times of %s do not contain the instants 60 + k Ts.', RUNS{k,1});
        end
        rs = col('RotSpeed');  bp = col('BldPitch1');  vx = col('Wind1VelX');  vr = col('RtVAvgxh');
        gs = col('GenSpeed')*pi/30;                                % rpm -> rad/s
        alpha = exp(-DT*p.CornerFreq);                             % DISCON.F90 l.355 (constant DT)
        gsf = zeros(size(gs));  gsf(1) = gs(1);                    % l.303
        for m = 2:numel(gs), gsf(m) = (1 - alpha)*gs(m) + alpha*gsf(m-1); end   % l.360
        om_of = rs(ik)*pi/30;
        om_md = nan(K_ALL + 1, 1);
        x = [rs(ik(1))*pi/30; gsf(ik(1))];
        om_md(1) = x(1);  nd = 0;  ng = 0;
        for q = 1:K_ALL                                            % k = 0..199
            [x, info] = rom_step(x, bp(ik(q)), vr(ik(q)), VARIANT, p);   % V = RtVAvgxh (V3b_model_v2)
            om_md(q + 1) = x(1);  nd = nd + info.n_domain;  ng = ng + info.n_guard;
        end
        e = abs(om_md - om_of)/p.omega_r_rated;
        S.emax_1p5s(k) = max(e(1:K_PASS + 1), [], 'includenan');
        S.emax_10s(k)  = max(e, [], 'includenan');
        S.n_domain(k)  = nd;  S.n_guard(k) = ng;
        S.pass(k) = S.emax_1p5s(k) <= E_PASS;
        i60 = ik(1);  i70 = round(T_DROT(2)/DT) + 1;
        S.BldPitch1_70s_deg(k) = bp(i70);
        S.realised_step_deg(k) = S.BlPitchF_deg(k) - bp(i60);
        sp = t >= T_PREV(1) - DT/2 & t <= T_PREV(2) + DT/2;
        S.max_pitch_dev_50_60_deg(k) = max(abs(bp(sp) - bp(i60)), [], 'includenan');
        S.dRotSpeed_61p5_rpm(k) = rs(round(T_DROT(1)/DT) + 1) - rs(i60);
        S.dRotSpeed_70_rpm(k)   = rs(i70) - rs(i60);
        sw = t >= T0 - DT/2 & t <= T_DROT(2) + DT/2;
        ratio = vr./vx;
        S.ratio_RtVAvgxh_mean(k) = mean(ratio(sw));
        S.ratio_RtVAvgxh_min(k)  = min(ratio(sw), [], 'includenan');
        S.ratio_RtVAvgxh_max(k)  = max(ratio(sw), [], 'includenan');
        S.status(k) = "read";
        TR(end+1) = struct('run', RUNS{k,1}, 't', tk, 'omega_openfast', om_of, 'omega_model', om_md, ...
                           'beta_deg', bp(ik), 'V_rotor', vr(ik)); %#ok<AGROW>
    catch ME
        log_error(errf, ['run ' RUNS{k,1}], ME);
        S.status(k) = "STOPPED: " + string(strrep(ME.message, newline, ' '));
    end
end
writetable(S, fullfile(OUT, 'V3b_runs.csv'), 'Delimiter', ';');
variant = VARIANT;
save(fullfile(OUT, 'V3b_trajectories.mat'), 'TR', 'variant');

V = {sprintf('campaign: %s', ID), 'spec: openfast_q1/E2/spec_E2.yaml (validation.V3_pitch_steps.V3b_model_v2, amendment 7)', ...
     sprintf('model: v2, V = RtVAvgxh held over each Ts, variant %s; cp_table: %s', VARIANT, cp_file)};
for k = 1:n
    if abs(S.BldPitch1_70s_deg(k) - S.BlPitchF_deg(k)) <= TOL_F, fchk = 'BlPitchF = BldPitch1(70 s)';
    else, fchk = sprintf('BlPitchF differs from BldPitch1(70 s) %.4f deg by more than %.0e deg', S.BldPitch1_70s_deg(k), TOL_F); end
    V{end+1} = sprintf(['%-7s %s | BlPitchF %.4f deg (%s), realised step %.4f deg, max |pitch - pitch(60 s)| 50-60 s %.4f deg, ' ...
        'RotSpeed change %.4f rpm at 61.5 s, %.4f rpm at 70 s, RtVAvgxh/Wind1VelX %.4f [%.4f, %.4f]'], ...
        S.run(k), S.status(k), S.BlPitchF_deg(k), fchk, S.realised_step_deg(k), S.max_pitch_dev_50_60_deg(k), ...
        S.dRotSpeed_61p5_rpm(k), S.dRotSpeed_70_rpm(k), S.ratio_RtVAvgxh_mean(k), S.ratio_RtVAvgxh_min(k), ...
        S.ratio_RtVAvgxh_max(k)); %#ok<AGROW>
    V{end+1} = sprintf('        e_max 1.5 s %.5f <= %.2f: %s; e_max 10 s %.5f (reported only); n_domain %g, n_guard %g', ...
                       S.emax_1p5s(k), E_PASS, pf(S.pass(k)), S.emax_10s(k), S.n_domain(k), S.n_guard(k)); %#ok<AGROW>
end
if n == 6 && all(S.pass), verdict = 'SATISFAIT'; else, verdict = 'NON SATISFAIT'; end
V{end+1} = ['VERDICT E2 V3-b: ' verdict];
write_lines(fullfile(OUT, 'verdict_E2_V3b.txt'), V);
fprintf('%s\n', V{:});
end

function [D, N] = read_checked(f, chan_file, run, errf)
% read a .outb and check its OutList against channels.txt of the V3-a case and the units used
try
    [D, N, U] = ReadFASTbinary(f);
catch ME
    log_error(errf, [run ' read .outb'], ME);
    rethrow(ME);
end
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
ch = read_lines(chan_file);
if numel(N) ~= numel(ch) || ~all(strcmpi(N, ch(:)))
    error('run_E2_V3b:outlist', 'OutList of %s differs from %s.', f, chan_file);
end
UNITS = {'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'BldPitch1', 'deg'; 'Wind1VelX', 'm/s'; 'RtVAvgxh', 'm/s'};
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if numel(u) ~= 1 || ~strcmp(u{1}, UNITS{k,2})
        error('run_E2_V3b:units', 'Channel %s not found once with unit %s in %s.', UNITS{k,1}, UNITS{k,2}, f);
    end
end
if isempty(D), error('run_E2_V3b:empty', 'Empty .outb: %s.', f); end
end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
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
