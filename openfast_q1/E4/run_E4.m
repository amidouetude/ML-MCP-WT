function run_E4(resume_dir)
%RUN_E4  Single execution of the E4 dataset campaign (openfast_q1/E4/spec_E4.yaml): 70 closed-loop
%OpenFAST runs, 7 mean speeds x 5 seeds x arms X0 and X3, then the dataset build (build_dataset_E4).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E4');  run_E4                    % campaign Q1-E4-DATA-<date>-a
%   Resume mode (spec_E4 interruption), ONLY under its own authorisation, after an interruption:
%       >> addpath('openfast_q1/E4');  run_E4('results/Q1-E4-DATA-<date>-a')
%   The resumed campaign gets the id Q1-E4-DATA-<today>-<next letter>; it reads the completion
%   records of the interrupted campaign, runs only the runs that are missing or not completed, reuses
%   the .bts and the completed runs whose recorded SHA-256 values are unchanged, and refuses to start
%   if the code commit (last commit of CODE_PATHS) differs from the one recorded by that campaign.
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; OneDrive is running
%   or less than 15 GB are free on the drive of results/ (spec_E4 launch_conditions); the SHA-256 of
%   spec_E4.yaml, spec_E4X.yaml, spec_E3.yaml, spec_E3W.yaml or spec_E2.yaml differs; the S-function
%   binaries, TurbSim or DISCON.dll differ from their SHA-256 (spec_E3 campaign.depends_on); the last
%   commit of discon_wrapper.m and discon.h is not WRAP_COMMIT; matlab-toolbox (ReadFASTbinary) is not
%   at TB_COMMIT; the E1 CSV differs from CSV_SHA, or for one of the 7 speeds sprintf('%.4f',
%   beta_eq_deg) is not the string of PITCH; the campaign folder already exists. The same checks
%   (except the campaign folder) are made again before each run, with a run folder that must not
%   exist: if one fails, that run and the following ones are not executed and the reason is recorded.
%   Checks and values are those of run_E4X.m at commit 86f2029.
%
%   Steps, each run once, never retried, one simulation at a time:
%     wind      gen_wind_E3 (unchanged) with seeds [34001 34002 34003 34004 34005]: 35 TurbSim inputs
%               and fields at 12 to 24 m/s, UsableTime 660 (spec_E4 wind); W saved in wind_E4.mat
%     runs      70 runs in the order of spec_E4 arms.runs (speed, then seed, then X0 before X3), TMax
%               660 s, on configuration O8 (spec_E4 plant): case prepared by prepare_case_E3, unchanged
%               (mode 'sfunc', InflowWind file with the generated .bts, TMax 660, NumCrctn 0 -> 1,
%               InterpOrder 2 unchanged, BlPitch(1-3) 0 -> beta_eq_deg of E1 at the mean speed);
%               Simulink model and block of arms X0 and X3 as run_E4X.m (spec_E4 arms.X0, arms.X3);
%               X3: excitation_E4 with seed 100 x RandSeed1 + mean speed and 1200 durations, saved in
%               runs/<run>/excitation.mat (spec_E4 arms.X3); X0 and X3 of a speed and seed use the
%               same .bts (arms.runs)
%     log       at every DT: block log of run_E4X (14 columns) in runs/<run>/wrapper_log.mat
%               (spec_E4 signals.recorded)
%     inputs    SHA-256 of every input written before each run and recomputed after it
%     record    completion record of each run as soon as it ends, appended to completion_E4.csv and
%               written to runs/<run>/completion.txt (spec_E4 interruption)
%     dataset   build_dataset_E4 (spec_E4 usability, partition, signals, normalisation, format, quality)
%   Every catch appends getReport(ME, 'extended') to errors_E4.txt.
%   Writes in results/Q1-E4-DATA-<date>-<letter>/ (spec_E4 outputs): meta_E4.txt, wind/ (.inp, .bts,
%   TurbSim logs, wind_manifest.txt), wind_E4.mat, completion_E4.csv, runs/<run>/ (case copy, manifest,
%   model, .outb, wrapper_log.mat, excitation.mat for X3, wrapper_warnings.txt, inputs_before.txt,
%   inputs_after.txt, completion.txt), runs_E4.mat, and through build_dataset_E4 the dataset files;
%   errors_E4.txt if any.

SPEC_E4_SHA  = '73e07bca01ffce034a34c5b0d6b334eec48e603936a92fe7569f9d79ad885088';  % spec_E4, draft 3 adopted
SPEC_E4X_SHA = '656659dcc47c98803e606e6fbc333a28174b48409ca66c76c52875c2a38d76d6';  % spec_E4X, amendment 1 (arms.X3)
SPEC_E3_SHA  = '66f7f43ba385d8b2880401d61c6ea1e75601d9c82acbc001159158a96ae96ba4';  % spec_E3, amendment 6
WRAP_SPEC    = 'a78de8925221565c50f47ef458b60497891e21547d90d048f0cb38cd08bb0d86';  % spec_E3 campaign.depends_on.wrapper (spec_E3W)
SPEC_E2_SHA  = '6c09b3ef2df0d8dade7123caaa56e22c6ce248578518545793a8a44dd2d00515';  % spec_E2, amendment 7
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
TMAX      = 660;                              % s, spec_E4 wind.duration and plant
SPEEDS    = [12 14 16 18 20 22 24];           % m/s, spec_E4 wind.mean_speeds
SEEDS     = [34001 34002 34003 34004 34005];  % RandSeed1, spec_E4 wind.seeds
ARMS      = {'X0', 'X3'};                     % spec_E4 arms.runs (X0 before X3)
N_D       = 1200;                             % spec_E4 arms.X3, d = 0.5 + 2.5 x rand(1, 1200)
MIN_FREE  = 15e9;                             % bytes, spec_E4 launch_conditions (at least 15 GB free)
CSV_REL   = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';                              % spec_E4 plant (beta_eq_deg of E1)
CSV_SHA   = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';
PITCH     = {12, '3.6173'; 14, '8.5723'; 16, '12.0261'; 18, '14.9124'; ...                                 % m/s, beta_eq_deg (deg), as spec_E3
             20, '17.4663'; 22, '19.8512'; 24, '22.0761'};                                                 % E3b_region3_qualification.runs
CODE_PATHS = {'openfast_q1/E4/run_E4.m', 'openfast_q1/E4/excitation_E4.m', 'openfast_q1/E4/build_dataset_E4.m', ...   % code commit of the
              'openfast_q1/E4/spec_E4.yaml', 'openfast_q1/E4/spec_E4X.yaml', 'openfast_q1/E3/gen_wind_E3.m', ...         % campaign (spec_E4
              'openfast_q1/E3/prepare_case_E3.m', 'openfast_q1/E3/check_input_refs.m', 'openfast_q1/E3/discon_wrapper.m', ... % interruption: same
              'openfast_q1/E3/discon.h', 'openfast_q1/E3/spec_E3.yaml', 'openfast_q1/E3/spec_E3W.yaml', ...             % code commit)
              'openfast_q1/E2/spec_E2.yaml', 'openfast_q1/E2/rom_params.m', 'openfast_q1/E2/rom_torque_law.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
ED4  = fullfile(ROOT, 'openfast_q1', 'E4');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
SFUN = {fullfile(BIN_DIR, BIN_SHA{1,1}); fullfile(BIN_DIR, BIN_SHA{2,1})};    % S-function binaries (as run_E3b)
WRAP = fullfile(ED3, WRAP_FILES(:));                                         % wrapper files (as run_E3b)
REF  = struct('root', ROOT, 'specs', {{fullfile(ED4, 'spec_E4.yaml'), SPEC_E4_SHA; fullfile(ED4, 'spec_E4X.yaml'), SPEC_E4X_SHA; ...
              fullfile(ED3, 'spec_E3.yaml'), SPEC_E3_SHA; fullfile(ED3, 'spec_E3W.yaml'), WRAP_SPEC; ...
              fullfile(ED2, 'spec_E2.yaml'), SPEC_E2_SHA}}, 'bin_dir', BIN_DIR, 'bin_sha', {BIN_SHA}, ...
              'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'wrap_commit', WRAP_COMMIT, 'tb_dir', TB_DIR, ...
              'tb_commit', TB_COMMIT, 'csv', abs_(CSV_REL), 'csv_sha', CSV_SHA, 'pitch', {PITCH}, ...
              'results', fullfile(ROOT, 'results'), 'min_free', MIN_FREE);

% --- refusals and campaign id -----------------------------------------------------------------
why = check_refs(REF);
if ~isempty(why), error('run_E4:refused', 'Refused before the campaign: %s', why); end
code_commit = last_commit(ROOT, CODE_PATHS);
today = char(datetime('now', 'Format', 'yyyy-MM-dd'));
RES = [];                                                                     % resume mode (spec_E4 interruption)
if nargin == 0
    ID = ['Q1-E4-DATA-' today '-a'];                                          % spec_E4 campaign.id
else
    RES = read_resume(resume_dir, code_commit);
    ID = ['Q1-E4-DATA-' today '-' char(RES.letter + 1)];
end
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E4:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
[~, wc]   = system(sprintf('git -C "%s" log -1 --format=%%H -- openfast_q1/E3/discon_wrapper.m openfast_q1/E3/discon.h', ROOT));
M = {sprintf('campaign: %s', ID), 'purpose: closed-loop dataset for the six learned families of Q1 (spec_E4 campaign.purpose)', ...
     sprintf('head: %s', strtrim(head)), sprintf('code_commit: %s (last commit of %s)', code_commit, strjoin(CODE_PATHS, ', ')), ...
     'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), ...
     sprintf('free_space_bytes: %.0f (at least %.0f, spec_E4 launch_conditions)', free_bytes(REF.results), MIN_FREE), ...
     'launch_conditions not checked by the code (stated by the author in the launch block): mains power, sleep and hibernation disabled, Windows updates paused'};
if isempty(RES), M{end+1} = 'mode: new campaign'; else, M{end+1} = sprintf('mode: resume of %s (spec_E4 interruption)', RES.id); end
for k = 1:size(REF.specs, 1), M{end+1} = sprintf('spec: %s %s', strrep(REF.specs{k,1}, [ROOT filesep], ''), REF.specs{k,2}); end %#ok<AGROW>
for k = 1:numel(CODE_PATHS), M{end+1} = sprintf('code: %s %s', CODE_PATHS{k}, sha256_file(abs_(CODE_PATHS{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('wrapper: commit %s (last commit of discon_wrapper.m and discon.h)', strtrim(wc)), ...
         sprintf('input: %s %s', CSV_REL, CSV_SHA), sprintf('seeds: RandSeed1 %s (spec_E4 wind.seeds)', mat2str(SEEDS)), ...
         'plant: configuration O8, FAST_SFunc (PCMode 4, VSContrl 4), discon_wrapper at every DT, InterpOrder 2, NumCrctn 1, initial pitch beta_eq_deg of E1, TMax 660 s (spec_E4 plant)', ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_E4.txt'), M);

% --- environment (session only, as run_E3b) ---------------------------------------------------
addpath(ED2);  addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_E4.txt');      % full report of every catch
CF    = fullfile(OUT, 'completion_E4.csv');  % completion records (spec_E4 interruption)
write_lines(CF, {completion_header()});
extra = {};

% --- wind fields (spec_E4 wind; resume: .bts of the interrupted campaign reused if unchanged) -----
W = empty_wind();
reuse_bts = false(numel(SPEEDS), numel(SEEDS));
try
    if ~isempty(RES)
        W = RES.W;
        for k = 1:numel(W)
            ok = W(k).ok && exist(W(k).bts, 'file') && strcmp(sha256_file(W(k).bts), W(k).bts_sha);
            reuse_bts(SPEEDS == W(k).speed, SEEDS == W(k).seed) = ok;
        end
        extra{end+1} = sprintf('wind: %d of %d fields of %s reused (SHA-256 unchanged)', nnz(reuse_bts), numel(reuse_bts), RES.id);
    end
    if ~all(reuse_bts(:))
        Wn = gen_wind_E3(ROOT, fullfile(OUT, 'wind'), fullfile(BIN_DIR, 'TurbSim_x64.exe'), SEEDS);   % unchanged, seeds of spec_E4
        if numel(Wn) ~= numel(SPEEDS)*numel(SEEDS) || ~all(ismember([Wn.seed], SEEDS)) || ~all(ismember([Wn.speed], SPEEDS))
            error('run_E4:wind', 'gen_wind_E3 did not return one field per speed of %s and seed of %s.', mat2str(SPEEDS), mat2str(SEEDS));
        end
        if isempty(RES)
            W = Wn;
        else
            for k = 1:numel(Wn)                                                % replace only the fields not reused
                iu = SPEEDS == Wn(k).speed;  is = SEEDS == Wn(k).seed;
                if ~reuse_bts(iu, is), W([W.speed] == Wn(k).speed & [W.seed] == Wn(k).seed) = Wn(k); end
            end
        end
    end
catch ME
    W = empty_wind();
    log_error(ERRF, 'wind generation', ME);
    extra{end+1} = ['wind generation: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E4.txt)'];
end
save(fullfile(OUT, 'wind_E4.mat'), 'W', 'reuse_bts');

% --- runs (70, spec_E4 arms.runs) -------------------------------------------------------------
R = struct('name', {}, 'speed', {}, 'seed', {}, 'arm', {}, 'status', {}, 'source', {}, 'case_dir', {}, 'outb', {}, ...
           'outb_sha', {}, 'wraplog', {}, 'wraplog_sha', {}, 'bts', {}, 'bts_sha', {}, 'excitation', {}, ...
           'excitation_sha', {}, 'ok_run', {}, 'wall_s', {}, 'q1_same', {}, 'ncalls', {}, 'err', {});
stopped = '';
for iu = 1:numel(SPEEDS)
    for is = 1:numel(SEEDS)
        for ia = 1:numel(ARMS)
            u = SPEEDS(iu);  s = SEEDS(is);  arm = ARMS{ia};
            r = struct('name', sprintf('U%02d_S%d_%s', u, s, arm), 'speed', u, 'seed', s, 'arm', arm, ...
                       'status', 'not executed', 'source', ID, 'case_dir', '', 'outb', '', 'outb_sha', '', ...
                       'wraplog', '', 'wraplog_sha', '', 'bts', '', 'bts_sha', '', 'excitation', '', ...
                       'excitation_sha', '', 'ok_run', false, 'wall_s', NaN, 'q1_same', false, 'ncalls', NaN, 'err', '');
            w = W([W.speed] == u & [W.seed] == s);
            if isscalar(w), r.bts = w.bts;  r.bts_sha = w.bts_sha; end
            % resume: a completed run of the interrupted campaign is reused if its SHA-256 values are unchanged
            if ~isempty(RES) && reuse_bts(iu, is)
                [rr, ok] = reusable(RES.C, r.name, w.bts_sha);
                if ok
                    R(end+1) = rr; %#ok<AGROW>
                    append_completion(CF, rr);
                    fprintf('%s: reused from %s\n', r.name, RES.id);
                    continue
                end
            end
            RUN_DIR = fullfile(OUT, 'runs', r.name);
            if isempty(stopped)                                                % refusals before each run
                stopped = check_refs(REF);
                if isempty(stopped) && exist(RUN_DIR, 'dir'), stopped = ['run folder already exists: ' RUN_DIR]; end
                if ~isempty(stopped)
                    stopped = sprintf('refused before %s: %s', r.name, stopped);
                    extra{end+1} = stopped; %#ok<AGROW>
                end
            end
            if ~isempty(stopped)
                r.err = stopped;
            elseif numel(w) ~= 1 || ~w.ok
                r.err = 'no wind field';
            else
                try
                    ip = PITCH([PITCH{:,1}] == u, 2);
                    C = prepare_case_E3(ROOT, RUN_DIR, struct('mode', 'sfunc', 'tmax', TMAX, ...
                            'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', w.bts, 'bts_sha', w.bts_sha, 'copy_bts', false, ...
                            'num_crctn', 1, ...                                   % spec_E3 plant_configuration (amendment 4)
                            'init_pitch', ip{1}));                                % spec_E4 plant (beta_eq_deg of E1)
                    r.case_dir = C.case_dir;
                    np = round(TMAX/DT) + 1;
                    if strcmp(arm, 'X0')
                        P = zeros(np, 2);                                         % spec_E4 arms.X0: no excitation
                        xin = {};
                    else
                        X = excitation_E4(DT, TMAX, 100*s + u, N_D);              % spec_E4 arms.X3
                        r.excitation = fullfile(C.case_dir, 'excitation.mat');
                        save(r.excitation, '-struct', 'X');
                        r.excitation_sha = sha256_file(r.excitation);
                        P = [X.p, X.p_prev];
                        xin = {r.excitation};
                    end
                    inputs = [C.manifest(:,1); {w.inp; w.bts; abs_(DLL_REL); abs_(CSV_REL)}; xin(:); SFUN; WRAP];
                    before = hash_list(inputs);
                    write_lines(fullfile(C.case_dir, 'inputs_before.txt'), strcat(before, {'  '}, inputs));
                    [r.ok_run, r.wall_s, r.err, ~, st] = run_sfunc(C, DT, TMAX, abs_(DLL_REL), HFILE, ERRF, r.name, arm, P);
                    after = hash_list(inputs);
                    write_lines(fullfile(C.case_dir, 'inputs_after.txt'), strcat(after, {'  '}, inputs));
                    r.q1_same = isequal(before, after);
                    r.outb = fullfile(fileparts(C.fst), '5MW_Land_DLL_WTurb.SFunc.outb');
                    r.wraplog = fullfile(C.case_dir, 'wrapper_log.mat');
                    if exist(r.outb, 'file'), r.outb_sha = sha256_file(r.outb); end
                    if exist(r.wraplog, 'file'), r.wraplog_sha = sha256_file(r.wraplog); end
                    r.ncalls = st.ncalls;
                    if isempty(st.warnings), wl = {'none'}; else, wl = st.warnings(:); end
                    write_lines(fullfile(C.case_dir, 'wrapper_warnings.txt'), wl);
                    if r.ok_run && ~isempty(r.outb_sha) && ~isempty(r.wraplog_sha), r.status = 'completed'; else, r.status = 'not completed'; end
                catch ME
                    if libisloaded('DISCON'), unloadlibrary('DISCON'); end
                    log_error(ERRF, ['run ' r.name], ME);
                    r.err = [strrep(ME.message, newline, ' ') ' (full report in errors_E4.txt)'];
                    r.status = 'error';
                end
            end
            append_completion(CF, r);                                          % spec_E4 interruption
            if ~isempty(r.case_dir), write_lines(fullfile(r.case_dir, 'completion.txt'), {completion_header(), completion_line(r)}); end
            fprintf('%s: %s, %.1f s, %g DISCON calls\n', r.name, r.status, r.wall_s, r.ncalls);
            R(end+1) = r; %#ok<AGROW>
        end
    end
end
save(fullfile(OUT, 'runs_E4.mat'), 'R', 'W', 'RES');

% --- dataset and end --------------------------------------------------------------------------
try
    build_dataset_E4(OUT);
catch ME
    log_error(ERRF, 'dataset', ME);
    extra{end+1} = ['dataset: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_E4.txt)'];
end
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_E4.txt'), [extra, {sprintf('runs: %d completed, %d reused, %d other', ...
             nnz(strcmp({R.status}, 'completed') & strcmp({R.source}, ID)), nnz(~strcmp({R.source}, ID)), ...
             nnz(~strcmp({R.status}, 'completed'))), sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function why = check_refs(F)
% refusals of the header, made before the campaign and again before each run; '' if all pass
why = '';
c = git_clean(F.root);
if ~isempty(c), why = ['openfast_q1/ is not clean in Git: ' strrep(c, newline, ' | ')]; return, end
[~, tl] = system('tasklist /FI "IMAGENAME eq OneDrive.exe" /NH');
if contains(tl, 'OneDrive.exe', 'IgnoreCase', true), why = 'OneDrive is running (spec_E4 launch_conditions)'; return, end
fb = free_bytes(F.results);
if ~(fb >= F.min_free), why = sprintf('%.0f bytes free on the drive of results/, at least %.0f required (spec_E4 launch_conditions)', fb, F.min_free); return, end
for k = 1:size(F.specs, 1)
    if ~strcmp(sha256_file(F.specs{k,1}), F.specs{k,2}), why = sprintf('%s SHA-256 differs from %s', F.specs{k,1}, F.specs{k,2}); return, end
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

function RES = read_resume(d, code_commit)
% interrupted campaign to resume (spec_E4 interruption): id, suffix letter, code commit check,
% completion records and wind fields; error if anything is missing or the code commit differs
[~, id] = fileparts(char(d));
tok = regexp(id, '^Q1-E4-DATA-\d{4}-\d{2}-\d{2}-([a-y])$', 'tokens', 'once');
if isempty(tok), error('run_E4:resume', 'The folder %s is not a campaign Q1-E4-DATA-<date>-<letter>.', d); end
mf = fullfile(d, 'meta_E4.txt');  cf = fullfile(d, 'completion_E4.csv');  wf = fullfile(d, 'wind_E4.mat');
if ~exist(mf, 'file') || ~exist(cf, 'file') || ~exist(wf, 'file')
    error('run_E4:resume', 'meta_E4.txt, completion_E4.csv or wind_E4.mat is missing in %s.', d);
end
ml = read_lines(mf);
cl = ml(startsWith(ml, 'code_commit: '));
if numel(cl) ~= 1, error('run_E4:resume', 'No single code_commit line in %s.', mf); end
cc = regexp(cl{1}, '^code_commit: ([0-9a-f]{40})', 'tokens', 'once');
if isempty(cc) || ~strcmp(cc{1}, code_commit)
    error('run_E4:resume', 'Code commit of %s differs from the current one %s (spec_E4 interruption: same code commit).', id, code_commit);
end
L = load(wf, 'W');
C = readtable(cf, 'Delimiter', ';', 'TextType', 'string', 'Format', repmat('%s', 1, numel(strsplit(completion_header(), ';'))));
for n = string(C.Properties.VariableNames)
    v = C.(n);  v(ismissing(v)) = "";  C.(n) = v;                  % empty fields read as ""
end
RES = struct('id', id, 'letter', tok{1}, 'W', L.W, 'C', C);
end

function [r, ok] = reusable(C, name, bts_sha)
% completed run of the interrupted campaign, reused if its .bts and its recorded SHA-256 values are
% unchanged (spec_E4 interruption)
r = [];  ok = false;
i = find(C.run == name & C.status == "completed", 1, 'last');
if isempty(i), return, end
c = C(i, :);
if c.bts_sha ~= bts_sha || ~exist(c.outb, 'file') || ~exist(c.wraplog, 'file'), return, end
if ~strcmp(sha256_file(char(c.outb)), c.outb_sha) || ~strcmp(sha256_file(char(c.wraplog)), c.wraplog_sha), return, end
if strlength(c.excitation) > 0 && (~exist(c.excitation, 'file') || ~strcmp(sha256_file(char(c.excitation)), c.excitation_sha)), return, end
r = struct('name', char(c.run), 'speed', str2double(c.speed), 'seed', str2double(c.seed), 'arm', char(c.arm), ...
           'status', 'completed', 'source', char(c.source), 'case_dir', char(c.case_dir), 'outb', char(c.outb), ...
           'outb_sha', char(c.outb_sha), 'wraplog', char(c.wraplog), 'wraplog_sha', char(c.wraplog_sha), ...
           'bts', char(c.bts), 'bts_sha', char(c.bts_sha), 'excitation', char(c.excitation), ...
           'excitation_sha', char(c.excitation_sha), 'ok_run', true, 'wall_s', str2double(c.wall_s), ...
           'q1_same', strcmp(c.q1_same, 'true'), 'ncalls', str2double(c.ncalls), 'err', '');
ok = true;
end

function h = completion_header()
h = 'run;speed;seed;arm;status;source;case_dir;outb;outb_sha;wraplog;wraplog_sha;bts;bts_sha;excitation;excitation_sha;ok_run;wall_s;q1_same;ncalls;err';
end

function s = completion_line(r)
% one completion record (spec_E4 interruption); ';' removed from the free text
s = strjoin({r.name, sprintf('%d', r.speed), sprintf('%d', r.seed), r.arm, r.status, r.source, r.case_dir, ...
             r.outb, r.outb_sha, r.wraplog, r.wraplog_sha, r.bts, r.bts_sha, r.excitation, r.excitation_sha, ...
             tf(r.ok_run), sprintf('%.1f', r.wall_s), tf(r.q1_same), sprintf('%g', r.ncalls), strrep(r.err, ';', ',')}, ';');
end

function append_completion(f, r)
append_lines(f, {completion_line(r)});
end

function s = tf(b)
if b, s = 'true'; else, s = 'false'; end
end

function W = empty_wind()
% empty wind struct with the fields of gen_wind_E3, so that [W.speed] works in the run loop
W = struct('speed', {}, 'seed', {}, 'name', {}, 'inp', {}, 'bts', {}, 'inp_sha', {}, 'bts_sha', {}, ...
           'ok', {}, 'wall_s', {}, 'err', {});
end

function c = last_commit(root, paths)
% last commit touching the code and spec files of the campaign (spec_E4 interruption: same code commit)
[st, c] = system(sprintf('git -C "%s" log -1 --format=%%H -- %s', root, strjoin(paths, ' ')));
c = strtrim(c);
if st ~= 0 || isempty(regexp(c, '^[0-9a-f]{40}$', 'once')), error('run_E4:commit', 'Code commit not found: %s', c); end
end

function b = free_bytes(d)
% usable space on the drive of d (spec_E4 launch_conditions)
b = double(java.io.File(d).getUsableSpace());
end

function script = block_script(C, arm, DT, NP)
% MATLAB Function block of arms X0 and X3, copied from run_E4X.m at commit 86f2029 (spec_E4 arms.X0,
% arms.X3, spec_E4X excitation.X0, excitation.X3, excitation.units, bounds_amendment_1,
% excitation.logging); input y = S-function outputs, parameter P = [p, p_prev] (deg) on the DT grid
% from t = 0; discon_wrapper unchanged
ix = @(name) find(strcmpi(C.channels, name));
switch arm
    case 'X0'   % no excitation (reference)
        arm_in  = 'gsd = gs;  bpd = bp;\n';
        arm_out = 'cmd0 = c(1);  cmd = cmd0;  pe = c(3);\n';
    case 'X3'   % DISCON receives BldPitch1(k) - p(k-1) x pi/180; command c(1) + p(k) x pi/180, clipped to [0, 30 x pi/180] rad
        arm_in  = 'gsd = gs;  bpd = bp - pkm1*pi/180;\n';
        arm_out = ['cmd0 = c(1) + pk*pi/180;  cmd = min(max(cmd0, 0), 30*pi/180);  pe = c(3);\n' ...
                   'if cmd ~= cmd0, clip = 1; end\n'];
    otherwise
        error('run_E4:arm', 'Unknown arm %s.', arm);
end
script = sprintf([ ...
    'function [u, g] = wrap(y, P)\n' ...
    '%%#codegen\n' ...
    '%% generated by run_E4.m, arm %s (spec_E4 arms.%s): discon_wrapper at every DT; channel indices from channels.txt\n' ...
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
% one run on configuration O8, copied from run_E4X.m at commit 86f2029 (model name E4_sfunc)
mdl = 'E4_sfunc';
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
if numel(ch) ~= 1, error('run_E4:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
ch.Script = block_script(C, arm, DT, size(P, 1));
dp = ch.find('-isa', 'Stateflow.Data', 'Name', 'P');
if numel(dp) ~= 1, error('run_E4:param', 'Data P of the MATLAB Function block not found.'); end
dp.Scope = 'Parameter';                                             % P read from the model workspace
assignin(get_param(mdl, 'ModelWorkspace'), 'P', P);
add_block('simulink/Sinks/To Workspace', [mdl '/log'], 'VariableName', 'wraplog', ...      % spec_E4 signals.recorded
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
        cols = {'p_deg', 'p_prev_deg', 'genspeed_to_discon_rad_s', 'bldpitch_to_discon_rad', ...       % block log of run_E4X
                'command_before_clip_rad', 'command_applied_rad', 'clipped', 'electrical_power_applied_W', ...
                'pitch_command_rad', 'torque_Nm', 'electrical_power_W', 'record45_rad', 'record47_Nm', 'aviFAIL'};
        if size(g, 2) ~= numel(cols), error('run_E4:log', 'Block log has %d columns, expected %d.', size(g, 2), numel(cols)); end
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
% copied from run_E4X.m
L = read_lines(f);
H = strsplit(strtrim(L{1}), ';');
jv = find(strcmp(H, 'vent_m_s'));  jb = find(strcmp(H, 'beta_eq_deg'));
if ~isscalar(jv) || ~isscalar(jb), error('run_E4:csvhead', 'Columns vent_m_s and beta_eq_deg not found once in %s.', f); end
hit = {};
for k = 2:numel(L)
    F = strsplit(strtrim(L{k}), ';');
    if numel(F) == numel(H) && strcmp(F{jv}, speed), hit{end+1} = F{jb}; end %#ok<AGROW>
end
if numel(hit) ~= 1, error('run_E4:csvrow', 'Row vent_m_s = %s found %d times in %s.', speed, numel(hit), f); end
beta = str2double(hit{1});
if ~isfinite(beta), error('run_E4:csvval', 'beta_eq_deg at %s m/s is not a number.', speed); end
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
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(char(p)).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
