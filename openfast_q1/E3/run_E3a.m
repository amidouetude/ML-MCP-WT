function run_E3a()
%RUN_E3A  Single execution of E3a, plant equivalence exe vs S-function (openfast_q1/E3/spec_E3.yaml).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E3');  run_E3a
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_E3.yaml is not SPEC_SHA (adopted spec + amendment 1); a binary, the DLL or the r-test .bts
%   differs from its SHA-256 (spec_E3 campaign.depends_on, E3a_plant_equivalence.wind);
%   matlab-toolbox (ReadFASTbinary) is not at TB_COMMIT; the campaign folder already exists.
%
%   Steps, each run once, never retried:
%     run 1   openfast_x64.exe + DISCON.dll, PCMode 5, VSContrl 5, TMax 60 s
%             (spec_E3 E3a_plant_equivalence.run_1_exe)
%     check   OutList and units of the run-1 .outb (spec_E3 channels.verified, channels.units);
%             on a difference E3a is STOPPED and the S-function is not run
%     run 2   FAST_SFunc, PCMode 4, VSContrl 4, inputs replayed from run 1 at every DT with the unit
%             conversions of spec_E3 E3a_plant_equivalence.run_2_sfunction, once with lag 0 and once
%             with lag 1 DT (spec_E3 E3a_plant_equivalence.lag_rule)
%     analyse analyse_E3a (metrics, lag choice, verdict)
%   S-function inputs (FAST_Library.h l.73-83, openfast-4.2.1/modules/openfast-library/src):
%     1 generator torque (N-m), 2 electrical power (W), 3 yaw position (rad), 4 yaw rate (rad/s),
%     5-7 blade 1-3 pitch angle (rad), 8 HSS brake fraction (-), 9-11 airfoil control (-),
%     12-31 cable DeltaL (m), 32-51 cable DeltaLDot (m/s); 51 fixed inputs (l.72).
%   S-function parameters (FAST_SFunc.c l.37-40): input file name, TMax, number of additional
%   inputs (0).
%   Writes in results/Q1-E3-PLANTEQ-<date>-a/: meta_E3a.txt, verdict_E3a.txt, the case copies with
%   their manifests and .outb, replay_inputs.mat, the Simulink models (spec_E3 outputs.files).

SPEC_SHA  = '6d115e86e9b705e8873deebfafad6261a4fe9cb472c092c7b6a7a4cc87794447';
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'openfast_x64.exe',          'dbae80560269c00f4a1f3529b5bb3ffcd111faa6d6791f4cce6dcf321679d924';   % campaign.depends_on.exe
             'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';   % campaign.depends_on.sfunction
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d';   % campaign.depends_on.sfunction
             'TurbSim_x64.exe',           '5f70b3e2d50cbe09ad37d98569443a7d6f1b7a97c214bf21bbd9533cf2f29df2'};  % campaign.depends_on.turbsim
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
BTS_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/test/5MW_Baseline/Wind/90m_12mps_twr.bts';             % E3a_plant_equivalence.wind
BTS_SHA   = '0a368181d3dce9bdb9bb8501e395c1a943aed933098ac914334dcfcc0507d4c1';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
TMAX      = 60;                                    % s, E3a_plant_equivalence.wind
LAGS      = [0 1];                                 % DT, E3a_plant_equivalence.lag_rule
N_INPUTS  = 51;                                    % FAST_Library.h l.72
DT        = 0.00625;                               % s, channels.output_format (checked by prepare_case_E3)
CODE = {'prepare_case_E3.m', 'run_E3a.m', 'analyse_E3a.m', 'gen_wind_E3.m', 'run_E3b.m', 'analyse_E3b.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E3a:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3.yaml')), SPEC_SHA)
    error('run_E3a:spec', 'spec_E3.yaml SHA-256 differs from %s.', SPEC_SHA);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('run_E3a:binary', '%s SHA-256 differs from spec_E3 campaign.depends_on.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('run_E3a:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
if ~strcmp(sha256_file(abs_(BTS_REL)), BTS_SHA), error('run_E3a:bts', 'r-test .bts SHA-256 differs from %s.', BTS_SHA); end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E3a:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E3-PLANTEQ-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E3a:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE{k}, sha256_file(fullfile(ED3, CODE{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('input: %s %s', BTS_REL, BTS_SHA), ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), ...
         sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E3a.txt'), M);

% --- environment (session only) ---------------------------------------------------------------
addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
opt0 = struct('dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', abs_(BTS_REL), 'bts_sha', BTS_SHA, ...
              'copy_bts', true, 'tmax', TMAX);
R = struct('name', {}, 'case_dir', {}, 'outb', {}, 'channels', {}, 'added', {}, 'ok_run', {}, 'wall_s', {}, 'err', {});
extra = {};

% --- run 1: executable + DISCON -----------------------------------------------------------------
r = new_run('run1_exe');
try
    o1 = opt0;  o1.mode = 'exe';
    C = prepare_case_E3(ROOT, fullfile(OUT, r.name), o1);
    r = fill_case(r, C);
    [r.ok_run, r.wall_s, r.err] = run_exe(fullfile(BIN_DIR, BIN_SHA{1,1}), C);
    r.outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.outb');
catch ME
    r.err = strrep(ME.message, newline, ' ');
end
R(end+1) = r;

% --- run 2: S-function, inputs replayed from run 1 ----------------------------------------------
[D1, chk] = read_checked(R(1));
if isempty(chk)
    N  = size(D1, 1);
    if max(abs(D1(:,1) - (0:N-1)'*DT)) > DT/100
        chk = 'run-1 output times are not 0, DT, 2 DT, ...';
    end
end
if isempty(chk)
    col = @(name) D1(:, strcmpi(R(1).channels, name));
    U = zeros(N, N_INPUTS);
    U(:,1) = col('GenTq')*1000;                    % kN-m -> N-m, E3a_plant_equivalence.run_2_sfunction
    U(:,2) = col('GenPwr')*1000;                   % kW -> W
    U(:,5) = col('BlPitchC1')*pi/180;              % deg -> rad
    U(:,6) = col('BlPitchC2')*pi/180;
    U(:,7) = col('BlPitchC3')*pi/180;
    save(fullfile(OUT, 'replay_inputs.mat'), 'U', 'DT', 'LAGS');
    extra{end+1} = sprintf('replay_inputs: replay_inputs.mat %s', sha256_file(fullfile(OUT, 'replay_inputs.mat')));
    for lag = LAGS
        r = new_run(sprintf('run2_sfunc_lag%d', lag));
        try
            o2 = opt0;  o2.mode = 'sfunc';
            C2 = prepare_case_E3(ROOT, fullfile(OUT, r.name), o2);
            r = fill_case(r, C2);
            Ul = [repmat(U(1,:), lag, 1); U(1:end-lag,:)];    % commands of step k applied at step k+lag
            [r.ok_run, r.wall_s, r.err, slx_sha] = run_sfunc(C2, Ul, DT, TMAX, fullfile(OUT, r.name));
            r.outb = fullfile(fileparts(C2.fst), '5MW_Land_DLL_WTurb.SFunc.outb');
            extra{end+1} = sprintf('model: %s/E3a_sfunc.slx %s', r.name, slx_sha); %#ok<AGROW>
        catch ME
            r.err = strrep(ME.message, newline, ' ');
        end
        R(end+1) = r; %#ok<AGROW>
    end
    stopped = '';
else
    stopped = ['run 1: ' chk];
end
for k = 1:numel(R)
    if ~isempty(R(k).added), extra{end+1} = sprintf('outlist_additions %s: %s', R(k).name, strjoin(R(k).added, ', ')); end %#ok<AGROW>
end
save(fullfile(OUT, 'runs_E3a.mat'), 'R', 'stopped');

% --- analysis and end -------------------------------------------------------------------------
analyse_E3a(OUT, R, stopped);
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E3a.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function r = new_run(name)
r = struct('name', name, 'case_dir', '', 'outb', '', 'channels', {{}}, 'added', {{}}, ...
           'ok_run', false, 'wall_s', NaN, 'err', '');
end

function r = fill_case(r, C)
r.case_dir = C.case_dir;  r.channels = C.channels;  r.added = C.added;
end

function [ok, wall, err] = run_exe(exe, C)
% one run of openfast_x64.exe in the case folder; console output to run.log
cdir = fileparts(C.fst);
[~, name, ext] = fileparts(C.fst);
w = tic;
st = system(sprintf('cd /d "%s" && "%s" "%s%s" > run.log 2>&1', cdir, exe, name, ext));
wall = toc(w);
ok = st == 0;
if ok, err = ''; else, err = sprintf('openfast_x64.exe exit code %d (see run.log)', st); end
end

function [ok, wall, err, slx_sha] = run_sfunc(C, U, DT, tmax, rd)
% build the replay model, simulate once
mdl = 'E3a_sfunc';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
          'FixedStep', sprintf('%.17g', DT), 'StopTime', sprintf('%.17g', tmax), ...
          'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SignalLogging', 'off');
N = size(U, 1);
% data time of row k (k >= 2) = (k - 1.5) DT, so that at the step time (k - 1) DT the held value
% is row k without relying on equality of floating-point times
td = [0; ((1:N-1)' - 0.5)*DT];
assignin('base', 'E3a_replay', [td, U]);
add_block('simulink/Sources/From Workspace', [mdl '/replay'], 'VariableName', 'E3a_replay', ...
          'SampleTime', sprintf('%.17g', DT), 'Interpolate', 'off', 'OutputAfterFinalValue', 'Holding final value');
add_block('simulink/User-Defined Functions/S-Function', [mdl '/FAST'], 'FunctionName', 'FAST_SFunc', ...
          'Parameters', sprintf('''%s'', %.17g, 0', C.fst, tmax));
add_block('simulink/Sinks/Terminator', [mdl '/term']);
add_line(mdl, 'replay/1', 'FAST/1', 'autorouting', 'on');
add_line(mdl, 'FAST/1', 'term/1', 'autorouting', 'on');
f = fullfile(rd, [mdl '.slx']);
save_system(mdl, f);
slx_sha = sha256_file(f);
clear('FAST_SFunc');
evalin('base', 'clear OutList');
ok = false;  err = '';
w = tic;
try
    sim(mdl);
    ok = true;
catch ME
    err = strrep(ME.message, newline, ' ');
end
wall = toc(w);
close_system(mdl, 0);
clear('FAST_SFunc');
evalin('base', 'clear E3a_replay');
end

function [D, chk] = read_checked(r)
% read a .outb and check its OutList and units (spec_E3 channels.verified, channels.units)
D = [];  chk = '';
if ~r.ok_run || ~exist(r.outb, 'file')
    chk = ['run not completed: ' r.err];  return
end
try
    [D, N, U] = ReadFASTbinary(r.outb);
catch ME
    chk = ['.outb not readable: ' ME.message];  return
end
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
if numel(N) ~= numel(r.channels) || ~all(strcmpi(N, r.channels(:)))
    chk = 'OutList written by OpenFAST differs from the expected channel list';  return
end
UNITS = {'GenTq', 'kN-m'; 'GenPwr', 'kW'; 'BlPitchC1', 'deg'; 'BlPitchC2', 'deg'; 'BlPitchC3', 'deg'; ...
         'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'Wind1VelX', 'm/s'};                % channels.units
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if ~strcmp(u{1}, UNITS{k,2})
        chk = sprintf('unit of %s is %s, spec_E3 channels.units says %s', UNITS{k,1}, u{1}, UNITS{k,2});  return
    end
end
if ~all(isfinite(D(:))), chk = 'non-finite outputs';  return, end
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
