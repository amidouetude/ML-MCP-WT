function diag_E3W_loop()
%DIAG_E3W_LOOP  Exploratory diagnostic of the closed loop of E3W W2 (after Q1-E3-WRAP-2026-10-21-c).
%
%   Run ONCE by the author from the repository root, with a single MATLAB session open, after the
%   code review (separate authorisation); never relaunched, even after a crash:
%       >> addpath('openfast_q1/E3');  diag_E3W_loop
%
%   EXPLORATORY: no value of this diagnostic is publishable. Two closed-loop runs of W2 (FAST_SFunc
%   and discon_wrapper, model built here as in run_E3W run_w2), each changing one item only:
%     D-a  case copy by prepare_case_E3 (mode 'sfunc', which runs check_input_refs), then in the
%          .fst of the copy InterpOrder 2 -> 1 (value 2 checked first, exactly one line changed);
%          discon_wrapper called as in run_E3W (records 4, 33, 34 = measured BldPitch1)
%     D-b  case copy by prepare_case_E3 (mode 'sfunc', InterpOrder unchanged = 2); the MATLAB Function
%          block passes to discon_wrapper, as bp1 (records 4, 33, 34), the pitch command returned by
%          the previous DISCON call instead of the measured BldPitch1; first call: measured BldPitch1
%          (DISCON initialises its pitch state from the measured pitch at the first call,
%          DISCON.F90 l.304). discon_wrapper.m is not modified.
%   Refuses to start (error, nothing written) under the conditions of run_E3W: openfast_q1/ not clean
%   in Git; spec_E3W.yaml SHA-256 not SPEC_SHA; DLL, S-function binaries, reference run or r-test
%   .bts differing from its SHA-256 (spec_E3W campaign.depends_on); matlab-toolbox not at TB_COMMIT;
%   output folder already existing.
%   Each case runs once inside try/catch; the failure of D-a does not prevent D-b. Every catch appends
%   getReport(ME, 'extended') to errors_diag2.txt. The report is appended after each case.
%   For each case, compared with the reference run (E3a run1_exe) over the whole run:
%     time of the first |RotSpeed diff| > 0.05 rpm, time of the first |BldPitch1 diff| > 0.05 deg,
%     max |BldPitch1| (case and reference), max |diff| of the channels of
%     spec_E3 E3a_plant_equivalence.compared over the whole run (reported only).
%   Writes in results/Q1-E3-WRAP-DIAG2-<date>-a/: meta_diag2.txt, report_diag2.txt, summary_diag2.csv,
%   errors_diag2.txt (if any catch), Da/ and Db/ (case copy, model, .outb). Writes nothing in the
%   repository, in C:\dev, in openfast_q1/model/ or in the E3W result folders.

SPEC_SHA  = 'a78de8925221565c50f47ef458b60497891e21547d90d048f0cb38cd08bb0d86';   % spec_E3W, amendment 3
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';   % campaign.depends_on.sfunction
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d'};  % campaign.depends_on.sfunction
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
REF_REL   = 'results/Q1-E3-PLANTEQ-2026-10-16-a/run1_exe/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.outb';      % campaign.depends_on.reference_run
REF_SHA   = 'cf07fc77fad277e6730b4de9a7439ca53a27ccb79a3dfe82c11ead60f7e14735';
BTS_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/test/5MW_Baseline/Wind/90m_12mps_twr.bts';             % W2_closed_loop.run (r-test field of E3a)
BTS_SHA   = '0a368181d3dce9bdb9bb8501e395c1a943aed933098ac914334dcfcc0507d4c1';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
DT        = 0.00625;          % s, spec_E3W wrapper.period
TMAX      = 60;               % s, spec_E3W W2_closed_loop.run
TOL_RPM   = 0.05;             % rpm, first-deviation threshold on RotSpeed (supervisor authorisation)
TOL_DEG   = 0.05;             % deg, first-deviation threshold on BldPitch1 (supervisor authorisation)
COMPARED  = {'RotSpeed', 'GenPwr', 'BldPitch1', 'TwrBsMyt', 'RootMyc1'};   % spec_E3 E3a_plant_equivalence.compared
CODE = {'diag_E3W_loop.m', 'discon.h', 'discon_wrapper.m', 'check_input_refs.m', 'prepare_case_E3.m', 'run_E3W.m'};
CASES = {'Da', 'InterpOrder 2 -> 1 in the .fst copy, wrapper input = measured BldPitch1';
         'Db', 'InterpOrder 2 (unchanged), wrapper input = previous pitch command'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals (as run_E3W) ----------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('diag_E3W_loop:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3W.yaml')), SPEC_SHA)
    error('diag_E3W_loop:spec', 'spec_E3W.yaml SHA-256 differs from %s.', SPEC_SHA);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('diag_E3W_loop:binary', '%s SHA-256 differs from spec_E3W campaign.depends_on.sfunction.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('diag_E3W_loop:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
if ~strcmp(sha256_file(abs_(REF_REL)), REF_SHA), error('diag_E3W_loop:ref', 'Reference run SHA-256 differs from %s.', REF_SHA); end
if ~strcmp(sha256_file(abs_(BTS_REL)), BTS_SHA), error('diag_E3W_loop:bts', 'r-test .bts SHA-256 differs from %s.', BTS_SHA); end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('diag_E3W_loop:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E3-WRAP-DIAG2-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('diag_E3W_loop:exists', 'Output folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -------------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s (exploratory, not publishable)', ID), 'after: results/Q1-E3-WRAP-2026-10-21-c (W2 closed loop)', ...
     sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), ...
     sprintf('spec: openfast_q1/E3/spec_E3W.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE{k}, sha256_file(fullfile(ED3, CODE{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('input: %s %s', REF_REL, REF_SHA), ...
         sprintf('input: %s %s', BTS_REL, BTS_SHA), sprintf('matlab_toolbox: %s', TB_COMMIT), ...
         sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
for k = 1:size(CASES, 1), M{end+1} = sprintf('case %s: %s', CASES{k,1}, CASES{k,2}); end %#ok<AGROW>
write_lines(fullfile(OUT, 'meta_diag2.txt'), M);

% --- environment (session only) -----------------------------------------------------------------
addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_diag2.txt');
REP   = fullfile(OUT, 'report_diag2.txt');
write_lines(REP, {sprintf('campaign: %s (exploratory, not publishable)', ID), sprintf('spec: %s', SPEC_SHA)});

% --- reference run ------------------------------------------------------------------------------
try
    [D, N] = ReadFASTbinary(abs_(REF_REL));
    N = strtrim(N(:));
catch ME
    log_error(ERRF, 'reference run', ME);
    append_lines(REP, {['reference run NOT READ (error: ' strrep(ME.message, newline, ' ') '; full report in errors_diag2.txt)'], ...
                       'DIAG2: NOT RUN'});
    finish(ROOT, OUT, {});
    return
end

% --- cases --------------------------------------------------------------------------------------
rows = cell(0, 9);
extra = {};
for k = 1:size(CASES, 1)
    cs = CASES{k,1};
    L = {sprintf('--- case %s: %s (start %s)', cs, CASES{k,2}, stamp())};
    row = {cs, 'error', NaN, NaN, NaN, NaN, NaN, NaN, NaN};
    try
        cdir = fullfile(OUT, cs);
        C = prepare_case_E3(ROOT, cdir, struct('mode', 'sfunc', 'tmax', TMAX, ...
                'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', abs_(BTS_REL), 'bts_sha', BTS_SHA, 'copy_bts', true));
        for j = 1:size(C.refs, 1), extra{end+1} = sprintf('%s input_ref: %s -> %s %s', cs, C.refs{j,1}, strrep(erase(C.refs{j,2}, [OUT filesep]), filesep, '/'), C.refs{j,3}); end %#ok<AGROW>
        h0 = sha256_file(C.fst);
        if strcmp(cs, 'Da')
            set_interp_order(C.fst, '2', '1');
            row{9} = 1;
            extra{end+1} = sprintf('Da fst: InterpOrder 2 -> 1, sha256 %s (manifest) -> %s', h0, sha256_file(C.fst)); %#ok<AGROW>
        else
            set_interp_order(C.fst, '2', '2');                     % check only
            row{9} = 2;
            extra{end+1} = sprintf('Db fst: InterpOrder 2 (unchanged), sha256 %s', h0); %#ok<AGROW>
        end
        [ok_run, wall, err, slx_sha, st] = run_case(C, cs, DT, TMAX, cdir, abs_(DLL_REL), HFILE, ERRF);
        extra{end+1} = sprintf('%s model: %s/E3W_diag_%s.slx %s', cs, cs, cs, slx_sha); %#ok<AGROW>
        for j = 1:numel(st.warnings), extra{end+1} = sprintf('%s warning: %s', cs, st.warnings{j}); end %#ok<AGROW>
        L{end+1} = sprintf('%s run %s; wall %.1f s; %d DISCON calls (wrapper %.2f s), %d warning(s)%s', ...
                           cs, yn(ok_run), wall, st.ncalls, st.wall_s, numel(st.warnings), errtxt(err));
        row(2:4) = {yn(ok_run), st.ncalls, numel(st.warnings)};
        [D2, chk] = read_checked(fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.SFunc.outb'), ok_run, C.channels, ERRF, cs);
        if isempty(chk) && (size(D2, 1) ~= size(D, 1) || max(abs(D2(:,1) - D(:,1))) > DT/100)
            chk = 'output times differ from the reference run';
        end
        if isempty(chk)
            t = D(:,1);
            rs = abs(D2(:, strcmpi(C.channels, 'RotSpeed')) - D(:, strcmpi(N, 'RotSpeed')));
            bp2 = D2(:, strcmpi(C.channels, 'BldPitch1'));  bp1 = D(:, strcmpi(N, 'BldPitch1'));
            row{5} = first_time(t, rs > TOL_RPM);
            row{6} = first_time(t, abs(bp2 - bp1) > TOL_DEG);
            row{7} = max(abs(bp2));  row{8} = max(abs(bp1));
            L{end+1} = sprintf('%s first |RotSpeed diff| > %.2f rpm: %s', cs, TOL_RPM, tstr(row{5}));
            L{end+1} = sprintf('%s first |BldPitch1 diff| > %.2f deg: %s', cs, TOL_DEG, tstr(row{6}));
            L{end+1} = sprintf('%s max |BldPitch1|: %.4f deg (reference %.4f deg)', cs, row{7}, row{8});
            for j = 1:numel(COMPARED)
                d = abs(D2(:, strcmpi(C.channels, COMPARED{j})) - D(:, strcmpi(N, COMPARED{j})));
                L{end+1} = sprintf('%s %-9s max|diff| over 0-%g s: %.4e (reported only)', cs, COMPARED{j}, TMAX, max(d)); %#ok<AGROW>
            end
            L{end+1} = sprintf('%s REPORTED', cs);
        else
            L{end+1} = sprintf('%s STOPPED (%s)', cs, chk);
        end
    catch ME
        if libisloaded('DISCON'), unloadlibrary('DISCON'); end
        log_error(ERRF, ['case ' cs], ME);
        L{end+1} = sprintf('%s ERROR (%s; full report in errors_diag2.txt)', cs, strrep(ME.message, newline, ' ')); %#ok<AGROW>
    end
    rows(end+1, :) = row; %#ok<AGROW>
    append_lines(REP, L);
    fprintf('%s\n', L{:});
end
S = cell2table(rows, 'VariableNames', {'case', 'run', 'ncalls', 'warnings', 't_first_RotSpeed_s', ...
               't_first_BldPitch1_s', 'max_abs_BldPitch1_deg', 'max_abs_BldPitch1_ref_deg', 'interp_order'});
writetable(S, fullfile(OUT, 'summary_diag2.csv'), 'Delimiter', ';');
append_lines(REP, {sprintf('end: %s', stamp())});
finish(ROOT, OUT, extra);
end

% =============================================================================================
function [ok, wall, err, slx_sha, st] = run_case(C, cs, DT, tmax, rd, dll, hfile, errf)
% build the case model (FAST_SFunc + wrapper block), simulate once, final call (as run_E3W run_w2)
mdl = ['E3W_diag_' cs];
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
          'FixedStep', sprintf('%.17g', DT), 'StopTime', sprintf('%.17g', tmax), ...
          'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SignalLogging', 'off');
ix = @(name) find(strcmpi(C.channels, name));
add_block('simulink/User-Defined Functions/S-Function', [mdl '/FAST'], 'FunctionName', 'FAST_SFunc', ...
          'Parameters', sprintf('''%s'', %.17g, 0', C.fst, tmax));
if strcmp(cs, 'Da')
    % wrapper input = measured BldPitch1, as run_E3W
    body = sprintf([ ...
        'c = discon_wrapper(''step'', y(%d), y(%d)*pi/180, y(%d)*pi/30, sqrt(y(%d)^2 + y(%d)^2));\n'], ...
        ix('Time'), ix('BldPitch1'), ix('GenSpeed'), ix('Wind1VelX'), ix('Wind1VelY'));
else
    % D-b: wrapper input = pitch command of the previous DISCON call (first call: measured BldPitch1)
    body = sprintf([ ...
        'persistent last\n' ...
        'if isempty(last), last = y(%d)*pi/180; end\n' ...
        'c = discon_wrapper(''step'', y(%d), last, y(%d)*pi/30, sqrt(y(%d)^2 + y(%d)^2));\n' ...
        'last = c(1);\n'], ...
        ix('BldPitch1'), ix('Time'), ix('GenSpeed'), ix('Wind1VelX'), ix('Wind1VelY'));
end
script = [sprintf([ ...
    'function u = wrap(y)\n' ...
    '%%#codegen\n' ...
    '%% generated by diag_E3W_loop.m, case %s: discon_wrapper at every DT; channel indices from channels.txt\n' ...
    'coder.extrinsic(''discon_wrapper'');\n' ...
    'c = zeros(6, 1);\n'], cs) body sprintf([ ...
    'u = zeros(51, 1);                  %% FAST_Library.h l.72-83\n' ...
    'u(1) = c(2);                       %% generator torque (N-m), wrapper.records_out\n' ...
    'u(2) = c(3);                       %% electrical power (W)\n' ...
    'u(5) = c(1);  u(6) = c(1);  u(7) = c(1);   %% collective pitch command (rad)\n'])];
add_block('simulink/User-Defined Functions/MATLAB Function', [mdl '/wrap']);
rt = sfroot;
m  = rt.find('-isa', 'Simulink.BlockDiagram', 'Name', mdl);
ch = m.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/wrap']);
if numel(ch) ~= 1, error('diag_E3W_loop:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
ch.Script = script;
add_line(mdl, 'FAST/1', 'wrap/1', 'autorouting', 'on');
add_line(mdl, 'wrap/1', 'FAST/1', 'autorouting', 'on');
f = fullfile(rd, [mdl '.slx']);
save_system(mdl, f);
slx_sha = sha256_file(f);
clear('FAST_SFunc');
evalin('base', 'clear OutList');
discon_wrapper('init', dll, hfile);
ok = false;  err = '';
w = tic;
try
    sim(mdl);
    ok = true;
catch ME
    log_error(errf, [cs ' simulation'], ME);
    err = strrep(ME.message, newline, ' ');
end
wall = toc(w);
try
    discon_wrapper('final');                                        % final call after the simulation
catch ME
    log_error(errf, [cs ' final call'], ME);
    err = strtrim([err ' | final call: ' strrep(ME.message, newline, ' ')]);
    if libisloaded('DISCON'), unloadlibrary('DISCON'); end
end
st = discon_wrapper('stats');
close_system(mdl, 0);
clear('FAST_SFunc');
end

function set_interp_order(fst, old, new)
% InterpOrder of the .fst copy: value checked = old, replaced by new; exactly one line changed
L0 = read_lines(fst);
pat = '^(\s*)(\S+)(\s+InterpOrder\s.*)$';
i = find(~cellfun(@isempty, regexp(L0, pat, 'once')));
if numel(i) ~= 1, error('diag_E3W_loop:interp', 'InterpOrder found %d times in %s.', numel(i), fst); end
tok = regexp(L0{i}, pat, 'tokens', 'once');
if ~strcmp(tok{2}, old)
    error('diag_E3W_loop:interp', 'InterpOrder is %s in %s, expected %s.', tok{2}, fst, old);
end
if strcmp(old, new), return, end
L = L0;
L{i} = [tok{1} sprintf('%*s', numel(tok{2}), new) tok{3}];
write_lines(fst, L);
L1 = read_lines(fst);
if numel(L1) ~= numel(L0) || nnz(~strcmp(L1, L0)) ~= 1
    error('diag_E3W_loop:interp', 'The .fst copy does not differ from the original by exactly one line.');
end
end

function [D, chk] = read_checked(outb, ok_run, channels, errf, cs)
% read a .outb and check its OutList and units (spec_E3 channels.verified, channels.units)
D = [];  chk = '';
if ~ok_run || ~exist(outb, 'file'), chk = 'run not completed';  return, end
try
    [D, N, U] = ReadFASTbinary(outb);
catch ME
    log_error(errf, [cs ' read .outb'], ME);
    chk = ['.outb not readable: ' strrep(ME.message, newline, ' ')];  return
end
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
if numel(N) ~= numel(channels) || ~all(strcmpi(N, channels(:)))
    chk = 'OutList written by OpenFAST differs from the expected channel list';  return
end
UNITS = {'GenTq', 'kN-m'; 'GenPwr', 'kW'; 'BlPitchC1', 'deg'; 'BlPitchC2', 'deg'; 'BlPitchC3', 'deg'; ...
         'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'Wind1VelX', 'm/s'; 'BldPitch1', 'deg'};   % spec_E3 channels.units
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if ~strcmp(u{1}, UNITS{k,2})
        chk = sprintf('unit of %s is %s, expected %s', UNITS{k,1}, u{1}, UNITS{k,2});  return
    end
end
if ~all(isfinite(D(:))), chk = 'non-finite outputs'; end
end

function finish(root, out, extra)
c2 = git_clean(root);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(out, 'meta_diag2.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

function t1 = first_time(t, mask)
k = find(mask, 1);
if isempty(k), t1 = NaN; else, t1 = t(k); end
end

function s = tstr(t1)
if isnan(t1), s = 'none'; else, s = sprintf('t = %.5f s', t1); end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, stamp(), getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function s = yn(ok)
if ok, s = 'completed'; else, s = 'error'; end
end

function s = errtxt(e)
if isempty(e), s = ''; else, s = ['; error: ' e]; end
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
