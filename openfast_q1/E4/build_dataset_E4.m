function build_dataset_E4(OUT)
%BUILD_DATASET_E4  Dataset, normalisation and quality report of the E4 campaign
%(openfast_q1/E4/spec_E4.yaml: usability, partition, signals, normalisation, format, quality).
%
%   build_dataset_E4(OUT)    called once by run_E4 at the end of the campaign; OUT is the campaign
%                            folder results/Q1-E4-DATA-<date>-<letter>
%
%   Reads OUT/completion_E4.csv (one record per run, written by run_E4; in resume mode the reused
%   runs point to the interrupted campaign). Refuses to run (error, nothing written) if spec_E4.yaml
%   differs from SPEC_E4_SHA, if the completion file does not hold the 70 runs of spec_E4 arms.runs,
%   or if the .outb, the block log, the excitation file or the .bts of a completed run differs from
%   the SHA-256 recorded by run_E4.
%   Per run (spec_E4 usability, quality):
%     read       .outb read with OutList (case_dir/channels.txt) and units checked, block log read and
%                its times checked against the .outb at every output step (quality.data_checks)
%     usability  spec_E3 Q2_execution and Q2b_pitch_loop on the whole record; a failing run is
%                excluded, the other arm of the same seed is kept if it passes (D8)
%     signals    omega_r = RotSpeed x pi/30; omega_f rebuilt from GenSpeed (rad/s) with the DISCON
%                filter from t = 0 (signals.states); u = applied pitch command (deg) of the block log
%                (signals.input); d = RtVAvgxh (signals.disturbance); Wind1VelX kept, not an input
%     sampling   at Ts = 0.05 s (main), 0.025 s and 0.1 s: samples t_k = 60 + k x Ts, x(t_k), u and d at
%                t_k held over the step, target Delta x_k = x(t_{k+1}) - x(t_k) between consecutive
%                samples of the same run, from t = 60 s, never across runs or across t = 60 s
%                (signals.sampling, signals.target)
%     checks     no NaN, duplicate or missing time step in the tables at Ts (quality.data_checks); a
%                run failing a check gets no dataset table and is counted as excluded
%     reported   clipping and out-of-range counts (whole record and 60-660 s), torque_error and the
%                torque_consistency of X3 relative to X0 of the same speed and seed (as spec_E4X
%                metrics.torque_error with torque_error_amendment_1, on 60-660 s), fraction of samples
%                at Ts = 0.05 s with lambda = omega_r x R / RtVAvgxh outside [2, 13] or applied pitch
%                outside [0, 30] deg (quality.reported)
%   partition    training 34001-34003, validation 34004, test 34005 (spec_E4 partition)
%   normalisation per Ts: mean and standard deviation of omega_r, omega_f, u, d, Delta omega_r and
%                Delta omega_f over the usable training runs of both arms (spec_E4 normalisation)
%   status       READY / READY WITH CONDITIONS / NOT READY (spec_E4 quality.status)
%   Writes in OUT/dataset/: <run>_DT.mat (archival table at DT), <run>_Ts0p050.mat, <run>_Ts0p025.mat,
%   <run>_Ts0p100.mat (dataset tables with metadata), and in OUT: index_E4.csv, normalisation_E4.mat,
%   normalisation_E4.csv, quality_E4.txt (with the SHA-256 of every file written).

SPEC_E4_SHA = '73e07bca01ffce034a34c5b0d6b334eec48e603936a92fe7569f9d79ad885088';   % spec_E4, draft 3 adopted
SPEEDS   = [12 14 16 18 20 22 24];          % m/s, spec_E4 wind.mean_speeds
SEEDS    = [34001 34002 34003 34004 34005]; % spec_E4 wind.seeds
ARMS     = {'X0', 'X3'};                    % spec_E4 arms.runs
TRAIN    = [34001 34002 34003];             % spec_E4 partition (training)
VALID    = 34004;                           % spec_E4 partition (validation)
TEST     = 34005;                           % spec_E4 partition (test)
DT       = 0.00625;                         % s, spec_E4 signals.recorded
TMAX     = 660;                             % s, spec_E4 wind.duration
T0       = 60;                              % s, spec_E4 wind.duration (first 60 s excluded)
TS_LIST  = [0.05 0.025 0.1];                % s, spec_E4 signals.sampling (main, then sensitivity)
TS_MAIN  = 0.05;                            % s, spec_E2 nmpc_interface.Ts.main
CORNERFREQ = 1.570796;                      % rad/s, DISCON.F90 l.58 (spec_E2 validation.V3_pitch_steps.compare)
VS_MAXTQ = 47402.91;                        % N m, DISCON.F90 l.91 (spec_E4X metrics.torque_error)
BETA_DOM = [0 30];                          % deg, spec_E4 quality.reported (spec_E2 nmpc_interface.constraints)
LAM_DOM  = [2 13];                          % -, spec_E4 quality.reported (Cp table domain, spec_E2 l.64)
MIN_TRAIN = 2;                              % usable training seeds per speed and arm, spec_E4 quality.status
VARS     = {'omega_r', 'omega_f', 'u_deg', 'd_RtVAvgxh', 'dx_omega_r', 'dx_omega_f'};   % spec_E4 normalisation

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(ROOT, 'openfast_q1', 'E2'));                    % rom_params, rom_torque_law
[~, ID] = fileparts(OUT);
ERRF = fullfile(OUT, 'errors_E4.txt');
DD   = fullfile(OUT, 'dataset');

% --- refusals ---------------------------------------------------------------------------------
if ~strcmp(sha256_file(fullfile(ROOT, 'openfast_q1', 'E4', 'spec_E4.yaml')), SPEC_E4_SHA)
    error('build_dataset_E4:spec', 'spec_E4.yaml SHA-256 differs from %s.', SPEC_E4_SHA);
end
C = read_completion(fullfile(OUT, 'completion_E4.csv'));
names = run_names(SPEEDS, SEEDS, ARMS);
if ~all(ismember(names, C.run)), error('build_dataset_E4:runs', 'completion_E4.csv does not hold the 70 runs of spec_E4 arms.runs.'); end
for k = 1:numel(names)
    c = C(find(C.run == names{k}, 1, 'last'), :);
    if c.status ~= "completed", continue, end
    F = {c.outb, c.outb_sha; c.wraplog, c.wraplog_sha; c.excitation, c.excitation_sha; c.bts, c.bts_sha};
    for j = 1:size(F, 1)
        if strlength(F{j,1}) == 0 && j == 3, continue, end         % X0: no excitation file
        if ~exist(F{j,1}, 'file') || ~strcmp(sha256_file(F{j,1}), F{j,2})
            error('build_dataset_E4:hash', '%s: %s is missing or its SHA-256 differs from %s.', names{k}, F{j,1}, F{j,2});
        end
    end
end
prm = rom_params();                                                % constants only (no Cp table)
if prm.VS_MaxTq ~= VS_MAXTQ || ~isequal(prm.lambda_dom, LAM_DOM) || ~isequal(prm.beta_dom, BETA_DOM)
    error('build_dataset_E4:params', 'rom_params differs from the constants of spec_E4 quality.reported.');
end
if ~exist(DD, 'dir'), mkdir(DD); end

% --- per run ----------------------------------------------------------------------------------
n = numel(names);
S = table('Size', [n 27], ...
    'VariableTypes', [{'string', 'double', 'double', 'string', 'string', 'string', 'string', 'logical', 'string'}, ...
                      {'logical', 'logical', 'double', 'double', 'double', 'double', 'double', 'double'}, ...
                      {'double', 'double', 'double', 'double', 'double', 'string', 'string', 'string', 'string', 'string'}], ...
    'VariableNames', {'run', 'speed', 'seed', 'arm', 'partition', 'source', 'status', 'usable', 'reason', ...
                      'Q2', 'Q2b', 'max_pitch_step_deg', 'min_RotSpeed_rpm', 'n_clip_all', 'n_clip_60_660', 'n_out_all', 'n_out_60_660', ...
                      'torque_error', 'torque_consistency', 'frac_lambda_out', 'frac_pitch_out', 'frac_domain_out', ...
                      'bts_sha256', 'outb_sha256', 'sha_DT', 'sha_Ts0p050', 'sha_Ts_sens'});
TAB = cell(n, numel(TS_LIST));                                     % dataset tables of the usable runs
for k = 1:n
    tok = regexp(names{k}, '^U(\d+)_S(\d+)_(X\d)$', 'tokens', 'once');
    S.run(k) = names{k};  S.speed(k) = str2double(tok{1});  S.seed(k) = str2double(tok{2});  S.arm(k) = tok{3};
    S.partition(k) = part_of(S.seed(k), TRAIN, VALID, TEST);
    S.Q2(k) = false;  S.Q2b(k) = false;  S.usable(k) = false;
    S{k, {'max_pitch_step_deg', 'min_RotSpeed_rpm', 'n_clip_all', 'n_clip_60_660', 'n_out_all', 'n_out_60_660', ...
          'torque_error', 'torque_consistency', 'frac_lambda_out', 'frac_pitch_out', 'frac_domain_out'}} = NaN(1, 11);
    S{k, {'sha_DT', 'sha_Ts0p050', 'sha_Ts_sens'}} = ["", "", ""];
    c = C(find(C.run == names{k}, 1, 'last'), :);
    S.source(k) = c.source;  S.status(k) = c.status;  S.bts_sha256(k) = c.bts_sha;  S.outb_sha256(k) = c.outb_sha;
    if c.status ~= "completed", S.reason(k) = "run " + c.status + ": " + c.err;  continue, end
    [D, ch, chk] = read_checked(c, ERRF);
    if isempty(chk), [G, chk] = read_blocklog(c, D(:, strcmpi(ch, 'Time')), DT, ERRF); end
    if ~isempty(chk), S.reason(k) = "not read: " + chk;  continue, end
    col = @(name) D(:, strcmpi(ch, name));
    t = col('Time');  sel = t >= T0 - DT/2;
    bp1 = col('BldPitch1');  rs = col('RotSpeed');
    % usability (spec_E4 usability, D8): spec_E3 Q2 and Q2b on the whole record
    S.Q2(k) = c.ok_run == "true" && t(end) >= TMAX - DT/2 && all(isfinite(D(:)));
    [S.Q2b(k), S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k)] = q2b_pitch_loop(bp1, rs, DT);
    % signals (spec_E4 signals.states, signals.input, signals.disturbance)
    wr  = rs*pi/30;                                                % omega_r, rad/s
    gs  = col('GenSpeed')*pi/30;                                   % rad/s
    wf  = dfilter(gs, DT, CORNERFREQ);                             % omega_f, rad/s, DISCON filter from t = 0
    u   = G.command_applied_rad*180/pi;                            % applied pitch command, deg
    d   = col('RtVAvgxh');                                         % m/s
    % reported counts and torque error (spec_E4 quality.reported)
    clip = G.clipped ~= 0;  out = u < BETA_DOM(1) | u > BETA_DOM(2);
    S.n_clip_all(k) = nnz(clip);  S.n_clip_60_660(k) = nnz(clip(sel));
    S.n_out_all(k)  = nnz(out);   S.n_out_60_660(k)  = nnz(out(sel));
    S.torque_error(k) = torque_error(col('GenTq'), wf, u, sel, prm, VS_MAXTQ);
    if ~(S.Q2(k) && S.Q2b(k))
        S.reason(k) = "excluded: " + strjoin(["Q2 " + pf(S.Q2(k)), "Q2b " + pf(S.Q2b(k))], ", ");
        continue
    end
    % archival table at DT and dataset tables at Ts (spec_E4 format, signals.sampling)
    A = table(t, wr, wf, u, d, col('Wind1VelX'), bp1, col('GenTq'), G.p_deg, double(clip), ...
              'VariableNames', {'t', 'omega_r', 'omega_f', 'u_deg', 'd_RtVAvgxh', 'Wind1VelX', 'BldPitch1_deg', 'GenTq_kNm', 'p_deg', 'clipped'});
    meta = struct('trajectory_id', names{k}, 'mean_speed', S.speed(k), 'seed', S.seed(k), 'arm', S.arm(k), ...
                  'bts_sha256', c.bts_sha, 'outb_sha256', c.outb_sha, 'partition', S.partition(k), 'Ts', DT, 'campaign', ID);
    fa = fullfile(DD, [names{k} '_DT.mat']);
    save(fa, 'A', 'meta');
    S.sha_DT(k) = sha256_file(fa);
    chk = '';  sens = strings(1, 0);
    for j = 1:numel(TS_LIST)
        [T, why] = sample_table(A, TS_LIST(j), DT, T0, TMAX);       % includes quality.data_checks
        if ~isempty(why), chk = sprintf('Ts %g s: %s', TS_LIST(j), why);  break, end
        meta.Ts = TS_LIST(j);
        ft = fullfile(DD, sprintf('%s_Ts%s.mat', names{k}, ts_tag(TS_LIST(j))));
        save(ft, 'T', 'meta');
        TAB{k, j} = T;
        if TS_LIST(j) == TS_MAIN
            S.sha_Ts0p050(k) = sha256_file(ft);
            lam = T.omega_r*prm.R./T.d_RtVAvgxh;                     % lambda (quality.reported)
            lo  = ~(lam >= LAM_DOM(1) & lam <= LAM_DOM(2));
            po  = T.u_deg < BETA_DOM(1) | T.u_deg > BETA_DOM(2);
            S.frac_lambda_out(k) = mean(lo);  S.frac_pitch_out(k) = mean(po);  S.frac_domain_out(k) = mean(lo | po);
        else
            sens(end+1) = sprintf('Ts%s %s', ts_tag(TS_LIST(j)), sha256_file(ft)); %#ok<AGROW>
        end
    end
    if ~isempty(chk)
        TAB(k, :) = {[]};
        S.reason(k) = "excluded: data check failed, " + chk;
        continue
    end
    S.sha_Ts_sens(k) = strjoin(sens, ' | ');
    S.usable(k) = true;
    S.reason(k) = "usable";
end

% --- torque_consistency of X3 relative to X0 of the same speed and seed (quality.reported) -------
for k = 1:n
    if S.arm(k) ~= "X3", continue, end
    i0 = find(S.speed == S.speed(k) & S.seed == S.seed(k) & S.arm == "X0");
    if isscalar(i0), S.torque_consistency(k) = S.torque_error(k) - S.torque_error(i0); end
end

% --- normalisation per Ts, usable training runs of both arms (spec_E4 normalisation) ------------
iu = find(S.usable & S.partition == "training");
NZ = struct('Ts', num2cell(TS_LIST), 'vars', {VARS}, 'mean', [], 'std', [], 'n_samples', [], 'runs', []);
NL = {'Ts;variable;mean;std;n_samples;n_runs'};
for j = 1:numel(TS_LIST)
    if isempty(iu), Z = NaN(0, numel(VARS)); else, Z = cell2mat(cellfun(@(T) T{:, VARS}, TAB(iu, j), 'UniformOutput', false)); end
    NZ(j).mean = mean(Z, 1);  NZ(j).std = std(Z, 0, 1);  NZ(j).n_samples = size(Z, 1);  NZ(j).runs = cellstr(S.run(iu));
    for v = 1:numel(VARS)
        NL{end+1} = sprintf('%g;%s;%.10g;%.10g;%d;%d', TS_LIST(j), VARS{v}, NZ(j).mean(v), NZ(j).std(v), NZ(j).n_samples, numel(iu)); %#ok<AGROW>
    end
end
fn = fullfile(OUT, 'normalisation_E4.mat');  save(fn, 'NZ');
fc = fullfile(OUT, 'normalisation_E4.csv');  write_lines(fc, NL);
fi = fullfile(OUT, 'index_E4.csv');          writetable(S, fi, 'Delimiter', ';');

% --- status (spec_E4 quality.status) ----------------------------------------------------------
x0 = S.arm == "X0";  x3 = S.arm == "X3";  vt = S.partition == "validation" | S.partition == "test";
tr = S.partition == "training";
ntr = @(m, u) nnz(m & tr & S.speed == u & S.usable);
low0 = SPEEDS(arrayfun(@(u) ntr(x0, u) < MIN_TRAIN, SPEEDS));
low3 = SPEEDS(arrayfun(@(u) ntr(x3, u) < MIN_TRAIN, SPEEDS));
excl = S.run(~S.usable);
if any(x0 & vt & ~S.usable) || ~isempty(low0)
    status = 'NOT READY';
elseif all(S.usable(x0)) && all(S.usable(x3 & vt)) && isempty(low3)
    status = 'READY';
else
    status = 'READY WITH CONDITIONS';
end

% --- quality report ---------------------------------------------------------------------------
Q = {sprintf('campaign: %s', ID), sprintf('spec: openfast_q1/E4/spec_E4.yaml %s', SPEC_E4_SHA), ...
     sprintf('runs: %d listed, %d usable, %d excluded or not completed', n, nnz(S.usable), n - nnz(S.usable))};
for k = 1:n
    Q{end+1} = sprintf(['%-17s %-10s %-11s %s | Q2 %s Q2b %s (max step %.4f deg, min RotSpeed %.3f rpm) | clipping %g (60-660 s %g), ' ...
        'out of range %g (60-660 s %g) | torque_error %.6f, consistency to X0 %.6f | Ts 0.05 s: lambda out %.4f, pitch out %.4f, either %.4f | %s'], ...
        S.run(k), S.partition(k), S.source(k), S.status(k), pf(S.Q2(k)), pf(S.Q2b(k)), S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k), ...
        S.n_clip_all(k), S.n_clip_60_660(k), S.n_out_all(k), S.n_out_60_660(k), S.torque_error(k), S.torque_consistency(k), ...
        S.frac_lambda_out(k), S.frac_pitch_out(k), S.frac_domain_out(k), S.reason(k)); %#ok<AGROW>
end
for u = SPEEDS
    Q{end+1} = sprintf('%d m/s: usable training seeds X0 %d, X3 %d; validation and test usable X0 %d of 2, X3 %d of 2', u, ...
        ntr(x0, u), ntr(x3, u), nnz(x0 & vt & S.speed == u & S.usable), nnz(x3 & vt & S.speed == u & S.usable)); %#ok<AGROW>
end
if isempty(excl), Q{end+1} = 'excluded runs: none'; else, Q{end+1} = ['excluded runs: ' strjoin(cellstr(excl), ', ')]; end
Q{end+1} = sprintf('speeds with fewer than %d usable training seeds: X0 %s m/s, X3 %s m/s', MIN_TRAIN, mat2str(low0), mat2str(low3));
Q{end+1} = 'X3 at 12-14 m/s is an accepted risk (spec_E4 arms.limit, quality.status)';
Q{end+1} = sprintf('normalisation: %d usable training runs of both arms, normalisation_E4.mat %s, normalisation_E4.csv %s', numel(iu), sha256_file(fn), sha256_file(fc));
Q{end+1} = sprintf('index: index_E4.csv %s', sha256_file(fi));
Q{end+1} = sprintf('STATUS: %s', status);
write_lines(fullfile(OUT, 'quality_E4.txt'), Q);
fprintf('%s\n', Q{:});
end

% =============================================================================================
function N = run_names(speeds, seeds, arms)
% run names in the order of spec_E4 arms.runs (speed, then seed, then X0 before X3)
N = {};
for u = speeds
    for s = seeds
        for a = 1:numel(arms), N{end+1} = sprintf('U%02d_S%d_%s', u, s, arms{a}); end %#ok<AGROW>
    end
end
end

function p = part_of(seed, train, valid, test)
% partition by seed (spec_E4 partition)
if ismember(seed, train), p = "training"; elseif seed == valid, p = "validation"; elseif seed == test, p = "test"; else, p = "none"; end
end

function C = read_completion(f)
% completion records written by run_E4 (spec_E4 interruption), all fields as strings
if ~exist(f, 'file'), error('build_dataset_E4:completion', 'Missing %s.', f); end
H = strsplit(strtrim(fileread_first(f)), ';');
C = readtable(f, 'Delimiter', ';', 'TextType', 'string', 'Format', repmat('%s', 1, numel(H)));
for nm = string(C.Properties.VariableNames)
    v = C.(nm);  v(ismissing(v)) = "";  C.(nm) = v;                % empty fields read as ""
end
end

function s = fileread_first(f)
fid = fopen(f, 'r');  s = fgetl(fid);  fclose(fid);
end

function [T, why] = sample_table(A, Ts, DT, T0, TMAX)
% dataset table at Ts (spec_E4 signals.sampling, signals.target) with the data checks of
% spec_E4 quality.data_checks; why = '' if the checks pass
T = [];  why = '';
m = round(Ts/DT);
if abs(m*DT - Ts) > 1e-12, why = 'Ts is not a multiple of DT';  return, end
i0 = round(T0/DT) + 1;  iN = round(TMAX/DT) + 1;
idx = (i0:m:iN)';                                                 % t_k = 60 + k x Ts, k = 0..K
if numel(idx) < 2 || abs(A.t(idx(1)) - T0) > DT/100, why = 'first sample is not at t = 60 s';  return, end
x = [A.omega_r(idx), A.omega_f(idx)];
T = table(A.t(idx(1:end-1)), x(1:end-1, 1), x(1:end-1, 2), A.u_deg(idx(1:end-1)), A.d_RtVAvgxh(idx(1:end-1)), ...
          A.Wind1VelX(idx(1:end-1)), diff(x(:, 1)), diff(x(:, 2)), ...
          'VariableNames', {'t', 'omega_r', 'omega_f', 'u_deg', 'd_RtVAvgxh', 'Wind1VelX', 'dx_omega_r', 'dx_omega_f'});
dt = diff(T.t);
if any(~isfinite(T{:, :}), 'all'), why = 'NaN or Inf in the table';  return, end
if numel(unique(T.t)) ~= height(T), why = 'duplicate time step';  return, end
if any(abs(dt - Ts) > DT/100), why = 'missing time step';  return, end
end

function tag = ts_tag(Ts)
tag = strrep(sprintf('%.3f', Ts), '.', 'p');
end

function gsf = dfilter(gs, DT, cf)
% DISCON low-pass filter rebuilt at every output step from t = 0 (spec_E2 validation.V3_pitch_steps.compare),
% copied from analyse_E4X.m
alpha = exp(-DT*cf);
gsf = zeros(size(gs));
gsf(1) = gs(1);
for k = 2:numel(gs)
    gsf(k) = (1 - alpha)*gs(k) + alpha*gsf(k-1);
end
end

function e = torque_error(gentq_knm, gsf, pitch_deg, sel, prm, maxtq)
% RMS over sel of (GenTq x 1000 - Q_g)/VS_MaxTq, beta at step k = pitch at step k-1 (spec_E4X
% metrics.torque_error, torque_error_amendment_1), copied from analyse_E4X.m
beta = [pitch_deg(1); pitch_deg(1:end-1)];
qg = zeros(size(gsf));
for k = 1:numel(gsf)
    qg(k) = rom_torque_law(gsf(k), beta(k), prm);
end
x = (gentq_knm*1000 - qg)/maxtq;
e = sqrt(mean(x(sel).^2));
end

function [ok, step_deg, min_rs] = q2b_pitch_loop(bp_deg, rs_rpm, DT)
% spec_E3 E3b_region3_qualification.criteria.Q2b_pitch_loop (amendment 6), over the whole record,
% copied from analyse_E3b.m
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

function [G, chk] = read_blocklog(c, t, DT, errf)
% block log of run_E4, one row per output time, times checked against the .outb (spec_E4
% quality.data_checks), as analyse_E4X.m read_blocklog
G = [];  chk = '';
COLS = {'p_deg', 'p_prev_deg', 'genspeed_to_discon_rad_s', 'bldpitch_to_discon_rad', ...
        'command_before_clip_rad', 'command_applied_rad', 'clipped', 'electrical_power_applied_W', ...
        'pitch_command_rad', 'torque_Nm', 'electrical_power_W', 'record45_rad', 'record47_Nm', 'aviFAIL'};
try
    L = load(c.wraplog, 't', 'g', 'cols', 'arm');
catch ME
    log_error(errf, [char(c.run) ' block log'], ME);
    chk = 'block log not readable';  return
end
if ~isequal(L.cols, COLS) || size(L.g, 2) ~= numel(COLS) || ~strcmp(L.arm, c.arm)
    chk = 'block log columns or arm not recognised';  return
end
if numel(L.t) ~= numel(t) || max(abs(L.t(:) - t(:))) > DT/100
    chk = sprintf('block log times differ from the .outb (%d rows, %d output steps)', numel(L.t), numel(t));  return
end
G = struct('command_applied_rad', double(L.g(:, 6)), 'clipped', double(L.g(:, 7)), 'p_deg', double(L.g(:, 1)));
end

function [D, N, chk] = read_checked(c, errf)
% read a .outb and check its OutList (case_dir/channels.txt written by prepare_case_E3) and units
% (spec_E3 channels.verified, channels.units), as analyse_E4X.m read_checked
D = [];  N = {};  chk = '';
cf = fullfile(c.case_dir, 'channels.txt');
if ~exist(cf, 'file'), chk = 'channels.txt missing';  return, end
expected = splitlines(strtrim(fileread(cf)));
try
    [D, N, U] = ReadFASTbinary(char(c.outb));
catch ME
    log_error(errf, [char(c.run) ' read .outb'], ME);
    chk = ['.outb not readable: ' strrep(ME.message, newline, ' ')];  return
end
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
if numel(N) ~= numel(expected) || ~all(strcmpi(N, strtrim(expected(:))))
    chk = 'OutList written by OpenFAST differs from the expected channel list';  return
end
UNITS = {'GenTq', 'kN-m'; 'GenPwr', 'kW'; 'BlPitchC1', 'deg'; 'BlPitchC2', 'deg'; 'BlPitchC3', 'deg'; ...
         'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'Wind1VelX', 'm/s'; ...           % spec_E3 channels.units
         'BldPitch1', 'deg'; ...                                                 % spec_E3 criteria.reported_only
         'RtVAvgxh', 'm/s'};                                                     % spec_E4 signals.disturbance
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

function s = pf(ok)
if ok, s = "PASS"; else, s = "FAIL"; end
end

function s = stamp()
s = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(char(p)).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
