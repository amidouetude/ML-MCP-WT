function run_E3W()
%RUN_E3W  Single execution of E3W, DISCON called from Simulink (openfast_q1/E3/spec_E3W.yaml).
%
%   Run ONCE by the author from the repository root, with a single MATLAB session open, after the
%   code review (separate authorisation):
%       >> addpath('openfast_q1/E3');  run_E3W
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_E3W.yaml is not SPEC_SHA (adopted spec + amendment 1); the DLL, the S-function binaries,
%   the reference run or the r-test .bts differs from its SHA-256 (spec_E3W campaign.depends_on);
%   matlab-toolbox (ReadFASTbinary) is not at TB_COMMIT; the campaign folder already exists.
%
%   Steps, each run once, never retried:
%     W1  open loop, no OpenFAST (spec_E3W verification.W1_open_loop): the outputs of the reference
%         run are replayed through discon_wrapper at every output step; record 45 (deg) is compared
%         with BlPitchC1 and record 47 (kN-m) with GenTq, at lag 0 (pass) and lag 1 (reported)
%     W2  closed loop, only if W1 was evaluated (spec_E3W verification.W2_closed_loop): case copy in
%         mode 'sfunc' by prepare_case_E3 (which runs check_input_refs), Simulink model built here:
%         FAST_SFunc and one MATLAB Function block calling discon_wrapper at every DT, final call
%         after the simulation; compared with the reference run with the channels, window and
%         metrics of spec_E3 E3a_plant_equivalence; reported only, it does not change W1
%   Writes in results/Q1-E3-WRAP-<date>-a/ (spec_E3W outputs.files): meta_E3W.txt, verdict_E3W.txt,
%   W1_comparison.csv, W2/ (case copy and .outb), metrics_W2.csv, errors_E3W.txt (full error report
%   of every catch). loadlibrary uses its default options (spec_E3W wrapper.library, amendment 2).

SPEC_SHA  = '4872fa54dbb3083553c8ffc742e3a1202e6aaf643827998fde8e0a9c4aef0daa';
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
DT        = 0.00625;          % s, wrapper.period
TMAX      = 60;               % s, W2_closed_loop.run
TOL_PITCH = 1e-3;             % deg, W1_open_loop.pass
TOL_TQ    = 1e-3;             % x max |GenTq|, W1_open_loop.pass
COMPARED  = {'RotSpeed', 'GenPwr', 'BldPitch1', 'TwrBsMyt', 'RootMyc1'};   % spec_E3 E3a_plant_equivalence.compared
WIN       = [10 60];          % s, spec_E3 E3a_plant_equivalence.compared
CODE = {'discon.h', 'discon_wrapper.m', 'check_input_refs.m', 'run_E3W.m', 'prepare_case_E3.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E3W:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3W.yaml')), SPEC_SHA)
    error('run_E3W:spec', 'spec_E3W.yaml SHA-256 differs from %s.', SPEC_SHA);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('run_E3W:binary', '%s SHA-256 differs from spec_E3W campaign.depends_on.sfunction.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('run_E3W:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
if ~strcmp(sha256_file(abs_(REF_REL)), REF_SHA), error('run_E3W:ref', 'Reference run SHA-256 differs from %s.', REF_SHA); end
if ~strcmp(sha256_file(abs_(BTS_REL)), BTS_SHA), error('run_E3W:bts', 'r-test .bts SHA-256 differs from %s.', BTS_SHA); end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E3W:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E3-WRAP-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-b'];   % attempt -a (2026-10-21): library not loaded
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E3W:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {'previous_attempt: results/Q1-E3-WRAP-2026-10-21-a (library not loaded: alias + thunkfilename, see Q1-E3-WRAP-DIAG-2026-10-21-a)', sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E3/spec_E3W.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE{k}, sha256_file(fullfile(ED3, CODE{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('input: %s %s', REF_REL, REF_SHA), ...
         sprintf('input: %s %s', BTS_REL, BTS_SHA), sprintf('matlab_toolbox: %s', TB_COMMIT), ...
         sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E3W.txt'), M);

% --- environment (session only) ---------------------------------------------------------------
addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_E3W.txt');     % full report of every catch
V = {sprintf('campaign: %s', ID), sprintf('spec: %s', SPEC_SHA)};
extra = {};

% --- W1, open loop ----------------------------------------------------------------------------
w1 = 'NOT EVALUATED';
try
    [D, N, U] = ReadFASTbinary(abs_(REF_REL));
    N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
    need = {'Time', 's'; 'BldPitch1', 'deg'; 'GenSpeed', 'rpm'; 'Wind1VelX', 'm/s'; 'Wind1VelY', 'm/s'; ...
            'BlPitchC1', 'deg'; 'GenTq', 'kN-m'};                                % W1_open_loop.inputs, .compared
    col = zeros(1, size(need, 1));
    for k = 1:size(need, 1)
        j = find(strcmpi(N, need{k,1}));
        if ~isscalar(j) || ~strcmp(U{j}, need{k,2})
            error('run_E3W:w1channel', 'Reference channel %s (%s) not found once with this unit.', need{k,1}, need{k,2});
        end
        col(k) = j;
    end
    t = D(:,col(1));  n = numel(t);
    hwv = sqrt(D(:,col(4)).^2 + D(:,col(5)).^2);                                  % record 27
    c = zeros(n, 6);
    discon_wrapper('init', abs_(DLL_REL), HFILE);
    t0 = tic;
    for k = 1:n
        c(k,:) = discon_wrapper('step', t(k), D(k,col(2))*pi/180, D(k,col(3))*pi/30, hwv(k))';
    end
    discon_wrapper('final');
    wall1 = toc(t0);
    s1 = discon_wrapper('stats');
    p45 = c(:,4)*180/pi;  q47 = c(:,5)/1000;                                         % rad -> deg, N-m -> kN-m
    bpc = D(:,col(6));    gtq = D(:,col(7));
    dp0 = abs(p45 - bpc);  dq0 = abs(q47 - gtq);
    dp1 = abs(p45(1:end-1) - bpc(2:end));  dq1 = abs(q47(1:end-1) - gtq(2:end));    % lag 1 (reported)
    tqref = max(abs(gtq));
    T1 = table(t, D(:,col(2)), D(:,col(3)), hwv, p45, bpc, p45 - bpc, q47, gtq, q47 - gtq, c(:,6), ...
        'VariableNames', {'t_s', 'BldPitch1_deg', 'GenSpeed_rpm', 'HorWindV_mps', 'rec45_deg', 'BlPitchC1_deg', ...
                          'dpitch_deg', 'rec47_kNm', 'GenTq_kNm', 'dtorque_kNm', 'aviFAIL'});
    writetable(T1, fullfile(OUT, 'W1_comparison.csv'), 'Delimiter', ';');
    ok1 = max(dp0) <= TOL_PITCH && max(dq0) <= TOL_TQ*tqref;
    if ok1, w1 = 'PASS'; else, w1 = 'FAIL'; end
    V = [V, {sprintf('W1: %d steps, %d DISCON calls (wrapper %.2f s, loop %.2f s), %d warning(s)', n, s1.ncalls, s1.wall_s, wall1, numel(s1.warnings)), ...
             sprintf('W1 lag 0: max |pitch diff| %.3e deg (<= %.0e), max |torque diff| %.3e kN-m (<= %.0e x %.4g = %.3e)', ...
                     max(dp0), TOL_PITCH, max(dq0), TOL_TQ, tqref, TOL_TQ*tqref), ...
             sprintf('W1 lag 1 (reported): max |pitch diff| %.3e deg, max |torque diff| %.3e kN-m', max(dp1), max(dq1)), ...
             ['W1 ' w1]}];
    for k = 1:numel(s1.warnings), extra{end+1} = ['W1 warning: ' s1.warnings{k}]; end %#ok<AGROW>
catch ME
    if libisloaded('DISCON'), unloadlibrary('DISCON'); end
    log_error(ERRF, 'W1', ME);
    V{end+1} = ['W1 NOT EVALUATED (error: ' strrep(ME.message, newline, ' ') '; full report in errors_E3W.txt)'];
end

% --- W2, closed loop (only if W1 was evaluated) -----------------------------------------------
w2 = 'NOT RUN';
if any(strcmp(w1, {'PASS', 'FAIL'}))
    try
        C = prepare_case_E3(ROOT, fullfile(OUT, 'W2'), struct('mode', 'sfunc', 'tmax', TMAX, ...
                'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', abs_(BTS_REL), 'bts_sha', BTS_SHA, 'copy_bts', true));
        for k = 1:size(C.refs, 1), extra{end+1} = sprintf('W2 input_ref: %s -> %s %s', C.refs{k,1}, strrep(erase(C.refs{k,2}, [OUT filesep]), filesep, '/'), C.refs{k,3}); end %#ok<AGROW>
        if ~isempty(C.added), extra{end+1} = ['W2 outlist_additions: ' strjoin(C.added', ', ')]; end
        [ok_run, wall2, err2, slx_sha, s2] = run_w2(C, DT, TMAX, fullfile(OUT, 'W2'), abs_(DLL_REL), HFILE, ERRF);
        extra{end+1} = sprintf('model: W2/E3W_sfunc.slx %s', slx_sha);
        V{end+1} = sprintf('W2: run %s; wall %.1f s; %d DISCON calls (wrapper %.2f s), %d warning(s)%s', ...
                           yn(ok_run), wall2, s2.ncalls, s2.wall_s, numel(s2.warnings), errtxt(err2));
        for k = 1:numel(s2.warnings), extra{end+1} = ['W2 warning: ' s2.warnings{k}]; end %#ok<AGROW>
        [D2, chk] = read_checked(fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.SFunc.outb'), ok_run, C.channels);
        if isempty(chk) && (size(D2, 1) ~= size(D, 1) || max(abs(D2(:,1) - D(:,1))) > DT/100)
            chk = 'output times differ from the reference run';
        end
        if isempty(chk)
            sel = D(:,1) >= WIN(1) - DT/2 & D(:,1) <= WIN(2) + DT/2;
            T2 = table();
            for k = 1:numel(COMPARED)
                x1 = D(sel, strcmpi(N, COMPARED{k}));  x2 = D2(sel, strcmpi(C.channels, COMPARED{k}));
                d = abs(x2 - x1);
                T2 = [T2; table(COMPARED(k), max(d), max(x1) - min(x1), max(d)/(max(x1) - min(x1)), ...
                      mean(d), mean(abs(x1)), mean(d)/mean(abs(x1)), 'VariableNames', {'channel', 'max_abs_diff', ...
                      'range_ref', 'max_rel', 'mean_abs_diff', 'mean_abs_ref', 'mean_rel'})]; %#ok<AGROW>
                V{end+1} = sprintf('W2 %-9s max|diff|/range %.3e, mean|diff|/mean|ref| %.3e (reported only)', ...
                                   COMPARED{k}, T2.max_rel(k), T2.mean_rel(k)); %#ok<AGROW>
            end
            writetable(T2, fullfile(OUT, 'metrics_W2.csv'), 'Delimiter', ';');
            w2 = 'REPORTED';
        else
            w2 = ['STOPPED (' chk ')'];
        end
    catch ME
        if libisloaded('DISCON'), unloadlibrary('DISCON'); end
        log_error(ERRF, 'W2', ME);
        w2 = ['ERROR (' strrep(ME.message, newline, ' ') '; full report in errors_E3W.txt)'];
    end
end
V{end+1} = ['W2 ' w2];
V{end+1} = sprintf('VERDICT E3W: W1 %s, W2 %s', w1, w2);
write_lines(fullfile(OUT, 'verdict_E3W.txt'), V);
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E3W.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
fprintf('%s\n', V{:});
end

% =============================================================================================
function [ok, wall, err, slx_sha, st] = run_w2(C, DT, tmax, rd, dll, hfile, errf)
% build the W2 model (FAST_SFunc + wrapper block), simulate once, final call (W2_closed_loop.run)
mdl = 'E3W_sfunc';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
          'FixedStep', sprintf('%.17g', DT), 'StopTime', sprintf('%.17g', tmax), ...
          'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SignalLogging', 'off');
ix = @(name) find(strcmpi(C.channels, name));
add_block('simulink/User-Defined Functions/S-Function', [mdl '/FAST'], 'FunctionName', 'FAST_SFunc', ...
          'Parameters', sprintf('''%s'', %.17g, 0', C.fst, tmax));
script = sprintf([ ...
    'function u = wrap(y)\n' ...
    '%%#codegen\n' ...
    '%% generated by run_E3W.m: discon_wrapper at every DT (spec_E3W wrapper.period); channel indices from channels.txt\n' ...
    'coder.extrinsic(''discon_wrapper'');\n' ...
    'c = zeros(6, 1);\n' ...
    'c = discon_wrapper(''step'', y(%d), y(%d)*pi/180, y(%d)*pi/30, sqrt(y(%d)^2 + y(%d)^2));\n' ...
    'u = zeros(51, 1);                  %% FAST_Library.h l.72-83\n' ...
    'u(1) = c(2);                       %% generator torque (N-m), wrapper.records_out\n' ...
    'u(2) = c(3);                       %% electrical power (W)\n' ...
    'u(5) = c(1);  u(6) = c(1);  u(7) = c(1);   %% collective pitch command (rad)\n'], ...
    ix('Time'), ix('BldPitch1'), ix('GenSpeed'), ix('Wind1VelX'), ix('Wind1VelY'));
add_block('simulink/User-Defined Functions/MATLAB Function', [mdl '/wrap']);
rt = sfroot;
m  = rt.find('-isa', 'Simulink.BlockDiagram', 'Name', mdl);
ch = m.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/wrap']);
if numel(ch) ~= 1, error('run_E3W:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
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
    log_error(errf, 'W2 simulation', ME);
    err = strrep(ME.message, newline, ' ');
end
wall = toc(w);
try
    discon_wrapper('final');                                        % final call after the simulation
catch ME
    log_error(errf, 'W2 final call', ME);
    err = strtrim([err ' | final call: ' strrep(ME.message, newline, ' ')]);
    if libisloaded('DISCON'), unloadlibrary('DISCON'); end
end
st = discon_wrapper('stats');
close_system(mdl, 0);
clear('FAST_SFunc');
end

function [D, chk] = read_checked(outb, ok_run, channels)
% read a .outb and check its OutList and units (spec_E3 channels.verified, channels.units)
D = [];  chk = '';
if ~ok_run || ~exist(outb, 'file'), chk = 'run not completed';  return, end
try
    [D, N, U] = ReadFASTbinary(outb);
catch ME
    chk = ['.outb not readable: ' ME.message];  return
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
