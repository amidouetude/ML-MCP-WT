function run_E2_V4data()
%RUN_E2_V4DATA  Single execution of the data campaign of E2 V4-b, model v2 (openfast_q1/E2/spec_E2.yaml,
%validation.V4_turbulent_segments.V4b_data_model_v2, amendment 7).
%
%   Run ONCE by the author from the repository root, after the code review (separate authorisation):
%       >> addpath('openfast_q1/E2');  run_E2_V4data
%
%   Data campaign, no verdict: 21 new turbulent runs on configuration O8 as spec_E3
%   E3b_region3_qualification (wind_generation, mean_speeds, duration, runs with initial pitch beta_eq,
%   NumCrctn 1, TMax 660 s), with RandSeed1 in {32001, 32002, 32003} (V4b_data_model_v2), reserved for
%   E2 V4-b and excluded from E4. The offline V4-b analysis (V4b_model_v2) is not part of this script.
%
%   Refuses to start (error, nothing written) if: openfast_q1/ is not clean in Git; the SHA-256 of
%   spec_E2.yaml, spec_E3.yaml or spec_E3W.yaml differs from SPEC_E2_SHA, SPEC_E3_SHA, WRAP_SPEC; the
%   S-function binaries, TurbSim or DISCON.dll differ from their SHA-256 (spec_E3 campaign.depends_on);
%   the last commit of discon_wrapper.m and discon.h is not WRAP_COMMIT (campaign.depends_on.wrapper);
%   matlab-toolbox (ReadFASTbinary) is not at TB_COMMIT; the E1 CSV differs from CSV_SHA, or for one of
%   the 7 speeds sprintf('%.4f', beta_eq_deg) is not the string of PITCH (spec_E3
%   E3b_region3_qualification.runs, amendment 6); the campaign folder already exists. Checks and values
%   are those of run_E3b.m at commit d628306.
%
%   Steps, each run once, never retried, one simulation at a time:
%     wind    gen_wind_E3 with seeds [32001 32002 32003]: 21 TurbSim inputs and fields (spec_E3
%             E3b_region3_qualification.wind_generation, mean_speeds; spec_E2 V4b_data_model_v2)
%     runs    21 runs (7 speeds x 3 seeds), no repetition, in the order of gen_wind_E3, on spec_E3
%             E3b_region3_qualification.plant_configuration (configuration O8): case prepared by
%             prepare_case_E3 (mode 'sfunc', InflowWind file with the generated .bts, TMax = 660 s,
%             NumCrctn 0 -> 1, InterpOrder 2 unchanged, BlPitch(1-3) 0 -> beta_eq_deg of E1 at the mean
%             speed), RtVAvgxh in the AeroDyn OutList (channels.required of spec_E3, step 4 of
%             prepare_case_E3), Simulink model and wrapper log as in run_E3b.m (run_sfunc copied)
%     inputs  SHA-256 of every input (case copy, .inp, .bts, DLL, E1 CSV, S-function binaries, wrapper
%             files) written before each run and recomputed after it, as in run_E3b.m
%     analyse analyse_V4data (below), no verdict: per run, .outb read with OutList and units checked
%             (as analyse_E3b.m, plus RtVAvgxh in m/s); spec_E3 Q2_execution and Q2b_pitch_loop (whole
%             record); usable = Q2 and Q2b pass (V4b_data_model_v2); spec_E3 Q3_power and Q4_overspeed
%             reported only; SHA-256 of the .outb. A mean speed with a run missing or not usable is
%             reported as not evaluated (V4b_data_model_v2).
%   Every catch appends getReport(ME, 'extended') to errors_V4data.txt.
%   Writes in results/Q1-E2-V4DATA-<date>-a/: meta_V4data.txt, wind/ (.inp, .bts, TurbSim logs,
%   wind_manifest.txt), runs/<run>/ (case copy, manifest, model, .outb, wrapper_log.mat,
%   wrapper_warnings.txt, inputs_before.txt, inputs_after.txt, summary.csv), runs_V4data.mat,
%   summary_V4data.csv, report_V4data.txt, errors_V4data.txt if any.

SPEC_E2_SHA = '6c09b3ef2df0d8dade7123caaa56e22c6ce248578518545793a8a44dd2d00515';  % spec_E2, amendment 7
SPEC_E3_SHA = '66f7f43ba385d8b2880401d61c6ea1e75601d9c82acbc001159158a96ae96ba4';  % spec_E3, amendment 6
WRAP_SPEC   = 'a78de8925221565c50f47ef458b60497891e21547d90d048f0cb38cd08bb0d86';  % spec_E3 campaign.depends_on.wrapper (spec_E3W)
BIN_DIR   = 'C:\dev\openfast-bin';
BIN_SHA   = {'FAST_SFunc.mexw64',         '16b628c493baf4b716cfe2373f320f72f5859b38718b2dc3da455befb3112297';   % campaign.depends_on.sfunction
             'OpenFAST-Simulink_x64.dll', '2d61ae5e72c21376d87c95489a4db22d95e4c3b3d9f1aea92a8fee6daa0d093d';   % campaign.depends_on.sfunction
             'TurbSim_x64.exe',           '5f70b3e2d50cbe09ad37d98569443a7d6f1b7a97c214bf21bbd9533cf2f29df2'};  % campaign.depends_on.turbsim
DLL_REL   = 'results/Q1-E3-DISCON-BUILD-2026-10-09-a/build/DISCON.dll';                                     % campaign.depends_on.discon
DLL_SHA   = 'b922907959c41a8f1fc9db8e68b43e189ce93eabff4fa0fc2da1b83d18c8671e';
TB_DIR    = 'C:\dev\matlab-toolbox';
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';                                                    % ReadFASTbinary, as in run_E3b.m
WRAP_COMMIT = '11f0133';                                                                                  % campaign.depends_on.wrapper
WRAP_FILES = {'discon_wrapper.m', 'discon.h'};                                                             % campaign.depends_on.wrapper
DT        = 0.00625;                          % s, spec_E3W wrapper.period
TMAX      = 660;                              % s, spec_E3 E3b_region3_qualification.duration and .runs
SEEDS     = [32001 32002 32003];              % RandSeed1, spec_E2 validation.V4_turbulent_segments.V4b_data_model_v2
CSV_REL   = 'results/Q1-E1-AEROMAP-2026-10-08-a/analyse/C3_C4_par_vent.csv';                              % spec_E3 E3b_region3_qualification.runs (amendment 6)
CSV_SHA   = '46bcc04149a2fbfbbc95cd3c11b5a7a3acc4b96b0cd21011be5ceeb871be671e';
PITCH     = {12, '3.6173'; 14, '8.5723'; 16, '12.0261'; 18, '14.9124'; ...                                 % m/s, beta_eq_deg (deg) with four
             20, '17.4663'; 22, '19.8512'; 24, '22.0761'};                                                 % decimals, spec_E3 E3b_region3_qualification.runs
CODE_E3 = {'prepare_case_E3.m', 'gen_wind_E3.m', 'discon_wrapper.m', 'discon.h', 'check_input_refs.m', 'spec_E3W.yaml'};
CODE_E2 = {'run_E2_V4data.m'};

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
ED2  = fullfile(ROOT, 'openfast_q1', 'E2');
ED3  = fullfile(ROOT, 'openfast_q1', 'E3');
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
SFUN = {fullfile(BIN_DIR, BIN_SHA{1,1}); fullfile(BIN_DIR, BIN_SHA{2,1})};    % S-function binaries (as run_E3b)
WRAP = fullfile(ED3, WRAP_FILES(:));                                         % wrapper files (as run_E3b)

% --- refusals ---------------------------------------------------------------------------------
if ~isempty(git_clean(ROOT)), error('run_E2_V4data:dirty', 'openfast_q1/ is not clean in Git.'); end
if ~strcmp(sha256_file(fullfile(ED2, 'spec_E2.yaml')), SPEC_E2_SHA)
    error('run_E2_V4data:spec_E2', 'spec_E2.yaml SHA-256 differs from %s.', SPEC_E2_SHA);
end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3.yaml')), SPEC_E3_SHA)
    error('run_E2_V4data:spec_E3', 'spec_E3.yaml SHA-256 differs from %s.', SPEC_E3_SHA);
end
if ~strcmp(sha256_file(fullfile(ED3, 'spec_E3W.yaml')), WRAP_SPEC)
    error('run_E2_V4data:wrapspec', 'spec_E3W.yaml SHA-256 differs from %s (campaign.depends_on.wrapper).', WRAP_SPEC);
end
for k = 1:size(BIN_SHA, 1)
    if ~strcmp(sha256_file(fullfile(BIN_DIR, BIN_SHA{k,1})), BIN_SHA{k,2})
        error('run_E2_V4data:binary', '%s SHA-256 differs from spec_E3 campaign.depends_on.', BIN_SHA{k,1});
    end
end
if ~strcmp(sha256_file(abs_(DLL_REL)), DLL_SHA), error('run_E2_V4data:dll', 'DISCON.dll SHA-256 differs from %s.', DLL_SHA); end
[stw, wc] = system(sprintf('git -C "%s" log -1 --format=%%H -- openfast_q1/E3/discon_wrapper.m openfast_q1/E3/discon.h', ROOT));
if stw ~= 0 || ~startsWith(strtrim(wc), WRAP_COMMIT)
    error('run_E2_V4data:wrapper', 'Last commit of the wrapper files is %s, expected %s (campaign.depends_on.wrapper).', strtrim(wc), WRAP_COMMIT);
end
[~, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if ~strcmp(strtrim(tb), TB_COMMIT), error('run_E2_V4data:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT); end
if ~strcmp(sha256_file(abs_(CSV_REL)), CSV_SHA), error('run_E2_V4data:csv', 'E1 CSV SHA-256 differs from %s.', CSV_SHA); end
beta = zeros(size(PITCH, 1), 1);
for k = 1:size(PITCH, 1)
    beta(k) = read_beta_eq(abs_(CSV_REL), sprintf('%d', PITCH{k,1}));
    if ~strcmp(sprintf('%.4f', beta(k)), PITCH{k,2})
        error('run_E2_V4data:beta', 'beta_eq_deg at %d m/s is %.10g, which does not round to %s.', PITCH{k,1}, beta(k), PITCH{k,2});
    end
end
ID  = ['Q1-E2-V4DATA-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];   % spec_E2 V4b_data_model_v2
OUT = fullfile(ROOT, 'results', ID);
if exist(OUT, 'dir'), error('run_E2_V4data:exists', 'Campaign folder already exists: %s', OUT); end
fprintf('%s\n', ID);
mkdir(OUT);

% --- meta (start) -----------------------------------------------------------------------------
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));
M = {sprintf('campaign: %s', ID), 'purpose: data of E2 V4-b, model v2 (spec_E2 validation.V4_turbulent_segments.V4b_data_model_v2, amendment 7); no verdict', ...
     sprintf('head: %s', strtrim(head)), 'clean_before: clean (openfast_q1/)', sprintf('start: %s', stamp()), ...
     sprintf('spec: openfast_q1/E2/spec_E2.yaml %s', SPEC_E2_SHA), sprintf('spec: openfast_q1/E3/spec_E3.yaml %s', SPEC_E3_SHA), ...
     sprintf('seeds: RandSeed1 %s (V4b_data_model_v2), reserved for E2 V4-b and excluded from E4', mat2str(SEEDS))};
for k = 1:numel(CODE_E2), M{end+1} = sprintf('code: openfast_q1/E2/%s %s', CODE_E2{k}, sha256_file(fullfile(ED2, CODE_E2{k}))); end %#ok<AGROW>
for k = 1:numel(CODE_E3), M{end+1} = sprintf('code: openfast_q1/E3/%s %s', CODE_E3{k}, sha256_file(fullfile(ED3, CODE_E3{k}))); end %#ok<AGROW>
for k = 1:size(BIN_SHA, 1), M{end+1} = sprintf('binary: %s %s', fullfile(BIN_DIR, BIN_SHA{k,1}), BIN_SHA{k,2}); end %#ok<AGROW>
pl = strjoin(cellfun(@(u, p) sprintf('%d m/s %s', u, p), PITCH(:,1), PITCH(:,2), 'UniformOutput', false), ', ');
M = [M, {sprintf('input: %s %s', DLL_REL, DLL_SHA), sprintf('wrapper: commit %s (last commit of discon_wrapper.m and discon.h)', strtrim(wc)), ...
         sprintf('input: %s %s, beta_eq_deg written as: %s deg', CSV_REL, CSV_SHA, pl), ...
         'plant_configuration: O8, FAST_SFunc (PCMode 4, VSContrl 4), discon_wrapper at every DT with the measured BldPitch1, InterpOrder 2, NumCrctn 1 in the .fst copy, initial pitch beta_eq_deg of E1 at the mean speed (spec_E3 amendment 6)', ...
         sprintf('matlab_toolbox: %s', TB_COMMIT), ...
         sprintf('matlab: %s', version), sprintf('machine: %s', strtrim(getenv('COMPUTERNAME')))}];
write_lines(fullfile(OUT, 'meta_V4data.txt'), M);

% --- environment (session only, as run_E3b) ---------------------------------------------------
addpath(ED3);  addpath(BIN_DIR);  addpath(fullfile(TB_DIR, 'Utilities'));
setenv('PATH', [BIN_DIR ';' getenv('PATH')]);
cache0 = Simulink.fileGenControl('getConfig');
Simulink.fileGenControl('set', 'CacheFolder', OUT, 'CodeGenFolder', OUT);
restore = onCleanup(@() Simulink.fileGenControl('set', 'CacheFolder', cache0.CacheFolder, ...
                                                'CodeGenFolder', cache0.CodeGenFolder));
HFILE = fullfile(ED3, 'discon.h');
ERRF  = fullfile(OUT, 'errors_V4data.txt');     % full report of every catch

% --- wind fields ------------------------------------------------------------------------------
extra = {};
try
    W = gen_wind_E3(ROOT, fullfile(OUT, 'wind'), fullfile(BIN_DIR, 'TurbSim_x64.exe'), SEEDS);
    if ~all(ismember([W.seed], SEEDS))
        error('run_E2_V4data:seeds', 'gen_wind_E3 returned a seed outside %s.', mat2str(SEEDS));
    end
catch ME
    W = [];
    log_error(ERRF, 'wind generation', ME);
    extra{end+1} = ['wind generation: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_V4data.txt)'];
end

% --- runs (21, no repetition, in the order of gen_wind_E3) ------------------------------------
R = struct('name', {}, 'speed', {}, 'seed', {}, 'case_dir', {}, 'outb', {}, 'channels', {}, ...
           'added', {}, 'ok_run', {}, 'wall_s', {}, 'q1_same', {}, 'err', {}, 'wraplog', {}, 'ncalls', {}, ...
           'nwarn', {}, 'slx_sha', {});
for q = 1:numel(W)
    w = W(q);
    r = struct('name', w.name, 'speed', w.speed, 'seed', w.seed, 'case_dir', '', 'outb', '', ...
               'channels', {{}}, 'added', {{}}, 'ok_run', false, 'wall_s', NaN, 'q1_same', false, 'err', '', ...
               'wraplog', '', 'ncalls', NaN, 'nwarn', NaN, 'slx_sha', '');
    if ~w.ok
        r.err = ['no wind field: ' w.err];
    else
        try
            ip = PITCH([PITCH{:,1}] == w.speed, 2);                                       % spec_E3 E3b_region3_qualification.runs (amendment 6)
            if numel(ip) ~= 1, error('run_E2_V4data:pitch', 'No initial pitch for %g m/s.', w.speed); end
            C = prepare_case_E3(ROOT, fullfile(OUT, 'runs', r.name), struct('mode', 'sfunc', 'tmax', TMAX, ...
                    'dll', abs_(DLL_REL), 'dll_sha', DLL_SHA, 'bts', w.bts, 'bts_sha', w.bts_sha, 'copy_bts', false, ...
                    'num_crctn', 1, ...                                                   % spec_E3 plant_configuration (amendment 4)
                    'init_pitch', ip{1}));                                                % spec_E3 E3b_region3_qualification.runs (amendment 6)
            r.case_dir = C.case_dir;  r.channels = C.channels;  r.added = C.added;
            inputs = [C.manifest(:,1); {w.inp; w.bts; abs_(DLL_REL); abs_(CSV_REL)}; SFUN; WRAP];   % as run_E3b
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
            r.err = [strrep(ME.message, newline, ' ') ' (full report in errors_V4data.txt)'];
        end
    end
    fprintf('%s: run %s, %.1f s, %g DISCON calls\n', r.name, yn(r.ok_run), r.wall_s, r.ncalls);
    R(end+1) = r; %#ok<AGROW>
end
if ~isempty(R)
    a = unique(cat(1, R.added));
    if ~isempty(a), extra{end+1} = ['outlist_additions (every case): ' strjoin(a', ', ')]; end
end
save(fullfile(OUT, 'runs_V4data.mat'), 'R', 'W');

% --- analysis and end -------------------------------------------------------------------------
try
    analyse_V4data(OUT, R, W, ERRF);
catch ME
    log_error(ERRF, 'analysis', ME);
    extra{end+1} = ['analysis: error: ' strrep(ME.message, newline, ' ') ' (full report in errors_V4data.txt)'];
end
c2 = git_clean(ROOT);
if isempty(c2), ca = 'clean'; else, ca = ['NOT CLEAN: ' strrep(c2, newline, ' | ')]; end
append_lines(fullfile(OUT, 'meta_V4data.txt'), [extra, {sprintf('end: %s', stamp()), ['clean_after: ' ca]}]);
end

% =============================================================================================
function analyse_V4data(OUT, R, W, errf)
% data-campaign analysis, no verdict (spec_E2 validation.V4_turbulent_segments.V4b_data_model_v2)
%   per run: .outb read, OutList and units checked (as analyse_E3b.m, plus RtVAvgxh in m/s);
%   Q2   spec_E3 criteria.Q2_execution: run completed, t_end >= TMax - DT/2, all outputs finite
%   Q2b  spec_E3 criteria.Q2b_pitch_loop over the whole record (q2b_pitch_loop of analyse_E3b.m)
%   usable = Q2 and Q2b pass; a mean speed with a run missing, not read or not usable is not evaluated
%   Q3   spec_E3 criteria.Q3_power, reported only: mean speeds >= 14 m/s, mean of GenTq x 1000 x
%        GenSpeed x pi/30 after 60 s within VS_RtPwr +/- 2 %
%   Q4   spec_E3 criteria.Q4_overspeed, reported only: max RotSpeed after 60 s <= 1.2 x 12.1 rpm
%   Writes OUT/summary_V4data.csv, OUT/report_V4data.txt and runs/<run>/summary.csv.
TMAX     = 660;                 % s, spec_E3 E3b_region3_qualification.runs
T_EXCL   = 60;                  % s, spec_E3 E3b_region3_qualification.duration
DT       = 0.00625;             % s, spec_E3 channels.output_format
Q3_FROM  = 14;                  % m/s, spec_E3 criteria.Q3_power
VS_RTPWR = 5296610;             % W, spec_E3 criteria.Q3_power (DISCON.F90 l.96)
Q3_TOL   = 0.02;                % spec_E3 criteria.Q3_power
Q4_MAX   = 1.2*12.1;            % rpm, spec_E3 criteria.Q4_overspeed
SPEEDS   = [12 14 16 18 20 22 24];   % m/s, spec_E3 E3b_region3_qualification.mean_speeds
N_SEEDS  = 3;                   % spec_E2 V4b_data_model_v2 (RandSeed1 in {32001, 32002, 32003})

[~, ID] = fileparts(OUT);
V = {sprintf('campaign: %s', ID), 'spec: openfast_q1/E2/spec_E2.yaml (validation.V4_turbulent_segments.V4b_data_model_v2); criteria of openfast_q1/E3/spec_E3.yaml (E3b_region3_qualification.criteria)', ...
     'data campaign: no verdict; usable = spec_E3 Q2 and Q2b pass; Q3 and Q4 reported only'};
for k = 1:numel(W)
    V{end+1} = sprintf('wind %s: TurbSim %s, %.1f s%s', W(k).name, yn(W(k).ok), W(k).wall_s, errtxt(W(k).err)); %#ok<AGROW>
end
if numel(W) ~= 21, V{end+1} = sprintf('wind fields generated: %d of 21', numel(W)); end

n = numel(R);
S = table('Size', [n 15], 'VariableTypes', {'string', 'double', 'double', 'string', 'logical', 'logical', 'double', 'double', ...
                                            'string', 'double', 'string', 'double', 'logical', 'double', 'string'}, ...
          'VariableNames', {'run', 'speed', 'seed', 'status', 'Q2', 'Q2b', 'max_pitch_step_deg', 'min_RotSpeed_rpm', ...
                            'Q3', 'mean_Pmech_W', 'Q4', 'max_RotSpeed_rpm', 'usable', 'wall_s', 'outb_sha256'});
for k = 1:n
    r = R(k);
    S.run(k) = r.name;  S.speed(k) = r.speed;  S.seed(k) = r.seed;  S.wall_s(k) = r.wall_s;
    S.Q2(k) = false;  S.Q2b(k) = false;  S.usable(k) = false;
    S.max_pitch_step_deg(k) = NaN;  S.min_RotSpeed_rpm(k) = NaN;  S.mean_Pmech_W(k) = NaN;  S.max_RotSpeed_rpm(k) = NaN;
    S.Q3(k) = "n/e";  S.Q4(k) = "n/e";  S.outb_sha256(k) = "";
    [D, ch, chk] = read_checked(r, errf);
    if ~isempty(chk)
        S.status(k) = "STOPPED: " + chk;
        continue
    end
    S.status(k) = "read";
    S.outb_sha256(k) = sha256_file(r.outb);
    col = @(name) D(:, strcmpi(ch, name));
    t = col('Time');
    S.Q2(k) = r.ok_run && t(end) >= TMAX - DT/2 && all(isfinite(D(:)));
    [S.Q2b(k), S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k)] = q2b_pitch_loop(col('BldPitch1'), col('RotSpeed'), DT);   % whole record
    S.usable(k) = S.Q2(k) && S.Q2b(k);                                     % V4b_data_model_v2
    sel = t >= T_EXCL - DT/2;
    P   = col('GenTq')*1000.*col('GenSpeed')*pi/30;                        % kN-m -> N-m, rpm -> rad/s; W
    S.mean_Pmech_W(k) = mean(P(sel));
    if r.speed >= Q3_FROM, S.Q3(k) = pf(abs(S.mean_Pmech_W(k)/VS_RTPWR - 1) <= Q3_TOL); else, S.Q3(k) = "n/a"; end
    rs = col('RotSpeed');
    S.max_RotSpeed_rpm(k) = max(rs(sel));
    S.Q4(k) = pf(S.max_RotSpeed_rpm(k) <= Q4_MAX);
    writetable(S(k,:), fullfile(r.case_dir, 'summary.csv'), 'Delimiter', ';');
end
writetable(S, fullfile(OUT, 'summary_V4data.csv'), 'Delimiter', ';');

for k = 1:n
    V{end+1} = sprintf(['%-11s %s | Q2 %s Q2b %s usable %s | max pitch step %.4f deg, min RotSpeed %.3f rpm | ' ...
        'Q3 %s (mean Pmech %.0f W, reported only) Q4 %s (max RotSpeed %.3f rpm, reported only) | wall %.1f s | outb %s'], ...
        S.run(k), S.status(k), pf(S.Q2(k)), q2btxt(S, k), yesno(S.usable(k)), S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k), ...
        S.Q3(k), S.mean_Pmech_W(k), S.Q4(k), S.max_RotSpeed_rpm(k), S.wall_s(k), S.outb_sha256(k)); %#ok<AGROW>
end
noev = [];  ev = [];
for u = SPEEDS
    iu = S.speed == u;
    if nnz(iu) ~= N_SEEDS || ~all(S.usable(iu)), noev(end+1) = u; else, ev(end+1) = u; end %#ok<AGROW>
end
us = S.run(S.usable);
if isempty(us), ustxt = 'none'; else, ustxt = strjoin(us', ', '); end
V{end+1} = sprintf('usable runs (%d of %d): %s', numel(us), n, ustxt);
V{end+1} = sprintf('mean speeds with %d usable runs: %s m/s; not evaluated (a run missing, not read or not usable): %s m/s', ...
                   N_SEEDS, mat2str(ev), mat2str(noev));
write_lines(fullfile(OUT, 'report_V4data.txt'), V);
fprintf('%s\n', V{:});
end

function h = hash_list(files)
h = cell(numel(files), 1);
for k = 1:numel(files)
    if exist(files{k}, 'file'), h{k} = sha256_file(files{k}); else, h{k} = 'missing'; end
end
end

function [ok, wall, err, slx_sha, st] = run_sfunc(C, DT, tmax, dll, hfile, errf, tag)
% one run on plant_configuration (spec_E3 E3b_region3_qualification), copied from run_E3b.m: model
% built as run_E3W run_w2, plus a To Workspace block logging the 6 wrapper outputs at every DT; sim
% with CaptureErrors on, the wrapper log is saved whatever the end of the run; library loaded before
% and unloaded after the run, final call after the simulation
mdl = 'E2V4data_sfunc';
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
    '%% generated by run_E2_V4data.m: discon_wrapper at every DT (spec_E3W wrapper.period); channel indices from channels.txt\n' ...
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
if numel(ch) ~= 1, error('run_E2_V4data:mfun', 'MATLAB Function block not found by the Stateflow API.'); end
ch.Script = script;
add_block('simulink/Sinks/To Workspace', [mdl '/log'], 'VariableName', 'wraplog', ...      % spec_E3 outputs.files (wrapper log)
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

function [ok, step_deg, min_rs] = q2b_pitch_loop(bp_deg, rs_rpm, DT)
% spec_E3 E3b_region3_qualification.criteria.Q2b_pitch_loop (amendment 6), over the whole record,
% copied from analyse_E3b.m
%   bp_deg  BldPitch1 (deg);  rs_rpm  RotSpeed (rpm);  DT  output step (s), DT_Out = DT
PC_MAXRAT = 0.1396263;          % rad/s, DISCON.F90 l.75 (criteria.Q2b_pitch_loop)
K_Q2B     = 10;                 % criteria.Q2b_pitch_loop (factor fixed by amendment 5, kept by amendment 6)
if numel(bp_deg) < 2
    step_deg = NaN;
else
    step_deg = max(abs(diff(bp_deg)), [], 'includenan');   % a non-finite step gives NaN, hence FAIL
end
min_rs = min(rs_rpm, [], 'includenan');
ok = step_deg*pi/180 <= K_Q2B*PC_MAXRAT*DT && min_rs > 0;
end

function [D, N, chk] = read_checked(r, errf)
% read a .outb and check its OutList and units (spec_E3 channels.verified, channels.units), copied
% from analyse_E3b.m with RtVAvgxh in m/s added (spec_E2 V4b_data_model_v2: RtVAvgxh in the OutList)
D = [];  N = {};  chk = '';
if ~r.ok_run || isempty(r.outb) || ~exist(r.outb, 'file')
    chk = ['run not completed: ' r.err];  return
end
try
    [D, N, U] = ReadFASTbinary(r.outb);
catch ME
    log_error(errf, [r.name ' read .outb'], ME);
    chk = ['.outb not readable: ' strrep(ME.message, newline, ' ')];  return
end
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
if numel(N) ~= numel(r.channels) || ~all(strcmpi(N, r.channels(:)))
    chk = 'OutList written by OpenFAST differs from the expected channel list';  return
end
UNITS = {'GenTq', 'kN-m'; 'GenPwr', 'kW'; 'BlPitchC1', 'deg'; 'BlPitchC2', 'deg'; 'BlPitchC3', 'deg'; ...
         'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'Wind1VelX', 'm/s'; ...           % spec_E3 channels.units
         'BldPitch1', 'deg'; ...                                                 % spec_E3 criteria.reported_only
         'RtVAvgxh', 'm/s'};                                                     % spec_E2 V4b_data_model_v2
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if numel(u) ~= 1 || ~strcmp(u{1}, UNITS{k,2})
        if isempty(u), ut = 'absent'; else, ut = u{1}; end
        chk = sprintf('unit of %s is %s, expected %s', UNITS{k,1}, ut, UNITS{k,2});  return
    end
end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, stamp(), getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function s = q2btxt(S, k)
if S.status(k) == "read", s = pf(S.Q2b(k)); else, s = 'n/e'; end
end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = yesno(ok)
if ok, s = 'yes'; else, s = 'no'; end
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

function beta = read_beta_eq(f, speed)
% beta_eq_deg of the row vent_m_s = speed in the E1 CSV (';' separated, header on the first line),
% copied from run_E3b.m
L = read_lines(f);
H = strsplit(strtrim(L{1}), ';');
jv = find(strcmp(H, 'vent_m_s'));  jb = find(strcmp(H, 'beta_eq_deg'));
if ~isscalar(jv) || ~isscalar(jb), error('run_E2_V4data:csvhead', 'Columns vent_m_s and beta_eq_deg not found once in %s.', f); end
hit = {};
for k = 2:numel(L)
    F = strsplit(strtrim(L{k}), ';');
    if numel(F) == numel(H) && strcmp(F{jv}, speed), hit{end+1} = F{jb}; end %#ok<AGROW>
end
if numel(hit) ~= 1, error('run_E2_V4data:csvrow', 'Row vent_m_s = %s found %d times in %s.', speed, numel(hit), f); end
beta = str2double(hit{1});
if ~isfinite(beta), error('run_E2_V4data:csvval', 'beta_eq_deg at %s m/s is not a number.', speed); end
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
