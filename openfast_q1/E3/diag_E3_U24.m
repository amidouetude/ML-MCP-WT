function diag_E3_U24()
%DIAG_E3_U24  Exploratory diagnostic DIAG24 of the two 24 m/s runs of Q1-E3-QUAL-2026-10-21-c that failed
%(U24_S31002: tower strike at 0.788 s; U24_S31003: pitch loop divergence from about 0.5 s).
%
%   Run ONCE by the author from the repository root, with a single MATLAB session open, after the
%   code review and a separate authorisation; never relaunched, even after a crash:
%       >> addpath('openfast_q1/E3');  diag_E3_U24
%
%   PROTOCOL (supervisor authorisation of 22/10/2026, reference text; it supersedes any earlier one)
%   - Nature: exploratory, no value is publishable. No threshold, no verdict.
%   - Identifier: Q1-E3-DIAG24-<yyyy-MM-dd>-a, results in results/<ID>/.
%   - Winds: results/Q1-E3-QUAL-2026-10-21-c/wind/U24_S31002.bts and U24_S31003.bts, read in place,
%     not copied; their SHA-256 are checked against wind_manifest.txt (8815d5e5...).
%   - Duration: TMax = 60 s, model value, checked by prepare_case_E3 with tmax 60.
%   - Initial pitch: read in results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv
%     (SHA-256 46bcc041...), row vent_m_s = 24, column beta_eq_deg; stop if sprintf('%.4f') of this
%     value is not 22.0761. The string 22.0761 replaces 0 for BlPitch(1), BlPitch(2), BlPitch(3) in
%     the ElastoDyn copy of the case (old value checked equal to 0, exactly three lines changed,
%     ElastoDyn SHA-256 before and after written in the meta). The ElastoDyn copy is changed after
%     prepare_case_E3, so its entry in case_manifest.txt is the unchanged file.
%   - Arms, per wind; one item changes from an arm to the next one:
%       EXE_P0   openfast_x64.exe, mode 'exe' (PCMode 5, VSContrl 5, DISCON.dll called by ServoDyn),
%                initial pitch 0 deg, ElastoDyn unchanged
%       EXE_PEQ  same path, initial pitch 22.0761 deg
%       O8_PEQ   S-function, mode 'sfunc', num_crctn 1, InterpOrder 2 (model value), initial pitch
%                22.0761 deg, discon_wrapper called at every DT with the measured BldPitch1, Simulink
%                model as run_E3b
%       O8_P0    same as O8_PEQ with initial pitch 0 deg (ElastoDyn unchanged); fourth arm added by
%                the author on 22/10/2026 as a 60-s control of the configuration of E3b-c
%   - Values written in report_diag24.txt and summary_diag24.csv, per case: run completed or
%     stopped, last time of the .outb; stop message (ErrorMessage of sim, or exit code and the last
%     20 lines of run.log); min and max of BldPitch1 (deg); max |BldPitch1 - BlPitchC1| (deg); O8 arms
%     only: max |BldPitch1 - record 45 x 180/pi| (deg) at the same times and the largest change of
%     record 45 in one step (deg); min and max of RotSpeed (rpm) and the first time RotSpeed < 0, or
%     "none"; max of OoPDefl1 (m) and of TTDspFA (m), or "channel absent"; wall time.
%   - Refuses to start (error, nothing written) if openfast_q1/ is not clean in Git; if spec_E3.yaml,
%     spec_E3W.yaml, a binary, the DLL, wind_manifest.txt, a field or the E1 CSV differs from its
%     SHA-256; if the last commit of the wrapper files is not 11f0133; if matlab-toolbox is not at
%     TB_COMMIT; if the output folder exists.
%   - Each case runs once inside try/catch; every catch appends getReport(ME, 'extended') to
%     errors_diag24.txt; the report is appended after each case; the failure of a case does not
%     prevent the next ones.
%   - Meta (meta_diag24.txt): code SHA-256, inputs, start and end, clean_before, clean_after, and the
%     line "after: results/Q1-E3-QUAL-2026-10-21-c".
%   - Writes nothing in the repository, in C:\dev, in openfast_q1/model/ or in the E3b folders.
%   prepare_case_E3.m, check_input_refs.m and discon_wrapper.m are used unchanged; run_exe is copied
%   from run_E3a.m; run_case follows diag_E3b_loop.m.

SPEC_SHA  = '5edbf5084063b0800993fccc3207ed0862baf2c5f6c142fc9d5ef891d85029d0';   % spec_E3, amendment 5
WRAP_SPEC = 'a78de8925221565c50f47ef458b60497891e21547d90d048f0cb38cd08bb0d86';   % spec_E3W
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'openfast_x64.exe',          'dbae80560269c00f4a1f3529b5bb3ffcd111faa6d6791f4cce6dcf321679d924';   % spec_E3 campaign.depends_on.exe
             'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';   % campaign.depends_on.sfunction
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d'};  % campaign.depends_on.sfunction
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
WRAP_COMMIT = '11f0133';                                                                                  % campaign.depends_on.wrapper
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
WIND_REL  = 'results/Q1-E3-QUAL-2026-10-21-c/wind';
MAN_SHA   = '8815d5e58c340a16de3c8ae2768cdcec1b8f65413b515bacc27ab36c518c6494';                             % wind_manifest.txt of E3b-c
WINDS     = {'U24_S31002', 'U24_S31003'};
CSV_REL   = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';
CSV_SHA   = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';
PITCH_STR = '22.0761';        % deg, beta_eq_deg at 24 m/s with four decimals
ARMS      = {'EXE_P0',  'exe',   false;      % name, path, initial pitch from E1
             'EXE_PEQ', 'exe',   true;
             'O8_PEQ',  'sfunc', true;
             'O8_P0',   'sfunc', false};
DT        = 0.00625;          % s, spec_E3W wrapper.period
TMAX      = 60;               % s, model value
CODE = {'diag_E3_U24.m', 'prepare_case_E3.m', 'check_input_refs.m', 'discon_wrapper.m', 'discon.h', 'run_E3a.m', 'run_E3b.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals -------------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('diag_E3_U24:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3.yaml')), SPEC_SHA)
    error('diag_E3_U24:spec', 'spec_E3.yaml SHA-256 differs from %s.', SPEC_SHA);
end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3W.yaml')), WRAP_SPEC)
    error('diag_E3_U24:wrapspec', 'spec_E3W.yaml SHA-256 differs from %s.', WRAP_SPEC);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('diag_E3_U24:binary', '%s SHA-256 differs from %s.', BIN_SHA{k,1}, BIN_SHA{k,2});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('diag_E3_U24:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
[stw, wc] = system(sprintf('git -C "%s" log -1 --format=%%H -- openfast_q1/E3/discon_wrapper.m openfast_q1/E3/discon.h', ROOT));
if stw ~= 0 || ~startsWith(strtrim(wc), WRAP_COMMIT)
    error('diag_E3_U24:wrapper', 'Last commit of the wrapper files is %s, expected %s.', strtrim(wc), WRAP_COMMIT);
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('diag_E3_U24:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
WDIR = abs_(WIND_REL);
MANF = fullfile(WDIR, 'wind_manifest.txt');
if ~strcmp(sha256_file(MANF), MAN_SHA), error('diag_E3_U24:manifest', 'wind_manifest.txt SHA-256 differs from %s.', MAN_SHA); end
ML = read_lines(MANF);
BTS = cell(numel(WINDS), 2);
for k = 1:numel(WINDS)
    i = find(startsWith(ML, [WINDS{k} ' ']));
    if ~isscalar(i), error('diag_E3_U24:manifest', '%s not found once in wind_manifest.txt.', WINDS{k}); end
    tok = regexp(ML{i}, 'bts ([0-9a-f]{64})', 'tokens', 'once');
    if isempty(tok), error('diag_E3_U24:manifest', 'No bts SHA-256 for %s in wind_manifest.txt.', WINDS{k}); end
    BTS(k,:) = {fullfile(WDIR, [WINDS{k} '.bts']), tok{1}};
    if ~strcmp(sha256_file(BTS{k,1}), BTS{k,2})
        error('diag_E3_U24:bts', '%s.bts SHA-256 differs from wind_manifest.txt.', WINDS{k});
    end
end
CSV = abs_(CSV_REL);
if ~strcmp(sha256_file(CSV), CSV_SHA), error('diag_E3_U24:csv', 'C3_C4_par_vent.csv SHA-256 differs from %s.', CSV_SHA); end
beta = read_beta_eq(CSV, '24');
if ~strcmp(sprintf('%.4f', beta), PITCH_STR)
    error('diag_E3_U24:beta', 'beta_eq_deg at 24 m/s is %.10g, which does not round to %s.', beta, PITCH_STR);
end
ID  = ['Q1-E3-DIAG24-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('diag_E3_U24:exists', 'Output folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) ---------------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s (exploratory, not publishable, no threshold, no verdict)', ID), ...
     'after: results/Q1-E3-QUAL-2026-10-21-c', sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_SHA), ...
     sprintf('spec: openfast_q1/E3/spec_E3W.yaml %s', WRAP_SPEC)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE{k}, sha256_file(fullfile(ED3, CODE{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('wrapper: commit %s', strtrim(wc)), ...
         sprintf('input: %s/wind_manifest.txt %s', WIND_REL, MAN_SHA)}];
for k = 1:numel(WINDS), M{end+1} = sprintf('input: %s/%s.bts %s (read in place)', WIND_REL, WINDS{k}, BTS{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s, beta_eq_deg(24 m/s) = %.13g, written as %s', CSV_REL, CSV_SHA, beta, PITCH_STR)}];
for k = 1:size(ARMS, 1), M{end+1} = sprintf('arm %s: path %s, initial pitch %s deg', ARMS{k,1}, ARMS{k,2}, ternary(ARMS{k,3}, PITCH_STR, '0')); end %#ok<AGROW>
M = [M, {sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), ...
         sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_diag24.txt'), M);

% --- environment (session only, as run_E3b) -------------------------------------------------------
addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_diag24.txt');
REP   = fullfile(OUT, 'report_diag24.txt');
write_lines(REP, {sprintf('campaign: %s (exploratory, not publishable, no threshold, no verdict)', ID)});

% --- cases ----------------------------------------------------------------------------------------
rows = cell(0, 17);
extra = {};
for w = 1:numel(WINDS)
    for a = 1:size(ARMS, 1)
        cs = [WINDS{w} '_' ARMS{a,1}];
        L = {sprintf('--- case %s: path %s, initial pitch %s deg (start %s)', cs, ARMS{a,2}, ternary(ARMS{a,3}, PITCH_STR, '0'), stamp())};
        row = {cs, WINDS{w}, ARMS{a,1}, 'error', NaN, '', NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN};
        try
            opt = struct('mode', ARMS{a,2}, 'tmax', TMAX, 'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, ...
                         'bts', BTS{w,1}, 'bts_sha', BTS{w,2}, 'copy_bts', false);
            if strcmp(ARMS{a,2}, 'sfunc'), opt.num_crctn = 1; end       % configuration O8 (spec_E3 amendment 4)
            C = prepare_case_E3(ROOT, fullfile(OUT, cs), opt);
            ed = fullfile(fileparts(C.fst), strrep(get_quoted(C.fst, 'EDFile'), '/', filesep));
            h0 = sha256_file(ed);
            if ARMS{a,3}
                set_blpitch(ed, '0', PITCH_STR);
                extra{end+1} = sprintf('%s ElastoDyn: BlPitch(1-3) 0 -> %s, sha256 %s (manifest) -> %s', cs, PITCH_STR, h0, sha256_file(ed)); %#ok<AGROW>
            else
                set_blpitch(ed, '0', '0');                                  % check only
                extra{end+1} = sprintf('%s ElastoDyn: BlPitch(1-3) 0 (unchanged), sha256 %s', cs, h0); %#ok<AGROW>
            end
            extra{end+1} = sprintf('%s fst: InterpOrder %s, NumCrctn %s, sha256 %s', cs, get_value(C.fst, 'InterpOrder'), ...
                                   get_value(C.fst, 'NumCrctn'), sha256_file(C.fst)); %#ok<AGROW>
            p45 = [];  t45 = [];
            if strcmp(ARMS{a,2}, 'exe')
                [ok, wall, msg] = run_exe(fullfile(BIN_DIR, BIN_SHA{1,1}), C);
                outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.outb');
            else
                [ok, wall, msg, slx_sha, st, t45, p45] = run_case(C, cs, DT, TMAX, abs_(DLL_REL), HFILE, ERRF);
                extra{end+1} = sprintf('%s model: %s/E3diag24.slx %s, %d DISCON calls (wrapper %.2f s)', cs, cs, slx_sha, st.ncalls, st.wall_s); %#ok<AGROW>
                for j = 1:numel(st.warnings), extra{end+1} = sprintf('%s warning: %s', cs, st.warnings{j}); end %#ok<AGROW>
                outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.SFunc.outb');
            end
            row(4:6) = {yn(ok), wall, msg};
            L{end+1} = sprintf('%s run %s; wall %.1f s', cs, yn(ok), wall); %#ok<AGROW>
            if ~isempty(msg), L{end+1} = sprintf('%s stop message: %s', cs, msg); end %#ok<AGROW>
            [D, N, chk] = read_outb(outb, ERRF, cs);
            if ~isempty(chk)
                L{end+1} = sprintf('%s .outb NOT READ (%s)', cs, chk); %#ok<AGROW>
            else
                col = @(name) D(:, strcmpi(N, name));
                t = col('Time');  bp = col('BldPitch1');  pc = col('BlPitchC1');  rs = col('RotSpeed');
                row{7} = t(end);
                row(8:10) = {min(bp), max(bp), max(abs(bp - pc))};
                L{end+1} = sprintf('%s .outb: %d rows, last time %.5f s', cs, numel(t), t(end)); %#ok<AGROW>
                L{end+1} = sprintf('%s BldPitch1 min %.4f deg, max %.4f deg; max |BldPitch1 - BlPitchC1| %.4f deg', cs, row{8}, row{9}, row{10}); %#ok<AGROW>
                if ~isempty(p45)
                    [~, ia, ib] = intersect(round(t/DT), round(t45/DT));
                    row{11} = max(abs(bp(ia) - p45(ib)*180/pi));
                    row{12} = max(abs(diff(p45)))*180/pi;
                    L{end+1} = sprintf('%s max |BldPitch1 - record 45| %.4f deg over %d common times; largest change of record 45 in one step %.4f deg', ...
                                       cs, row{11}, numel(ia), row{12}); %#ok<AGROW>
                end
                row(13:14) = {min(rs), max(rs)};
                kn = find(rs < 0, 1);
                if isempty(kn), tn = 'none'; else, row{15} = t(kn); tn = sprintf('t = %.5f s', t(kn)); end
                L{end+1} = sprintf('%s RotSpeed min %.4f rpm, max %.4f rpm; first RotSpeed < 0: %s', cs, row{13}, row{14}, tn); %#ok<AGROW>
                [row{16}, s16] = chan_max(D, N, 'OoPDefl1');
                [row{17}, s17] = chan_max(D, N, 'TTDspFA');
                L{end+1} = sprintf('%s max OoPDefl1: %s; max TTDspFA: %s', cs, s16, s17); %#ok<AGROW>
                L{end+1} = sprintf('%s REPORTED', cs); %#ok<AGROW>
            end
        catch ME
            if libisloaded('DISCON'), unloadlibrary('DISCON'); end
            log_error(ERRF, ['case ' cs], ME);
            L{end+1} = sprintf('%s ERROR (%s; full report in errors_diag24.txt)', cs, strrep(ME.message, newline, ' ')); %#ok<AGROW>
        end
        row{6} = strrep(strrep(row{6}, newline, ' | '), ';', ',');       % one CSV field
        rows(end+1, :) = row; %#ok<AGROW>
        append_lines(REP, L);
        fprintf('%s\n', L{:});
    end
end
S = cell2table(rows, 'VariableNames', {'case', 'wind', 'arm', 'run', 'wall_s', 'stop_message', 't_end_s', ...
               'BldPitch1_min_deg', 'BldPitch1_max_deg', 'max_abs_BldPitch1_minus_BlPitchC1_deg', ...
               'max_abs_BldPitch1_minus_rec45_deg', 'max_rec45_step_deg', 'RotSpeed_min_rpm', 'RotSpeed_max_rpm', ...
               't_first_RotSpeed_neg_s', 'OoPDefl1_max_m', 'TTDspFA_max_m'});
writetable(S, fullfile(OUT, 'summary_diag24.csv'), 'Delimiter', ';');
append_lines(REP, {sprintf('end: %s', stamp())});
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_diag24.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function [ok, wall, err] = run_exe(exe, C)
% one run of openfast_x64.exe in the case folder; console output to run.log (copied from run_E3a.m);
% on a non-zero exit code, err holds the code and the last 20 lines of run.log
cdir = fileparts(C.fst);
[~, name, ext] = fileparts(C.fst);
w = tic;
st = system(sprintf('cd /d "%s" && "%s" "%s%s" > run.log 2>&1', cdir, exe, name, ext));
wall = toc(w);
ok = st == 0;
if ok
    err = '';
else
    err = sprintf('openfast_x64.exe exit code %d', st);
    lf = fullfile(cdir, 'run.log');
    if exist(lf, 'file')
        R = read_lines(lf);
        R = strtrim(R(max(1, numel(R) - 19):end));
        err = [err '; last 20 lines of run.log: ' strjoin(R', ' | ')];
    end
end
end

function [ok, wall, err, slx_sha, st, t45, p45] = run_case(C, cs, DT, tmax, dll, hfile, errf)
% configuration O8 as run_E3b run_sfunc: discon_wrapper at every DT with the measured BldPitch1;
% sim with CaptureErrors on; the wrapper log is saved and returned whatever the end of the run
mdl = 'E3diag24';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
          'FixedStep', sprintf('%.17g', DT), 'StopTime', sprintf('%.17g', tmax), ...
          'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SignalLogging', 'off');
ix = @(name) find(strcmpi(C.channels, name));
add_block('simulink/User-Defined Functions/S-Function', [mdl '/FAST'], 'FunctionName', 'FAST_SFunc', ...
          'Parameters', sprintf('''%s'', %.17g, 0', C.fst, tmax));
script = sprintf([ ...
    'function [u, c] = wrap(y)\n' ...
    '%%#codegen\n' ...
    '%% generated by diag_E3_U24.m, case %s: discon_wrapper at every DT with the measured BldPitch1\n' ...
    'coder.extrinsic(''discon_wrapper'');\n' ...
    'c = zeros(6, 1);\n' ...
    'c = discon_wrapper(''step'', y(%d), y(%d)*pi/180, y(%d)*pi/30, sqrt(y(%d)^2 + y(%d)^2));\n' ...
    'u = zeros(51, 1);                  %% FAST_Library.h l.72-83\n' ...
    'u(1) = c(2);                       %% generator torque (N-m), wrapper.records_out\n' ...
    'u(2) = c(3);                       %% electrical power (W)\n' ...
    'u(5) = c(1);  u(6) = c(1);  u(7) = c(1);   %% collective pitch command (rad)\n'], ...
    cs, ix('Time'), ix('BldPitch1'), ix('GenSpeed'), ix('Wind1VelX'), ix('Wind1VelY'));
add_block('simulink/User-Defined Functions/MATLAB Function', [mdl '/wrap']);
rt = sfroot;
m  = rt.find('-isa', 'Simulink.BlockDiagram', 'Name', mdl);
ch = m.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/wrap']);
if numel(ch) ~= 1, error('diag_E3_U24:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
ch.Script = script;
add_block('simulink/Sinks/To Workspace', [mdl '/log'], 'VariableName', 'wraplog', ...
          'SaveFormat', 'Structure With Time', 'MaxDataPoints', 'inf', 'Decimation', '1', ...
          'SampleTime', sprintf('%.17g', DT));
add_line(mdl, 'FAST/1', 'wrap/1', 'autorouting', 'on');
add_line(mdl, 'wrap/1', 'FAST/1', 'autorouting', 'on');
add_line(mdl, 'wrap/2', 'log/1', 'autorouting', 'on');
f = fullfile(C.case_dir, [mdl '.slx']);
save_system(mdl, f);
slx_sha = sha256_file(f);
clear('FAST_SFunc');
evalin('base', 'clear OutList');
discon_wrapper('init', dll, hfile);
ok = false;  err = '';  so = [];  t45 = [];  p45 = [];
w = tic;
try
    so = sim(mdl, 'ReturnWorkspaceOutputs', 'on', 'CaptureErrors', 'on');
    em = so.ErrorMessage;
    if isempty(em), ok = true; else, err = strrep(em, newline, ' '); end
catch ME
    log_error(errf, [cs ' simulation'], ME);
    err = strrep(ME.message, newline, ' ');
end
wall = toc(w);
if ~ok && ~isempty(err)
    fid = fopen(errf, 'a');
    fprintf(fid, '===== %s simulation message (%s)\n%s\n', cs, stamp(), err);
    fclose(fid);
end
try
    discon_wrapper('final');                                        % final call after the simulation
catch ME
    log_error(errf, [cs ' final call'], ME);
    err = strtrim([err ' | final call: ' strrep(ME.message, newline, ' ')]);
    if libisloaded('DISCON'), unloadlibrary('DISCON'); end
end
st = discon_wrapper('stats');
if ~isempty(so)
    try
        lg = so.get('wraplog');
        t = lg.time(:);
        c = lg.signals.values;
        if ndims(c) == 3, c = reshape(permute(c, [3 1 2]), size(c, 3), []); end
        cols = {'pitch_command_rad', 'torque_Nm', 'electrical_power_W', 'record45_rad', 'record47_Nm', 'aviFAIL'};   % discon_wrapper step
        save(fullfile(C.case_dir, 'wrapper_log.mat'), 't', 'c', 'cols');
        t45 = t;  p45 = double(c(:, 4));
    catch ME
        log_error(errf, [cs ' wrapper log'], ME);
        err = strtrim([err ' | wrapper log: ' strrep(ME.message, newline, ' ')]);
    end
end
close_system(mdl, 0);
clear('FAST_SFunc');
end

function beta = read_beta_eq(f, speed)
% beta_eq_deg of the row vent_m_s = speed in the E1 CSV (';' separated, header on the first line)
L = read_lines(f);
H = strsplit(strtrim(L{1}), ';');
jv = find(strcmp(H, 'vent_m_s'));  jb = find(strcmp(H, 'beta_eq_deg'));
if ~isscalar(jv) || ~isscalar(jb), error('diag_E3_U24:csvhead', 'Columns vent_m_s and beta_eq_deg not found once in %s.', f); end
hit = {};
for k = 2:numel(L)
    F = strsplit(strtrim(L{k}), ';');
    if numel(F) == numel(H) && strcmp(F{jv}, speed), hit{end+1} = F{jb}; end %#ok<AGROW>
end
if numel(hit) ~= 1, error('diag_E3_U24:csvrow', 'Row vent_m_s = %s found %d times in %s.', speed, numel(hit), f); end
beta = str2double(hit{1});
if ~isfinite(beta), error('diag_E3_U24:csvval', 'beta_eq_deg at %s m/s is not a number.', speed); end
end

function set_blpitch(f, old, new)
% BlPitch(1), BlPitch(2), BlPitch(3) of the ElastoDyn copy: old checked, replaced by new;
% exactly three lines changed when old and new differ (check only when equal)
L0 = read_lines(f);
L = L0;
for b = 1:3
    key = sprintf('BlPitch(%d)', b);
    pat = ['^(\s*)(\S+)(\s+' regexptranslate('escape', key) '\s.*)$'];
    i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
    if numel(i) ~= 1, error('diag_E3_U24:key', '%s found %d times in %s.', key, numel(i), f); end
    tok = regexp(L{i}, pat, 'tokens', 'once');
    if ~strcmp(tok{2}, old), error('diag_E3_U24:value', '%s is %s in %s, expected %s.', key, tok{2}, f, old); end
    L{i} = [tok{1} sprintf('%*s', numel(tok{2}), new) tok{3}];
end
if strcmp(old, new), return, end
write_lines(f, L);
L1 = read_lines(f);
if numel(L1) ~= numel(L0) || nnz(~strcmp(L1, L0)) ~= 3
    error('diag_E3_U24:value', 'The ElastoDyn copy does not differ by exactly three lines.');
end
end

function [v, s] = chan_max(D, N, name)
j = find(strcmpi(N, name));
if ~isscalar(j), v = NaN;  s = 'channel absent';  return, end
v = max(D(:, j));
s = sprintf('%.4f m', v);
end

function [D, N, chk] = read_outb(outb, errf, cs)
% read a .outb, complete or written by OpenFAST at a stop
D = [];  N = {};  chk = '';
if ~exist(outb, 'file'), chk = 'no .outb';  return, end
try
    [D, N] = ReadFASTbinary(outb);
catch ME
    log_error(errf, [cs ' read .outb'], ME);
    chk = ['.outb not readable: ' strrep(ME.message, newline, ' ')];  return
end
N = strtrim(N(:));
need = {'Time', 'BldPitch1', 'BlPitchC1', 'RotSpeed'};
for k = 1:numel(need)
    if nnz(strcmpi(N, need{k})) ~= 1, chk = sprintf('channel %s not found once', need{k});  return, end
end
if isempty(D), chk = 'empty .outb'; end
end

function v = get_value(f, key)
L = read_lines(f);
pat = ['^\s*(\S+)\s+' regexptranslate('escape', key) '\s'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('diag_E3_U24:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
v = tok{1};
end

function v = get_quoted(f, key)
L = read_lines(f);
pat = ['^"([^"]*)"\s+' regexptranslate('escape', key) '\s'];
i = find(~cellfun(@isempty, regexp(L, pat, 'once')));
if numel(i) ~= 1, error('diag_E3_U24:key', '%s found %d times in %s.', key, numel(i), f); end
tok = regexp(L{i}, pat, 'tokens', 'once');
v = tok{1};
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, stamp(), getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function s = yn(ok)
if ok, s = 'completed'; else, s = 'stopped'; end
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
