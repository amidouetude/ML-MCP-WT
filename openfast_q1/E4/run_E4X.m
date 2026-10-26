function run_E4X()
%RUN_E4X  Single execution of the exploratory campaign E4X, entry point of the pitch excitation for
%the E4 dataset (openfast_q1/E4/spec_E4X.yaml, with amendment 1).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E4');  run_E4X
%
%   EXPLORATORY (spec_E4X campaign.status_rule): no value enters the values registry or the
%   manuscript; the campaign only fixes the excitation of spec_E4.
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_E4X.yaml, spec_E3.yaml, spec_E3W.yaml or spec_E2.yaml differs from SPEC_E4X_SHA,
%   SPEC_E3_SHA, WRAP_SPEC, SPEC_E2_SHA; the S-function binaries, TurbSim or DISCON.dll differ from
%   their SHA-256 (spec_E3 campaign.depends_on); the last commit of discon_wrapper.m and discon.h
%   is not WRAP_COMMIT (campaign.depends_on.wrapper); matlab-toolbox (ReadFASTbinary) is not at
%   TB_COMMIT; the E1 CSV differs from CSV_SHA, or for 16 and 22 m/s sprintf('%.4f', beta_eq_deg)
%   is not the string of PITCH (spec_E3 E3b_region3_qualification.runs, amendment 6); the campaign
%   folder already exists. The same checks (except the campaign folder) are made again before each
%   run, with a run folder that must not exist: if one fails, that run and the following ones are
%   not executed and the reason is recorded. Checks and values are those of run_E2_V4data.m at
%   commit c1190a0.
%
%   Steps, each run once, never retried, one simulation at a time:
%     wind        gen_wind_E4X: 2 TurbSim inputs and fields, 16 and 22 m/s, RandSeed1 33001,
%                 UsableTime 180 (spec_E4X cases.mean_speeds, cases.seed, cases.wind)
%     excitation  excitation_E4X: p(t) in deg at every DT from t = 0 (excitation.signal,
%                 signal_amendment_1), saved in excitation.mat
%     runs        8 runs in the order of cases.order_amendment_1 (16 m/s X0, X1, X2, X3, then
%                 22 m/s X0, X1, X2, X3), TMax = 180 s (cases.duration), on configuration O8
%                 (campaign.plant): case prepared by prepare_case_E3, unchanged (mode 'sfunc',
%                 InflowWind file with the generated .bts, TMax 180, NumCrctn 0 -> 1, InterpOrder 2
%                 unchanged, BlPitch(1-3) 0 -> beta_eq_deg of E1 at the mean speed, RtVAvgxh in
%                 the AeroDyn OutList by spec_E3 channels.required); Simulink model as run_E3b.m,
%                 with the excitation of the arm injected only in the generated MATLAB Function
%                 block (campaign.plant, excitation.X0-X3, excitation.units, excitation.bounds,
%                 bounds_amendment_1); discon_wrapper.m unchanged
%     log         at every DT (excitation.logging): p(k), p(k-1), GenSpeed and BldPitch1 passed to
%                 DISCON, command before and after clipping, clipping flag, applied electrical
%                 power, and the 6 outputs of discon_wrapper 'step'; runs/<run>/wrapper_log.mat
%     inputs      SHA-256 of every input (case copy, .inp, .bts, DLL, E1 CSV, S-function binaries,
%                 wrapper files, excitation.mat) written before each run and recomputed after it
%     analyse     analyse_E4X (metrics, choice_rule, verdict RETAINED: Xn)
%   Every catch appends getReport(ME, 'extended') to errors_E4X.txt.
%   Writes in results/Q1-E4-EXCIT-<date>-a/ (outputs.folder): meta_E4X.txt, wind/ (.inp, .bts,
%   TurbSim logs, wind_manifest.txt), excitation.mat, runs/<run>/ (case copy, manifest, model,
%   .outb, wrapper_log.mat, wrapper_warnings.txt, inputs_before.txt, inputs_after.txt),
%   runs_E4X.mat, and through analyse_E4X metrics_E4X.csv and verdict_E4X.txt; errors_E4X.txt if any.

SPEC_E4X_SHA = '656659dcc47c98803e606e6fbc333a28174b48409ca66c76c52875c2a38d76d6';  % spec_E4X, amendment 1
SPEC_E3_SHA  = '66f7f43ba385d8b2880401d61c6ea1e75601d9c82acbc001159158a96ae96ba4';  % spec_E3, amendment 6
WRAP_SPEC    = 'a78de8925221565c50f47ef458b60497891e21547d90d048f0cb38cd08bb0d86';  % spec_E3 campaign.depends_on.wrapper (spec_E3W)
SPEC_E2_SHA  = '6c09b3ef2df0d8dade7123caaa56e22c6ce248578518545793a8a44dd2d00515';  % spec_E2, amendment 7 (nmpc_interface, rom_torque_law)
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';   % spec_E3 campaign.depends_on.sfunction
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d';   % spec_E3 campaign.depends_on.sfunction
             'TurbSim_x64.exe',           '5f70b3e2d50cbe09ad37d98569443a7d6f1b7a97c214bf21bbd9533cf2f29df2'};  % spec_E3 campaign.depends_on.turbsim
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % spec_E3 campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as run_E3b.m
WRAP_COMMIT = '11f0133';                                                                                  % spec_E3 campaign.depends_on.wrapper
WRAP_FILES  = {'discon_wrapper.m', 'discon.h'};                                                           % spec_E3 campaign.depends_on.wrapper
DT        = 0.00625;                          % s, spec_E3W wrapper.period
TMAX      = 180;                              % s, spec_E4X cases.duration
SPEEDS    = [16 22];                          % m/s, spec_E4X cases.mean_speeds, cases.order_amendment_1
ARMS      = {'X0', 'X1', 'X2', 'X3'};         % spec_E4X cases.arms, cases.order_amendment_1
CSV_REL   = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';                              % spec_E4X campaign.plant (beta_eq_deg of E1)
CSV_SHA   = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';
PITCH     = {16, '12.0261'; 22, '19.8512'};                                                               % m/s, beta_eq_deg (deg), as spec_E3 E3b_region3_qualification.runs
CODE_E4 = {'spec_E4X.yaml', 'run_E4X.m', 'gen_wind_E4X.m', 'excitation_E4X.m', 'analyse_E4X.m'};
CODE_E3 = {'prepare_case_E3.m', 'discon_wrapper.m', 'discon.h', 'check_input_refs.m', 'spec_E3.yaml', 'spec_E3W.yaml'};
CODE_E2 = {'spec_E2.yaml', 'rom_params.m', 'rom_torque_law.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
ED4  = fullfile(ROOT, 'openfast_q1', 'E4');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
SFUN = {fullfile(BIN_DIR, BIN_SHA{1,1}); fullfile(BIN_DIR, BIN_SHA{2,1})};    % S-function binaries (as run_E3b)
WRAP = fullfile(ED3, WRAP_FILES(:));                                         % wrapper files (as run_E3b)
REF  = struct('root', ROOT, 'ed2', ED2, 'ed3', ED3, 'ed4', ED4, 'spec_e4x', SPEC_E4X_SHA, 'spec_e3', SPEC_E3_SHA, ...
              'wrap_spec', WRAP_SPEC, 'spec_e2', SPEC_E2_SHA, 'bin_dir', BIN_DIR, 'bin_sha', {BIN_SHA}, ...
              'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'wrap_commit', WRAP_COMMIT, 'tb_dir', TB_DIR, ...
              'tb_commit', TB_COMMIT, 'csv', abs_(CSV_REL), 'csv_sha', CSV_SHA, 'pitch', {PITCH});

% --- refusals ---------------------------------------------------------------------------------
why = check_refs(REF);
if ~isempty(why), error('run_E4X:refused', 'Refused before the campaign: %s', why); end
ID  = ['Q1-E4-EXCIT-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];   % spec_E4X campaign.id
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E4X:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
[~, wc]   = system(sprintf('git -C "%s" log -1 --format=%%H -- openfast_q1/E3/discon_wrapper.m openfast_q1/E3/discon.h', ROOT));
M = {sprintf('campaign: %s', ID), 'purpose: entry point of the pitch excitation for the E4 dataset (spec_E4X campaign.purpose); EXPLORATORY, no value enters the values registry or the manuscript (campaign.status_rule)', ...
     sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), ...
     sprintf('spec: openfast_q1/E4/spec_E4X.yaml %s (amendment 1)', SPEC_E4X_SHA), ...
     sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_E3_SHA), sprintf('spec: openfast_q1/E2/spec_E2.yaml %s', SPEC_E2_SHA), ...
     'seed: RandSeed1 33001 (spec_E4X cases.seed), reserved for this campaign and excluded from E4, E5 and E7', ...
     sprintf('order: %s (cases.order_amendment_1)', strjoin(run_names(SPEEDS, ARMS), ', '))};
for k = 1:numel(CODE_E4), M{end+1} = sprintf('code: openfast_q1/E4/%s %s', CODE_E4{k}, sha256_file(fullfile(ED4, CODE_E4{k}))); end %#ok<AGROW>
for k = 1:numel(CODE_E3), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE_E3{k}, sha256_file(fullfile(ED3, CODE_E3{k}))); end %#ok<AGROW>
for k = 1:numel(CODE_E2), M{end+1} = sprintf('code: openfast_q1/E2/%s %s', CODE_E2{k}, sha256_file(fullfile(ED2, CODE_E2{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('wrapper: commit %s (last commit of discon_wrapper.m and discon.h)', strtrim(wc)), ...
         sprintf('input: %s %s, beta_eq_deg written as: 16 m/s %s, 22 m/s %s deg', CSV_REL, CSV_SHA, PITCH{1,2}, PITCH{2,2}), ...
         'plant: configuration O8, FAST_SFunc (PCMode 4, VSContrl 4), discon_wrapper at every DT, InterpOrder 2, NumCrctn 1, initial pitch beta_eq_deg of E1 (spec_E4X campaign.plant); excitation injected only in the generated MATLAB Function block', ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E4X.txt'), M);

% --- environment (session only, as run_E3b) ---------------------------------------------------
addpath(ED2);  addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_E4X.txt');     % full report of every catch
extra = {};

% --- wind fields ------------------------------------------------------------------------------
try
    W = gen_wind_E4X(ROOT, fullfile(OUT, 'wind'), fullfile(BIN_DIR, 'TurbSim_x64.exe'));
    if ~isequal(sort([W.speed]), SPEEDS) || ~all([W.seed] == 33001)
        error('run_E4X:wind', 'gen_wind_E4X did not return one field per speed of %s with seed 33001.', mat2str(SPEEDS));
    end
catch ME
    W = struct('speed', {}, 'seed', {}, 'name', {}, 'inp', {}, 'bts', {}, 'inp_sha', {}, 'bts_sha', {}, ...
               'ok', {}, 'wall_s', {}, 'err', {});        % empty, so that [W.speed] works in the run loop
    log_error(ERRF, 'wind generation', ME);
    extra{end+1} = ['wind generation: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E4X.txt)'];
end

% --- excitation sequence ----------------------------------------------------------------------
XF = fullfile(OUT, 'excitation.mat');
try
    X = excitation_E4X(DT, TMAX);
    save(XF, '-struct', 'X');
    X.sha = sha256_file(XF);
    extra{end+1} = sprintf('excitation: %d plateaus started before %g s, excitation.mat %s', X.n_plateaus, TMAX, X.sha);
catch ME
    X = [];
    log_error(ERRF, 'excitation', ME);
    extra{end+1} = ['excitation: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E4X.txt)'];
end

% --- runs (8, cases.order_amendment_1) --------------------------------------------------------
R = struct('name', {}, 'speed', {}, 'arm', {}, 'case_dir', {}, 'outb', {}, 'channels', {}, 'added', {}, ...
           'ok_run', {}, 'wall_s', {}, 'q1_same', {}, 'err', {}, 'wraplog', {}, 'ncalls', {}, 'nwarn', {}, ...
           'slx_sha', {}, 'outb_sha', {}, 'wraplog_sha', {}, 'status', {});
stopped = '';
for iu = 1:numel(SPEEDS)
    for ia = 1:numel(ARMS)
        u = SPEEDS(iu);  arm = ARMS{ia};
        r = struct('name', sprintf('U%02d_%s', u, arm), 'speed', u, 'arm', arm, 'case_dir', '', 'outb', '', ...
                   'channels', {{}}, 'added', {{}}, 'ok_run', false, 'wall_s', NaN, 'q1_same', false, 'err', '', ...
                   'wraplog', '', 'ncalls', NaN, 'nwarn', NaN, 'slx_sha', '', 'outb_sha', '', 'wraplog_sha', '', ...
                   'status', 'not executed');
        RUN_DIR = fullfile(OUT, 'runs', r.name);
        if isempty(stopped)                                                    % refusals before each run
            stopped = check_refs(REF);
            if isempty(stopped) && exist(RUN_DIR, 'dir'), stopped = ['run folder already exists: ' RUN_DIR]; end
            if isempty(stopped) && isempty(X), stopped = 'no excitation sequence'; end
            if ~isempty(stopped)
                stopped = sprintf('refused before %s: %s', r.name, stopped);
                extra{end+1} = stopped; %#ok<AGROW>
            end
        end
        w = W([W.speed] == u);
        if ~isempty(stopped)
            r.err = stopped;
        elseif numel(w) ~= 1 || ~w.ok
            r.err = 'no wind field';
        else
            try
                ip = PITCH([PITCH{:,1}] == u, 2);
                C = prepare_case_E3(ROOT, RUN_DIR, struct('mode', 'sfunc', 'tmax', TMAX, ...
                        'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', w.bts, 'bts_sha', w.bts_sha, 'copy_bts', false, ...
                        'num_crctn', 1, ...                                       % spec_E3 plant_configuration (amendment 4)
                        'init_pitch', ip{1}));                                    % spec_E4X campaign.plant (beta_eq_deg of E1)
                r.case_dir = C.case_dir;  r.channels = C.channels;  r.added = C.added;
                inputs = [C.manifest(:,1); {w.inp; w.bts; abs_(DLL_REL); abs_(CSV_REL); XF}; SFUN; WRAP];
                before = hash_list(inputs);
                write_lines(fullfile(C.case_dir, 'inputs_before.txt'), strcat(before, {'  '}, inputs));
                if strcmp(arm, 'X0'), P = zeros(numel(X.p), 2); else, P = [X.p, X.p_prev]; end   % excitation.X0: no excitation
                [r.ok_run, r.wall_s, r.err, r.slx_sha, st] = run_sfunc(C, DT, TMAX, abs_(DLL_REL), HFILE, ERRF, r.name, arm, P);
                after = hash_list(inputs);
                write_lines(fullfile(C.case_dir, 'inputs_after.txt'), strcat(after, {'  '}, inputs));
                r.q1_same = isequal(before, after);
                r.outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.SFunc.outb');
                r.wraplog = fullfile(C.case_dir, 'wrapper_log.mat');
                if exist(r.outb, 'file'), r.outb_sha = sha256_file(r.outb); end
                if exist(r.wraplog, 'file'), r.wraplog_sha = sha256_file(r.wraplog); end
                r.ncalls = st.ncalls;  r.nwarn = numel(st.warnings);
                if isempty(st.warnings), wl = {'none'}; else, wl = st.warnings(:); end
                write_lines(fullfile(C.case_dir, 'wrapper_warnings.txt'), wl);
                r.status = 'executed';
            catch ME
                if libisloaded('DISCON'), unloadlibrary('DISCON'); end
                log_error(ERRF, ['run ' r.name], ME);
                r.err = [strrep(ME.message, newline, ' ') ' (full report in errors_E4X.txt)'];
                r.status = 'error';
            end
        end
        fprintf('%s: %s, run %s, %.1f s, %g DISCON calls\n', r.name, r.status, yn(r.ok_run), r.wall_s, r.ncalls);
        R(end+1) = r; %#ok<AGROW>
    end
end
a = unique(cat(1, R.added));
if ~isempty(a), extra{end+1} = ['outlist_additions (every case): ' strjoin(a', ', ')]; end
save(fullfile(OUT, 'runs_E4X.mat'), 'R', 'W', 'X');

% --- analysis and end -------------------------------------------------------------------------
try
    analyse_E4X(OUT);
catch ME
    log_error(ERRF, 'analysis', ME);
    extra{end+1} = ['analysis: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E4X.txt)'];
end
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E4X.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function why = check_refs(F)
% refusals of the header, made before the campaign and again before each run; '' if all pass
why = '';
c = git_clean(F.root);
if ~isempty(c), why = ['openfast_q1/ is not clean in Git: ' strrep(c, newline, ' | ')]; return, end
S = {fullfile(F.ed4, 'spec_E4X.yaml'), F.spec_e4x; fullfile(F.ed3, 'spec_E3.yaml'), F.spec_e3; ...
     fullfile(F.ed3, 'spec_E3W.yaml'), F.wrap_spec; fullfile(F.ed2, 'spec_E2.yaml'), F.spec_e2};
for k = 1:size(S, 1)
    if ~strcmp(sha256_file(S{k,1}), S{k,2}), why = sprintf('%s SHA-256 differs from %s', S{k,1}, S{k,2}); return, end
end
for k = 1:size(F.bin_sha, 1)
    if ~strcmp(sha256_file(fullfile(F.bin_dir, F.bin_sha{k,1})), F.bin_sha{k,2})
        why = sprintf('%s SHA-256 differs from spec_E3 campaign.depends_on', F.bin_sha{k,1}); return
    end
end
if ~strcmp(sha256_file(F.dll), F.dll_sha), why = sprintf('DISCON.dll SHA-256 differs from %s', F.dll_sha); return, end
[stw, wc] = system(sprintf('git -C "%s" log -1 --format=%%H -- openfast_q1/E3/discon_wrapper.m openfast_q1/E3/discon.h', F.root));
if stw ~= 0 || ~startsWith(strtrim(wc), F.wrap_commit)
    why = sprintf('last commit of the wrapper files is %s, expected %s', strtrim(wc), F.wrap_commit); return
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', F.tb_dir));
if ~strcmp(strtrim(tb), F.tb_commit), why = sprintf('matlab-toolbox is not at %s', F.tb_commit); return, end
if ~strcmp(sha256_file(F.csv), F.csv_sha), why = sprintf('E1 CSV SHA-256 differs from %s', F.csv_sha); return, end
for k = 1:size(F.pitch, 1)
    b = read_beta_eq(F.csv, sprintf('%d', F.pitch{k,1}));
    if ~strcmp(sprintf('%.4f', b), F.pitch{k,2})
        why = sprintf('beta_eq_deg at %d m/s is %.10g, which does not round to %s', F.pitch{k,1}, b, F.pitch{k,2}); return
    end
end
end

function N = run_names(speeds, arms)
% run names in the order of spec_E4X cases.order_amendment_1
N = {};
for u = speeds
    for a = 1:numel(arms), N{end+1} = sprintf('U%02d_%s', u, arms{a}); end %#ok<AGROW>
end
end

function script = block_script(C, arm, DT, NP)
% MATLAB Function block of the arm (spec_E4X excitation.X0-X3, excitation.units, excitation.bounds,
% bounds_amendment_1, excitation.logging); input y = S-function outputs, parameter P = [p, p_prev]
% (deg) on the DT grid from t = 0 (signal_amendment_1); discon_wrapper unchanged
A_SPEED = 1.229096;       % rad/s, spec_E4X excitation.X1 (1 % of PC_RefSpd, DISCON.F90 l.77)
A_PITCH = 1.0;            % deg, spec_E4X excitation.A_pitch
GENEFF  = 0.944;          % electrical power as discon_wrapper (spec_E3W wrapper.records_out)
ix = @(name) find(strcmpi(C.channels, name));
switch arm
    case 'X0'   % no excitation (reference)
        arm_in  = 'gsd = gs;  bpd = bp;\n';
        arm_out = 'cmd0 = c(1);  cmd = cmd0;  pe = c(3);\n';
    case 'X1'   % DISCON receives GenSpeed + (A_speed/A_pitch) x p; command and torque unchanged; power from the true GenSpeed
        arm_in  = sprintf('gsd = gs + %.17g*pk;  bpd = bp;\n', A_SPEED/A_PITCH);
        arm_out = sprintf(['cmd0 = c(1);  cmd = cmd0;\n' ...
                           'if c(2) >= 0, pe = c(2)*gs*%.17g; else, pe = c(2)*gs/%.17g; end\n'], GENEFF, GENEFF);
    case 'X2'   % DISCON receives BldPitch1 + p x pi/180; command unchanged
        arm_in  = 'gsd = gs;  bpd = bp + pk*pi/180;\n';
        arm_out = 'cmd0 = c(1);  cmd = cmd0;  pe = c(3);\n';
    case 'X3'   % DISCON receives BldPitch1(k) - p(k-1) x pi/180; command c(1) + p(k) x pi/180, clipped to [0, 30 x pi/180] rad
        arm_in  = 'gsd = gs;  bpd = bp - pkm1*pi/180;\n';
        arm_out = ['cmd0 = c(1) + pk*pi/180;  cmd = min(max(cmd0, 0), 30*pi/180);  pe = c(3);\n' ...
                   'if cmd ~= cmd0, clip = 1; end\n'];
    otherwise
        error('run_E4X:arm', 'Unknown arm %s.', arm);
end
script = sprintf([ ...
    'function [u, g] = wrap(y, P)\n' ...
    '%%#codegen\n' ...
    '%% generated by run_E4X.m, arm %s (spec_E4X excitation.%s): discon_wrapper at every DT; channel indices from channels.txt\n' ...
    'coder.extrinsic(''discon_wrapper'');\n' ...
    't = y(%d);  bp = y(%d)*pi/180;  gs = y(%d)*pi/30;  hwv = sqrt(y(%d)^2 + y(%d)^2);\n' ...
    'k = round(t/%.17g) + 1;  k = min(max(k, 1), %d);\n' ...
    'pk = P(k, 1);  pkm1 = P(k, 2);  clip = 0;\n' ...
    arm_in ...
    'c = zeros(6, 1);\n' ...
    'c = discon_wrapper(''step'', t, bpd, gsd, hwv);\n' ...
    arm_out ...
    'u = zeros(51, 1);                  %% FAST_Library.h l.72-83\n' ...
    'u(1) = c(2);                       %% generator torque (N-m), wrapper.records_out\n' ...
    'u(2) = pe;                         %% electrical power (W)\n' ...
    'u(5) = cmd;  u(6) = cmd;  u(7) = cmd;   %% collective pitch command (rad)\n' ...
    'g = [pk; pkm1; gsd; bpd; cmd0; cmd; clip; pe; c];\n'], ...
    arm, arm, ix('Time'), ix('BldPitch1'), ix('GenSpeed'), ix('Wind1VelX'), ix('Wind1VelY'), DT, NP);
end

function [ok, wall, err, slx_sha, st] = run_sfunc(C, DT, tmax, dll, hfile, errf, tag, arm, P)
% one run on configuration O8, as run_sfunc of run_E2_V4data.m (copied from run_E3b.m), with the
% block of the arm and P as a parameter of the MATLAB Function block (model workspace); the block
% output g is logged at every DT by a To Workspace block; sim with CaptureErrors on, the log is saved
% whatever the end of the run; library loaded before and unloaded after the run, final call after
% the simulation
mdl = 'E4X_sfunc';
if bdIsLoaded(mdl), close_system(mdl, 0); end
new_system(mdl);
set_param(mdl, 'SolverType', 'Fixed-step', 'Solver', 'FixedStepDiscrete', ...
          'FixedStep', sprintf('%.17g', DT), 'StopTime', sprintf('%.17g', tmax), ...
          'SaveTime', 'off', 'SaveOutput', 'off', 'SaveState', 'off', 'SignalLogging', 'off');
add_block('simulink/User-Defined Functions/S-Function', [mdl '/FAST'], 'FunctionName', 'FAST_SFunc', ...
          'Parameters', sprintf('''%s'', %.17g, 0', C.fst, tmax));
add_block('simulink/User-Defined Functions/MATLAB Function', [mdl '/wrap']);
rt = sfroot;
m  = rt.find('-isa', 'Simulink.BlockDiagram', 'Name', mdl);
ch = m.find('-isa', 'Stateflow.EMChart', 'Path', [mdl '/wrap']);
if numel(ch) ~= 1, error('run_E4X:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
ch.Script = block_script(C, arm, DT, size(P, 1));
dp = ch.find('-isa', 'Stateflow.Data', 'Name', 'P');
if numel(dp) ~= 1, error('run_E4X:param', 'Data P of the MATLAB Function block not found.'); end
dp.Scope = 'Parameter';                                             % P read from the model workspace
assignin(get_param(mdl, 'ModelWorkspace'), 'P', P);
add_block('simulink/Sinks/To Workspace', [mdl '/log'], 'VariableName', 'wraplog', ...      % excitation.logging
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
        g = lg.signals.values;
        if ndims(g) == 3, g = reshape(permute(g, [3 1 2]), size(g, 3), []); end
        cols = {'p_deg', 'p_prev_deg', 'genspeed_to_discon_rad_s', 'bldpitch_to_discon_rad', ...       % excitation.logging
                'command_before_clip_rad', 'command_applied_rad', 'clipped', 'electrical_power_applied_W', ...
                'pitch_command_rad', 'torque_Nm', 'electrical_power_W', 'record45_rad', 'record47_Nm', 'aviFAIL'};
        if size(g, 2) ~= numel(cols), error('run_E4X:log', 'Block log has %d columns, expected %d.', size(g, 2), numel(cols)); end
        save(fullfile(C.case_dir, 'wrapper_log.mat'), 't', 'g', 'cols', 'arm');
    catch ME
        log_error(errf, [tag ' wrapper log'], ME);
        err = strtrim([err ' | wrapper log: ' strrep(ME.message, newline, ' ')]);
    end
end
close_system(mdl, 0);
clear('FAST_SFunc');
end

function h = hash_list(files)
h = cell(numel(files), 1);
for k = 1:numel(files)
    if exist(files{k}, 'file'), h{k} = sha256_file(files{k}); else, h{k} = 'missing'; end
end
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
% copied from run_E2_V4data.m
L = read_lines(f);
H = strsplit(strtrim(L{1}), ';');
jv = find(strcmp(H, 'vent_m_s'));  jb = find(strcmp(H, 'beta_eq_deg'));
if ~isscalar(jv) || ~isscalar(jb), error('run_E4X:csvhead', 'Columns vent_m_s and beta_eq_deg not found once in %s.', f); end
hit = {};
for k = 2:numel(L)
    F = strsplit(strtrim(L{k}), ';');
    if numel(F) == numel(H) && strcmp(F{jv}, speed), hit{end+1} = F{jb}; end %#ok<AGROW>
end
if numel(hit) ~= 1, error('run_E4X:csvrow', 'Row vent_m_s = %s found %d times in %s.', speed, numel(hit), f); end
beta = str2double(hit{1});
if ~isfinite(beta), error('run_E4X:csvval', 'beta_eq_deg at %s m/s is not a number.', speed); end
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
