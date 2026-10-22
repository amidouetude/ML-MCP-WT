function run_E2_V3()
%RUN_E2_V3  Single execution of E2 V3, pitch steps on configuration O8 (openfast_q1/E2/spec_E2.yaml,
%validation.V3_pitch_steps, amendment 6).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E2');  run_E2_V3
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_E2.yaml, spec_E3.yaml or spec_E3W.yaml differs from SPEC_E2_SHA, SPEC_E3_SHA, WRAP_SPEC; an
%   S-function binary or DISCON.dll differs from its SHA-256 (spec_E3 campaign.depends_on); the last
%   commit of discon_wrapper.m and discon.h is not WRAP_COMMIT; matlab-toolbox (ReadFASTbinary) is not
%   at TB_COMMIT; the E1 CSV differs from CSV_SHA, or for 14, 18 or 22 m/s sprintf('%.4f', beta_eq_deg)
%   is not the string of PITCH (spec_E2 validation.V3_pitch_steps.initial_conditions), or a final pitch
%   of PITCH is not sprintf('%.4f', beta_eq + 1 or - 1) (validation.V3_pitch_steps.maneuver); the Cp
%   table differs from CP_SHA; the campaign folder already exists.
%
%   Steps, each run once, never retried, one simulation at a time:
%     runs    6 runs U14_up, U14_dn, U18_up, U18_dn, U22_up, U22_dn on configuration O8
%             (validation.V3_pitch_steps.plant): case prepared by prepare_case_E3 (mode 'sfunc',
%             TMax = 70 s, NumCrctn 0 -> 1, BlPitch(1-3) = beta_eq(U), steady wind U, override maneuver
%             TPitManS 60 s, PitManRat 8 deg/s, BlPitchF = beta_eq(U) + or - 1 deg, AeroDyn channels
%             RtAeroCp, RtArea, RtTSR added; validation.V3_pitch_steps.steady_wind, .initial_conditions,
%             .maneuver, .outputs_added); Simulink model and wrapper log as run_E3b (run_sfunc copied
%             from run_E3b.m); SHA-256 of the inputs written before and after each run (reported)
%     analyse analyse_E2_V3 (validation.V3_pitch_steps.compare, .pass, .variant_rule, .reported_only)
%   Every catch appends getReport(ME, 'extended') to errors_E2_V3.txt.
%   Writes in results/Q1-E2-V3-<date>-a/: meta_E2_V3.txt, runs/<run>/ (case copy, manifest, model,
%   .outb, wrapper_log.mat, wrapper_warnings.txt, inputs_before.txt, inputs_after.txt), runs_E2_V3.mat,
%   verdict_E2_V3.txt, V3_runs.csv, V3_trajectories.mat, errors_E2_V3.txt if any.

SPEC_E2_SHA = '49468fb0c9185d186419c1f6acd881bee891b546954f095e80519fe293e7b95f';   % spec_E2, amendment 6
SPEC_E3_SHA = '66f7f43ba385d8b2880401d61c6ea1e75601d9c82acbc001159158a96ae96ba4';   % spec_E3, amendment 6
WRAP_SPEC   = 'a78de8925221565c50f47ef458b60497891e21547d90d048f0cb38cd08bb0d86';   % spec_E3W (spec_E3 campaign.depends_on.wrapper)
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';   % spec_E3 campaign.depends_on.sfunction
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d'};  % spec_E3 campaign.depends_on.sfunction
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % spec_E3 campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in spec_F
WRAP_COMMIT = '11f0133';                                                                                  % spec_E3 campaign.depends_on.wrapper
WRAP_FILES = {'discon_wrapper.m', 'discon.h'};                                                             % spec_E3 campaign.depends_on.wrapper
CSV_REL   = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';                              % validation.V3_pitch_steps.initial_conditions
CSV_SHA   = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';
CP_REL    = 'results/Q1-E2-ROM-2026-10-16-b/verification/cp_table_E2.mat';                                % Cp table of V0-V2 (Q1-E2-ROM-2026-10-16-b)
CP_SHA    = '9e16ebbf84d0de9cd3f09ecae3a2e7cbf8b469415e7f6e65c6f8ec484c6ceac2';
% speed (m/s), beta_eq (deg, validation.V3_pitch_steps.initial_conditions),
% BlPitchF up and down (deg, validation.V3_pitch_steps.maneuver)
PITCH     = {14, '8.5723',  '9.5723',  '7.5723';
             18, '14.9124', '15.9124', '13.9124';
             22, '19.8512', '20.8512', '18.8512'};
MANEUVER  = struct('TPitManS', '60', 'PitManRat', '8');                                                    % validation.V3_pitch_steps.maneuver
EXTRA_AD  = {'RtAeroCp', 'RtArea', 'RtTSR'};                                                               % validation.V3_pitch_steps.outputs_added
DT        = 0.00625;                          % s, spec_E3W wrapper.period
TMAX      = 70;                               % s, validation.V3_pitch_steps.maneuver
CODE = {'E2/run_E2_V3.m', 'E2/analyse_E2_V3.m', 'E2/rom_params.m', 'E2/rom_rhs.m', 'E2/rom_step.m', ...
        'E2/rom_torque_law.m', 'E2/spec_E2.yaml', 'E3/prepare_case_E3.m', 'E3/check_input_refs.m', ...
        'E3/discon_wrapper.m', 'E3/discon.h', 'E3/spec_E3.yaml', 'E3/spec_E3W.yaml'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
SFUN = {fullfile(BIN_DIR, BIN_SHA{1,1}); fullfile(BIN_DIR, BIN_SHA{2,1})};   % S-function binaries
WRAP = fullfile(ED3, WRAP_FILES(:));                                         % wrapper files

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E2_V3:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED2, 'spec_E2.yaml')), SPEC_E2_SHA)
    error('run_E2_V3:spec', 'spec_E2.yaml SHA-256 differs from %s.', SPEC_E2_SHA);
end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3.yaml')), SPEC_E3_SHA)
    error('run_E2_V3:spec', 'spec_E3.yaml SHA-256 differs from %s.', SPEC_E3_SHA);
end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3W.yaml')), WRAP_SPEC)
    error('run_E2_V3:wrapspec', 'spec_E3W.yaml SHA-256 differs from %s.', WRAP_SPEC);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('run_E2_V3:binary', '%s SHA-256 differs from spec_E3 campaign.depends_on.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('run_E2_V3:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
[stw, wc] = system(sprintf('git -C "%s" log -1 --format=%%H -- openfast_q1/E3/discon_wrapper.m openfast_q1/E3/discon.h', ROOT));
if stw ~= 0 || ~startsWith(strtrim(wc), WRAP_COMMIT)
    error('run_E2_V3:wrapper', 'Last commit of the wrapper files is %s, expected %s.', strtrim(wc), WRAP_COMMIT);
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E2_V3:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
if ~strcmp(sha256_file(abs_(CSV_REL)), CSV_SHA), error('run_E2_V3:csv', 'E1 CSV SHA-256 differs from %s.', CSV_SHA); end
for k = 1:size(PITCH, 1)
    beta = read_beta_eq(abs_(CSV_REL), sprintf('%d', PITCH{k,1}));
    if ~strcmp(sprintf('%.4f', beta), PITCH{k,2})
        error('run_E2_V3:beta', 'beta_eq_deg at %d m/s is %.10g, which does not round to %s.', PITCH{k,1}, beta, PITCH{k,2});
    end
    b0 = str2double(PITCH{k,2});
    if ~strcmp(sprintf('%.4f', b0 + 1), PITCH{k,3}) || ~strcmp(sprintf('%.4f', b0 - 1), PITCH{k,4})
        error('run_E2_V3:pitchF', 'Final pitch strings at %d m/s are not beta_eq + 1 and - 1 deg.', PITCH{k,1});
    end
end
if ~strcmp(sha256_file(abs_(CP_REL)), CP_SHA), error('run_E2_V3:cp', 'Cp table SHA-256 differs from %s.', CP_SHA); end
ID  = ['Q1-E2-V3-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E2_V3:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', ...
     sprintf('start: %s', stamp()), sprintf('spec: openfast_q1/E2/spec_E2.yaml %s', SPEC_E2_SHA), ...
     sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_E3_SHA), sprintf('spec: openfast_q1/E3/spec_E3W.yaml %s', WRAP_SPEC)};
for k = 1:numel(CODE), M{end+1} = sprintf('code: openfast_q1/%s %s', CODE{k}, sha256_file(fullfile(ROOT, 'openfast_q1', strrep(CODE{k}, '/', filesep)))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
pl = strjoin(cellfun(@(u, b, up, dn) sprintf('%d m/s %s (up %s, down %s)', u, b, up, dn), PITCH(:,1), PITCH(:,2), PITCH(:,3), PITCH(:,4), ...
             'UniformOutput', false), ', ');
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('wrapper: commit %s (last commit of discon_wrapper.m and discon.h)', strtrim(wc)), ...
         sprintf('input: %s %s, beta_eq_deg and BlPitchF written as: %s deg', CSV_REL, CSV_SHA, pl), ...
         sprintf('input: %s %s (Cp table)', CP_REL, CP_SHA), ...
         'plant_configuration: O8, FAST_SFunc (PCMode 4, VSContrl 4), discon_wrapper at every DT with the measured BldPitch1, InterpOrder 2, NumCrctn 1 in the .fst copy (spec_E2 validation.V3_pitch_steps.plant)', ...
         sprintf('maneuver: TPitManS %s s, PitManRat %s deg/s, TMax %d s; steady wind; AeroDyn channels added: %s', ...
                 MANEUVER.TPitManS, MANEUVER.PitManRat, TMAX, strjoin(EXTRA_AD, ', ')), ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), ...
         sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E2_V3.txt'), M);

% --- environment (session only, as run_E3b) ---------------------------------------------------
addpath(ED2);  addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_E2_V3.txt');     % full report of every catch

% --- runs -------------------------------------------------------------------------------------
R = struct('name', {}, 'speed', {}, 'dir', {}, 'beta_eq', {}, 'BlPitchF', {}, 'case_dir', {}, 'outb', {}, ...
           'channels', {}, 'added', {}, 'ok_run', {}, 'wall_s', {}, 'inputs_same', {}, 'err', {}, ...
           'wraplog', {}, 'ncalls', {}, 'nwarn', {}, 'slx_sha', {});
DIRS = {'up', 3; 'dn', 4};
extra = {};
for k = 1:size(PITCH, 1)
    for j = 1:size(DIRS, 1)
        r = struct('name', sprintf('U%d_%s', PITCH{k,1}, DIRS{j,1}), 'speed', PITCH{k,1}, 'dir', DIRS{j,1}, ...
                   'beta_eq', PITCH{k,2}, 'BlPitchF', PITCH{k,DIRS{j,2}}, 'case_dir', '', 'outb', '', ...
                   'channels', {{}}, 'added', {{}}, 'ok_run', false, 'wall_s', NaN, 'inputs_same', false, 'err', '', ...
                   'wraplog', '', 'ncalls', NaN, 'nwarn', NaN, 'slx_sha', '');
        try
            mv = MANEUVER;  mv.BlPitchF = r.BlPitchF;                                       % validation.V3_pitch_steps.maneuver
            C = prepare_case_E3(ROOT, fullfile(OUT, 'runs', r.name), struct('mode', 'sfunc', 'tmax', TMAX, ...
                    'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'num_crctn', 1, ...             % validation.V3_pitch_steps.plant
                    'init_pitch', r.beta_eq, ...                                              % .initial_conditions
                    'steady_wind', sprintf('%d', r.speed), ...                                % .steady_wind
                    'maneuver', mv, 'extra_ad_channels', {EXTRA_AD}));                        % .maneuver, .outputs_added
            r.case_dir = C.case_dir;  r.channels = C.channels;  r.added = C.added;
            inputs = [C.manifest(:,1); {abs_(DLL_REL); abs_(CSV_REL); abs_(CP_REL)}; SFUN; WRAP];
            before = hash_list(inputs);
            write_lines(fullfile(C.case_dir, 'inputs_before.txt'), strcat(before, {'  '}, inputs));
            [r.ok_run, r.wall_s, r.err, r.slx_sha, st] = run_sfunc(C, DT, TMAX, abs_(DLL_REL), HFILE, ERRF, r.name);
            after = hash_list(inputs);
            write_lines(fullfile(C.case_dir, 'inputs_after.txt'), strcat(after, {'  '}, inputs));
            r.inputs_same = isequal(before, after);
            r.outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.SFunc.outb');
            r.wraplog = fullfile(C.case_dir, 'wrapper_log.mat');
            r.ncalls = st.ncalls;  r.nwarn = numel(st.warnings);
            if isempty(st.warnings), wl = {'none'}; else, wl = st.warnings(:); end
            write_lines(fullfile(C.case_dir, 'wrapper_warnings.txt'), wl);
        catch ME
            if libisloaded('DISCON'), unloadlibrary('DISCON'); end
            log_error(ERRF, ['run ' r.name], ME);
            r.err = [strrep(ME.message, newline, ' ') ' (full report in errors_E2_V3.txt)'];
        end
        fprintf('%s: run %s, %.1f s, %g DISCON calls\n', r.name, yn(r.ok_run), r.wall_s, r.ncalls);
        R(end+1) = r; %#ok<AGROW>
    end
end
if ~isempty(R)
    a = unique(cat(1, R.added));
    if ~isempty(a), extra{end+1} = ['outlist_additions (every case): ' strjoin(a', ', ')]; end
end
save(fullfile(OUT, 'runs_E2_V3.mat'), 'R');

% --- analysis and end -------------------------------------------------------------------------
try
    analyse_E2_V3(OUT, R, abs_(CP_REL));
catch ME
    log_error(ERRF, 'analyse_E2_V3', ME);
    extra{end+1} = ['analysis: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E2_V3.txt)'];
end
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E2_V3.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function h = hash_list(files)
h = cell(numel(files), 1);
for k = 1:numel(files)
    if exist(files{k}, 'file'), h{k} = sha256_file(files{k}); else, h{k} = 'missing'; end
end
end

function [ok, wall, err, slx_sha, st] = run_sfunc(C, DT, tmax, dll, hfile, errf, tag)
% one run on configuration O8, copied from run_E3b.m (model built as run_E3W run_w2, plus a To
% Workspace block logging the 6 wrapper outputs at every DT; sim with CaptureErrors on, the wrapper
% log is saved whatever the end of the run; library loaded before and unloaded after the run, final
% call after the simulation)
mdl = 'E2V3_sfunc';
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
    '%% generated by run_E2_V3.m: discon_wrapper at every DT (spec_E3W wrapper.period); channel indices from channels.txt\n' ...
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
if numel(ch) ~= 1, error('run_E2_V3:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
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

function beta = read_beta_eq(f, speed)
% beta_eq_deg of the row vent_m_s = speed in the E1 CSV (';' separated, header on the first line),
% as run_E3b.m
L = read_lines(f);
H = strsplit(strtrim(L{1}), ';');
jv = find(strcmp(H, 'vent_m_s'));  jb = find(strcmp(H, 'beta_eq_deg'));
if ~isscalar(jv) || ~isscalar(jb), error('run_E2_V3:csvhead', 'Columns vent_m_s and beta_eq_deg not found once in %s.', f); end
hit = {};
for k = 2:numel(L)
    F = strsplit(strtrim(L{k}), ';');
    if numel(F) == numel(H) && strcmp(F{jv}, speed), hit{end+1} = F{jb}; end %#ok<AGROW>
end
if numel(hit) ~= 1, error('run_E2_V3:csvrow', 'Row vent_m_s = %s found %d times in %s.', speed, numel(hit), f); end
beta = str2double(hit{1});
if ~isfinite(beta), error('run_E2_V3:csvval', 'beta_eq_deg at %s m/s is not a number.', speed); end
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
