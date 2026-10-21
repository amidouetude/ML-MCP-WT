function run_E3b()
%RUN_E3B  Single execution of E3b, region-3 qualification of DISCON (openfast_q1/E3/spec_E3.yaml).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E3');  run_E3b
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_E3.yaml is not SPEC_SHA (adopted spec + amendments 1 to 4); a binary, the DLL or the r-test
%   .bts differs from its SHA-256 (spec_E3 campaign.depends_on); the last commit of discon_wrapper.m
%   and discon.h is not WRAP_COMMIT or spec_E3W.yaml differs from WRAP_SPEC (campaign.depends_on.wrapper);
%   matlab-toolbox (ReadFASTbinary) is not at TB_COMMIT; the campaign folder already exists.
%
%   Steps, each run once, never retried, one simulation at a time:
%     wind    gen_wind_E3: 21 TurbSim inputs and fields (spec_E3 E3b_region3_qualification.wind_generation)
%     runs    21 runs (7 speeds x 3 seeds), then the repetition of 18 m/s seed 31001
%             (spec_E3 E3b_region3_qualification.runs, .repeatability) on plant_configuration (amendment 4,
%             configuration O8): case prepared by prepare_case_E3 (mode 'sfunc', InflowWind file,
%             TMax = 660 s, NumCrctn 0 -> 1, InterpOrder 2 unchanged), Simulink model built here
%             (FAST_SFunc and one MATLAB Function block calling discon_wrapper at every DT with the
%             measured BldPitch1, as run_E3W W2), the 6 wrapper outputs logged at every DT by a To
%             Workspace block; sim is called with CaptureErrors on, so that runs/<run>/wrapper_log.mat
%             and the .outb are kept also when OpenFAST stops the run; the library is loaded before
%             and unloaded after each run, with the final call (discon_wrapper 'final')
%     Q1      SHA-256 of every input (case copy, .inp, .bts, DLL, S-function binaries, wrapper files)
%             written before each run and recomputed after it (criteria.Q1_integrity)
%     analyse analyse_E3b (Q1-Q5, reported_only, domain_rule, verdict)
%   Every catch appends getReport(ME, 'extended') to errors_E3b.txt.
%   Writes in results/Q1-E3-QUAL-<date>-c/: meta_E3b.txt, verdict_E3b.txt, wind/ (.inp, .bts,
%   TurbSim logs), runs/<run>/ (case copy, manifest, model, .outb, wrapper_log.mat, wrapper_warnings.txt,
%   inputs_before.txt, inputs_after.txt, summary.csv), summary_E3b.csv, errors_E3b.txt if any
%   (spec_E3 outputs.files).

SPEC_SHA  = '7a3a8662fa1ede2c39b08777cbddfc3196f486b3031cbb526207e4bdf4dfe2a9';   % spec_E3, amendment 4
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
WRAP_COMMIT = '11f0133';                                                                                  % campaign.depends_on.wrapper
WRAP_SPEC = 'a78de8925221565c50f47ef458b60497891e21547d90d048f0cb38cd08bb0d86';                             % campaign.depends_on.wrapper (spec_E3W)
WRAP_FILES = {'discon_wrapper.m', 'discon.h'};                                                             % campaign.depends_on.wrapper
DT        = 0.00625;                          % s, spec_E3W wrapper.period
TMAX      = 660;                              % s, E3b_region3_qualification.duration and .runs
REPEAT    = [18 31001];                       % m/s, seed: E3b_region3_qualification.repeatability
CODE = {'prepare_case_E3.m', 'run_E3a.m', 'analyse_E3a.m', 'gen_wind_E3.m', 'run_E3b.m', 'analyse_E3b.m', ...
        'discon_wrapper.m', 'discon.h', 'check_input_refs.m', 'spec_E3W.yaml'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
SFUN = {fullfile(BIN_DIR, BIN_SHA{2,1}); fullfile(BIN_DIR, BIN_SHA{3,1})};    % S-function binaries (Q1_integrity)
WRAP = fullfile(ED3, WRAP_FILES(:));                                         % wrapper files (Q1_integrity)

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E3b:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3.yaml')), SPEC_SHA)
    error('run_E3b:spec', 'spec_E3.yaml SHA-256 differs from %s.', SPEC_SHA);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('run_E3b:binary', '%s SHA-256 differs from spec_E3 campaign.depends_on.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('run_E3b:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
if ~strcmp(sha256_file(abs_(BTS_REL)), BTS_SHA), error('run_E3b:bts', 'r-test .bts SHA-256 differs from %s.', BTS_SHA); end
[stw, wc] = system(sprintf('git -C "%s" log -1 --format=%%H -- openfast_q1/E3/discon_wrapper.m openfast_q1/E3/discon.h', ROOT));
if stw ~= 0 || ~startsWith(strtrim(wc), WRAP_COMMIT)
    error('run_E3b:wrapper', 'Last commit of the wrapper files is %s, expected %s (campaign.depends_on.wrapper).', strtrim(wc), WRAP_COMMIT);
end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3W.yaml')), WRAP_SPEC)
    error('run_E3b:wrapspec', 'spec_E3W.yaml SHA-256 differs from %s (campaign.depends_on.wrapper).', WRAP_SPEC);
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E3b:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
ID  = ['Q1-E3-QUAL-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-c'];   % attempts -a (2026-10-17): wrong relative path to the wind file; -b (2026-10-21): coupling unstable with InterpOrder 1
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E3b:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {'previous_attempt: results/Q1-E3-QUAL-2026-10-21-b (coupling unstable with InterpOrder 1, 19 of 22 runs stopped)', sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_SHA)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE{k}, sha256_file(fullfile(ED3, CODE{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('wrapper: commit %s (last commit of discon_wrapper.m and discon.h)', strtrim(wc)), ...
         'plant_configuration: O8, FAST_SFunc (PCMode 4, VSContrl 4), discon_wrapper at every DT with the measured BldPitch1, InterpOrder 2, NumCrctn 1 in the .fst copy', ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), ...
         sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E3b.txt'), M);

% --- environment (session only, as run_E3W) ---------------------------------------------------
addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_E3b.txt');     % full report of every catch

% --- wind fields ------------------------------------------------------------------------------
extra = {};
try
    W = gen_wind_E3(ROOT, fullfile(OUT, 'wind'), fullfile(BIN_DIR, 'TurbSim_x64.exe'));
catch ME
    W = [];
    log_error(ERRF, 'wind generation', ME);
    extra{end+1} = ['wind generation: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E3b.txt)'];
end

% --- runs -------------------------------------------------------------------------------------
R = struct('name', {}, 'speed', {}, 'seed', {}, 'rep', {}, 'case_dir', {}, 'outb', {}, 'channels', {}, ...
           'added', {}, 'ok_run', {}, 'wall_s', {}, 'q1_same', {}, 'err', {}, 'wraplog', {}, 'ncalls', {}, ...
           'nwarn', {}, 'slx_sha', {});
if ~isempty(W)
    j = find([W.speed] == REPEAT(1) & [W.seed] == REPEAT(2));
    plan = [num2cell(1:numel(W)); num2cell(ones(1, numel(W)))];
    plan = [plan, {j; 2}];                     % repetition after the 21 runs
    for q = 1:size(plan, 2)
        w = W(plan{1,q});  rep = plan{2,q};
        r = struct('name', w.name, 'speed', w.speed, 'seed', w.seed, 'rep', rep, 'case_dir', '', 'outb', '', ...
                   'channels', {{}}, 'added', {{}}, 'ok_run', false, 'wall_s', NaN, 'q1_same', false, 'err', '', ...
                   'wraplog', '', 'ncalls', NaN, 'nwarn', NaN, 'slx_sha', '');
        if rep == 2, r.name = [w.name '_rep2']; end
        if ~w.ok
            r.err = ['no wind field: ' w.err];
        else
            try
                C = prepare_case_E3(ROOT, fullfile(OUT, 'runs', r.name), struct('mode', 'sfunc', 'tmax', TMAX, ...
                        'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', w.bts, 'bts_sha', w.bts_sha, 'copy_bts', false, ...
                        'num_crctn', 1));                                                     % plant_configuration (amendment 4)
                r.case_dir = C.case_dir;  r.channels = C.channels;  r.added = C.added;
                inputs = [C.manifest(:,1); {w.inp; w.bts; abs_(DLL_REL)}; SFUN; WRAP];        % Q1_integrity
                before = hash_list(inputs);
                write_lines(fullfile(C.case_dir, 'inputs_before.txt'), strcat(before, {'  '}, inputs));
                [r.ok_run, r.wall_s, r.err, r.slx_sha, st] = run_sfunc(C, DT, TMAX, abs_(DLL_REL), HFILE, ERRF, r.name);
                after = hash_list(inputs);
                write_lines(fullfile(C.case_dir, 'inputs_after.txt'), strcat(after, {'  '}, inputs));
                r.q1_same = isequal(before, after);
                r.outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.SFunc.outb');
                r.wraplog = fullfile(C.case_dir, 'wrapper_log.mat');
                r.ncalls = st.ncalls;  r.nwarn = numel(st.warnings);
                if isempty(st.warnings), wl = {'none'}; else, wl = st.warnings(:); end
                write_lines(fullfile(C.case_dir, 'wrapper_warnings.txt'), wl);
            catch ME
                if libisloaded('DISCON'), unloadlibrary('DISCON'); end
                log_error(ERRF, ['run ' r.name], ME);
                r.err = [strrep(ME.message, newline, ' ') ' (full report in errors_E3b.txt)'];
            end
        end
        fprintf('%s: run %s, %.1f s, %g DISCON calls\n', r.name, yn(r.ok_run), r.wall_s, r.ncalls);
        R(end+1) = r; %#ok<AGROW>
    end
    a = unique(cat(1, R.added));
    if ~isempty(a), extra{end+1} = ['outlist_additions (every case): ' strjoin(a', ', ')]; end
end
save(fullfile(OUT, 'runs_E3b.mat'), 'R', 'W');

% --- analysis and end -------------------------------------------------------------------------
analyse_E3b(OUT, R, W);
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E3b.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function h = hash_list(files)
h = cell(numel(files), 1);
for k = 1:numel(files)
    if exist(files{k}, 'file'), h{k} = sha256_file(files{k}); else, h{k} = 'missing'; end
end
end

function [ok, wall, err, slx_sha, st] = run_sfunc(C, DT, tmax, dll, hfile, errf, tag)
% one run on plant_configuration (spec_E3 E3b_region3_qualification): model built as run_E3W run_w2,
% plus a To Workspace block logging the 6 wrapper outputs at every DT; sim with CaptureErrors on, the
% wrapper log is saved whatever the end of the run (as diag_E3b_loop); library loaded before and
% unloaded after the run, final call after the simulation
mdl = 'E3b_sfunc';
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
    '%% generated by run_E3b.m: discon_wrapper at every DT (spec_E3W wrapper.period); channel indices from channels.txt\n' ...
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
if numel(ch) ~= 1, error('run_E3b:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
ch.Script = script;
add_block('simulink/Sinks/To Workspace', [mdl '/log'], 'VariableName', 'wraplog', ...      % outputs.files (wrapper log)
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
ok = false;  err = '';  so = [];
w = tic;
try
    so = sim(mdl, 'ReturnWorkspaceOutputs', 'on', 'CaptureErrors', 'on');
    em = so.ErrorMessage;
    if isempty(em), ok = true; else, err = strrep(em, newline, ' '); end
catch ME
    log_error(errf, [tag ' simulation'], ME);
    err = strrep(ME.message, newline, ' ');
end
wall = toc(w);
if ~ok && ~isempty(err)
    fid = fopen(errf, 'a');
    fprintf(fid, '===== %s simulation message (%s)\n%s\n', tag, stamp(), err);
    fclose(fid);
end
try
    discon_wrapper('final');                                        % final call after the simulation
catch ME
    log_error(errf, [tag ' final call'], ME);
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
    catch ME
        log_error(errf, [tag ' wrapper log'], ME);
        err = strtrim([err ' | wrapper log: ' strrep(ME.message, newline, ' ')]);
    end
end
close_system(mdl, 0);
clear('FAST_SFunc');
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
