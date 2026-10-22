function analyse_E3b(OUT, R, W)
%ANALYSE_E3B  Criteria Q1-Q5, reported quantities, domain rule and verdict of E3b
%(openfast_q1/E3/spec_E3.yaml, E3b_region3_qualification).
%
%   analyse_E3b(OUT, R, W)    called once by run_E3b at the end of the campaign
%
%   R: runs of run_E3b (21 runs + the repetition), W: wind fields of gen_wind_E3.
%   Every catch appends getReport(ME, 'extended') to OUT/errors_E3b.txt.
%   Every .outb is read and its OutList and units checked (spec_E3 channels.verified,
%   channels.units); a difference marks the run STOPPED. Statistics exclude the first 60 s
%   (spec_E3 E3b_region3_qualification.duration).
%   Q1 integrity     inputs hashed before and after each run are equal (criteria.Q1_integrity)
%   Q2 execution     run completed, t_end >= TMax - DT/2, all outputs finite (criteria.Q2_execution)
%   Q2b pitch loop   over the whole record from t = 0 (no exclusion of the first 60 s): max over output
%                    steps of |BldPitch1(k) - BldPitch1(k-1)| x pi/180 <= 10 x PC_MaxRat x DT and
%                    min RotSpeed > 0 rpm (criteria.Q2b_pitch_loop, amendments 5 and 6); a run that is
%                    not read is not evaluated (n/e) and counts as a failure for the verdict
%   Q3 power         mean speeds >= 14 m/s: mean of GenTq x 1000 x GenSpeed x pi/30 within
%                    VS_RtPwr +/- 2 % (criteria.Q3_power)
%   Q4 overspeed     max RotSpeed <= 1.2 x 12.1 rpm (criteria.Q4_overspeed)
%   Q5 repeatability the channel names, units and data (class double, typecast to uint8) of the two
%                    .outb of 18 m/s seed 31001 are identical; file SHA-256 reported only (repeatability)
%   reported_only    region-3 fraction (reconstruction below; PitCom = record 45 returned by the
%                    previous DISCON call, read in runs/<run>/wrapper_log.mat, amendment 3), fraction
%                    with BldPitch1 > 30 deg, mean and std of RotSpeed, mean GenPwr, wall time
%                    (criteria.reported_only); if the wrapper log is missing or its times differ from
%                    the .outb, the region-3 fraction is NaN and the reason is written in column wraplog
%   domain_rule      a speed is region-3 core if its region-3 fraction is >= 0.90 for every seed; a
%                    speed with a NaN fraction, or with a run (repetition excluded) not read or failing
%                    Q2 or Q2b, is listed as not evaluated (domain_rule, amendment 5)
%   verdict          QUALIFIED / QUALIFIED WITH LIMITS / NOT QUALIFIED; Q2b must pass for all runs
%                    (verdict, amendment 5)
%   Writes OUT/verdict_E3b.txt, OUT/summary_E3b.csv and runs/<run>/summary.csv.

TMAX     = 660;                 % s, E3b_region3_qualification.runs
T_EXCL   = 60;                  % s, E3b_region3_qualification.duration
DT       = 0.00625;             % s, channels.output_format
Q3_FROM  = 14;                  % m/s, criteria.Q3_power
VS_RTPWR = 5296610;             % W, criteria.Q3_power (DISCON.F90 l.96)
Q3_TOL   = 0.02;                % criteria.Q3_power
Q4_MAX   = 1.2*12.1;            % rpm, criteria.Q4_overspeed
PITCH_HI = 30;                  % deg, criteria.reported_only
CORE_MIN = 0.90;                % domain_rule
REPEAT   = [18 31001];          % repeatability

[~, ID] = fileparts(OUT);
ERRF = fullfile(OUT, 'errors_E3b.txt');
V = {sprintf('campaign: %s', ID), 'spec: openfast_q1/E3/spec_E3.yaml (E3b_region3_qualification)'};
for k = 1:numel(W)
    V{end+1} = sprintf('wind %s: TurbSim %s, %.1f s%s', W(k).name, yn(W(k).ok), W(k).wall_s, errtxt(W(k).err)); %#ok<AGROW>
end
if numel(W) ~= 21, V{end+1} = sprintf('wind fields generated: %d of 21', numel(W)); end

n = numel(R);
S = table('Size', [n 21], 'VariableTypes', [{'string', 'double', 'double', 'double', 'string'}, repmat({'logical'}, 1, 5), repmat({'double'}, 1, 7), {'string'}, ...
                                             {'logical', 'double', 'double'}], ...          % Q2b columns appended (amendments 5 and 6)
          'VariableNames', {'run', 'speed', 'seed', 'rep', 'status', 'Q1', 'Q2', 'Q3', 'Q4', 'Q3_applies', ...
                            'mean_Pmech_W', 'max_RotSpeed_rpm', 'frac_region3', 'frac_pitch_gt30', ...
                            'mean_RotSpeed_rpm', 'std_RotSpeed_rpm', 'mean_GenPwr_kW', 'wraplog', ...
                            'Q2b', 'max_pitch_step_deg', 'min_RotSpeed_rpm'});
wall = nan(n, 1);  outb_sha = strings(n, 1);
for k = 1:n
    r = R(k);
    S.run(k) = r.name;  S.speed(k) = r.speed;  S.seed(k) = r.seed;  S.rep(k) = r.rep;
    S.Q1(k) = r.q1_same;  wall(k) = r.wall_s;  S.Q3_applies(k) = r.speed >= Q3_FROM;
    S{k, 11:17} = NaN(1, 7);
    S.wraplog(k) = "not read";
    S.Q2b(k) = false;  S.max_pitch_step_deg(k) = NaN;  S.min_RotSpeed_rpm(k) = NaN;
    [D, ch, chk] = read_checked(r, ERRF);
    if ~isempty(chk)
        S.status(k) = "STOPPED: " + chk;
        continue
    end
    S.status(k) = "read";
    outb_sha(k) = sha256_file(r.outb);
    col = @(name) D(:, strcmpi(ch, name));
    t = col('Time');
    S.Q2(k) = r.ok_run && t(end) >= TMAX - DT/2 && all(isfinite(D(:)));
    [S.Q2b(k), S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k)] = q2b_pitch_loop(col('BldPitch1'), col('RotSpeed'), DT);   % whole record
    sel = t >= T_EXCL - DT/2;
    gs  = col('GenSpeed')*pi/30;                       % rpm -> rad/s
    P   = col('GenTq')*1000.*gs;                       % kN-m -> N-m; W
    S.mean_Pmech_W(k) = mean(P(sel));
    S.Q3(k) = ~S.Q3_applies(k) || abs(S.mean_Pmech_W(k)/VS_RTPWR - 1) <= Q3_TOL;
    rs = col('RotSpeed');
    S.max_RotSpeed_rpm(k) = max(rs(sel));
    S.Q4(k) = S.max_RotSpeed_rpm(k) <= Q4_MAX;
    [p45, wtxt] = read_wraplog(r, t, DT, ERRF);
    S.wraplog(k) = wtxt;
    if ~isempty(p45)
        reg3 = region3(t, gs, p45, col('BldPitch1')*pi/180);
        S.frac_region3(k) = mean(reg3(sel));
    end
    bp = col('BldPitch1');
    S.frac_pitch_gt30(k) = mean(bp(sel) > PITCH_HI);
    S.mean_RotSpeed_rpm(k) = mean(rs(sel));
    S.std_RotSpeed_rpm(k)  = std(rs(sel));
    gp = col('GenPwr');
    S.mean_GenPwr_kW(k) = mean(gp(sel));
    writetable([S(k,:), table(wall(k), outb_sha(k), 'VariableNames', {'wall_s', 'outb_sha256'})], ...
               fullfile(r.case_dir, 'summary.csv'), 'Delimiter', ';');
end
S.wall_s = wall;  S.outb_sha256 = outb_sha;
writetable(S, fullfile(OUT, 'summary_E3b.csv'), 'Delimiter', ';');

% --- Q5 -----------------------------------------------------------------------------------------
i1 = find(S.speed == REPEAT(1) & S.seed == REPEAT(2) & S.rep == 1);
i2 = find(S.speed == REPEAT(1) & S.seed == REPEAT(2) & S.rep == 2);
q5 = false;  q5txt = 'not evaluated (run missing or not read)';
if isscalar(i1) && isscalar(i2) && S.status(i1) == "read" && S.status(i2) == "read"
    [Da, Na, Ua] = ReadFASTbinary(R(i1).outb);
    [Db, Nb, Ub] = ReadFASTbinary(R(i2).outb);
    same_n = isequal(strtrim(Na(:)), strtrim(Nb(:)));
    same_u = isequal(strtrim(Ua(:)), strtrim(Ub(:)));
    same_d = isa(Da, 'double') && isa(Db, 'double') && isequal(size(Da), size(Db)) && ...
             isequal(typecast(Da(:), 'uint8'), typecast(Db(:), 'uint8'));       % byte for byte
    q5 = same_n && same_u && same_d;
    q5txt = sprintf('names %d, units %d, data byte for byte %d; file SHA-256 %s / %s (reported only)', ...
                    same_n, same_u, same_d, S.outb_sha256(i1), S.outb_sha256(i2));
end

% --- report -------------------------------------------------------------------------------------
for k = 1:n
    V{end+1} = sprintf(['%-15s %s | Q1 %s Q2 %s Q2b %s Q3 %s Q4 %s | max pitch step %.4f deg, min RotSpeed %.3f rpm, ' ...
        'mean Pmech %.0f W, max RotSpeed %.3f rpm, ' ...
        'region 3 %.4f (wrapper log %s), pitch > 30 deg %.4f, RotSpeed %.3f +/- %.3f rpm, mean GenPwr %.1f kW, wall %.1f s'], ...
        S.run(k), S.status(k), pf(S.Q1(k)), pf(S.Q2(k)), q2btxt(S, k), q3txt(S, k), pf(S.Q4(k)), ...
        S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k), S.mean_Pmech_W(k), ...
        S.max_RotSpeed_rpm(k), S.frac_region3(k), S.wraplog(k), S.frac_pitch_gt30(k), S.mean_RotSpeed_rpm(k), ...
        S.std_RotSpeed_rpm(k), S.mean_GenPwr_kW(k), S.wall_s(k)); %#ok<AGROW>
end
V{end+1} = sprintf('Q5 repeatability (%d m/s seed %d): %s (%s)', REPEAT, pf(q5), q5txt);

% --- domain rule (the 21 runs, not the repetition) ----------------------------------------------
P1 = S(S.rep == 1, :);
core = [];  trans = [];  noev = [];
for u = unique(P1.speed)'
    iu = P1.speed == u;
    f = P1.frac_region3(iu);
    excl = any(P1.status(iu) ~= "read") || any(~P1.Q2(iu)) || any(~P1.Q2b(iu));   % domain_rule (amendment 5)
    if excl || any(isnan(f)), noev(end+1) = u;                                   %#ok<AGROW>
    elseif numel(f) == 3 && all(f >= CORE_MIN), core(end+1) = u; else, trans(end+1) = u; end %#ok<AGROW>
end
V{end+1} = sprintf('domain_rule (region-3 fraction >= %.2f for every seed; runs not read or failing Q2 or Q2b excluded): core %s m/s; transition %s m/s; not evaluated %s m/s', ...
                   CORE_MIN, mat2str(core), mat2str(trans), mat2str(noev));

% --- verdict ------------------------------------------------------------------------------------
all_runs = n == 22 && numel(W) == 21 && all(S.status == "read");
base_ok  = all_runs && all(S.Q1) && all(S.Q2) && all(S.Q2b) && q5;   % verdict (Q2b: amendment 5)
lim      = unique(S.speed(~S.Q3 | ~S.Q4))';
if base_ok && isempty(lim)
    verdict = 'QUALIFIED';
elseif base_ok
    verdict = sprintf('QUALIFIED WITH LIMITS (Q3 or Q4 fail at %s m/s)', mat2str(lim));
else
    verdict = 'NOT QUALIFIED';
end
V{end+1} = ['VERDICT E3b: ' verdict];
write_lines(fullfile(OUT, 'verdict_E3b.txt'), V);
fprintf('%s\n', V{:});
end

% =============================================================================================
function reg3 = region3(t, gs, pitc, bp1)
% region-3 reconstruction of spec_E3 E3b_region3_qualification.criteria.reported_only
%   t     output times (s);  gs  GenSpeed (rad/s);  bp1  BldPitch1 (rad)
%   pitc  record 45 returned by DISCON at each output time (rad), from the wrapper log (amendment 3)
CORNERFREQ = 1.570796;          % rad/s, DISCON.F90 l.58
VS_RTGNSP  = 121.6805;          % rad/s, DISCON.F90 l.95
VS_RGN3MP  = 0.01745329;        % rad, DISCON.F90 l.94
n = numel(t);
gsf = zeros(n, 1);  pitcom = zeros(n, 1);
gsf(1)    = gs(1);              % initial GenSpeedF = GenSpeed, DISCON.F90 l.303
pitcom(1) = bp1(1);             % initial PitCom = BlPitch, DISCON.F90 l.304
for k = 2:n
    alpha  = exp((t(k-1) - t(k))*CORNERFREQ);              % Alpha = EXP((LastTime - Time)*CornerFreq), l.355
    gsf(k) = (1 - alpha)*gs(k) + alpha*gsf(k-1);           % GenSpeedF = (1 - Alpha)*GenSpeed + Alpha*GenSpeedF, l.360
    pitcom(k) = pitc(k-1);                                 % PitCom computed after the test (l.487-489): record 45 of the previous call
end
reg3 = gsf >= VS_RTGNSP | pitcom >= VS_RGN3MP;             % test of DISCON.F90 l.384
end

function [ok, step_deg, min_rs] = q2b_pitch_loop(bp_deg, rs_rpm, DT)
% spec_E3 E3b_region3_qualification.criteria.Q2b_pitch_loop (amendment 6), over the whole record
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

function [p45, txt] = read_wraplog(r, t, DT, errf)
% record 45 of every DISCON call (wrapper log, column 4), one row per output time
% (spec_E3 E3b_region3_qualification.criteria.reported_only, amendment 3)
p45 = [];
if isempty(r.wraplog) || ~exist(r.wraplog, 'file'), txt = "missing";  return, end
try
    L = load(r.wraplog, 't', 'c', 'cols');
catch ME
    log_error(errf, [r.name ' wrapper log'], ME);
    txt = "not readable";  return
end
if ~strcmp(L.cols{4}, 'record45_rad') || size(L.c, 2) ~= 6
    txt = "columns not recognised";  return
end
if numel(L.t) ~= numel(t) || max(abs(L.t(:) - t(:))) > DT/100
    txt = sprintf("times differ from the .outb (%d rows, %d output steps)", numel(L.t), numel(t));  return
end
p45 = double(L.c(:, 4));
txt = "read";
end

function [D, N, chk] = read_checked(r, errf)
% read a .outb and check its OutList and units (spec_E3 channels.verified, channels.units)
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
         'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'Wind1VelX', 'm/s'; ...           % channels.units
         'BldPitch1', 'deg'};                                                    % criteria.reported_only ("BldPitch1 > 30 deg")
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if ~strcmp(u{1}, UNITS{k,2})
        chk = sprintf('unit of %s is %s, expected %s', UNITS{k,1}, u{1}, UNITS{k,2});  return
    end
end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function s = q2btxt(S, k)
if S.status(k) == "read", s = pf(S.Q2b(k)); else, s = 'n/e'; end
end

function s = q3txt(S, k)
if S.Q3_applies(k), s = pf(S.Q3(k)); else, s = 'n/a'; end
end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = yn(ok)
if ok, s = 'completed'; else, s = 'error'; end
end

function s = errtxt(e)
if isempty(e), s = ''; else, s = ['; error: ' e]; end
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
