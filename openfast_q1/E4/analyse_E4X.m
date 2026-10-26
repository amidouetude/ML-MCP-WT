function analyse_E4X(OUT)
%ANALYSE_E4X  Metrics, choice rule and verdict of the exploratory campaign E4X
%(openfast_q1/E4/spec_E4X.yaml, with amendment 1).
%
%   analyse_E4X(OUT)    called once by run_E4X at the end of the campaign; OUT is the campaign folder
%
%   Reads OUT/runs_E4X.mat (R, W, X written by run_E4X). Refuses to run (error, nothing written) if
%   spec_E4X.yaml differs from SPEC_E4X_SHA, if excitation.mat differs from X.sha, or if the .outb or
%   the wrapper log of an executed run differs from the SHA-256 recorded by run_E4X.
%   Per run: .outb read, OutList and units checked (as analyse_E3b.m, plus RtVAvgxh in m/s); block
%   log read and its times checked against the .outb (as analyse_E3b.m read_wraplog).
%   applied pitch      command sent to the S-function at each output step, column
%                      command_applied_rad of the block log, in deg (metrics.applied_pitch_amendment_1);
%                      the same metrics with BldPitch1 of the .outb are reported only
%   safety             Q2 (spec_E3 criteria.Q2_execution) and Q2b (criteria.Q2b_pitch_loop) on the whole
%                      record; max RotSpeed <= 14.52 rpm (criteria.Q4_overspeed) and applied pitch in
%                      [0, 30] deg on 60-180 s (metrics.safety, safety_windows_amendment_1)
%   counts             clipping instants (X3) and out-of-range instants (applied pitch outside
%                      [0, 30] deg) on 60-180 s, used by choice_rule, and on the whole record, reported
%                      only (excitation.bounds_amendment_1, metrics.safety_windows_amendment_1)
%   torque_error       RMS over 60-180 s of (GenTq x 1000 - Q_g)/VS_MaxTq, Q_g = rom_torque_law(omega_f,
%                      beta_deg, p), omega_f rebuilt from GenSpeed (rad/s) at every output step from t = 0
%                      with the DISCON filter (spec_E2 validation.V3_pitch_steps.compare), beta_deg at
%                      step k = applied pitch at step k-1, at the first step the applied pitch of that
%                      step (metrics.torque_error, torque_error_amendment_1)
%   torque_consistency torque_error of the arm minus torque_error of X0 at the same speed
%   independence       1 - R^2 of the least-squares fit of the applied pitch on [1, RtVAvgxh, GenSpeed]
%                      at the same output step over 60-180 s, solved with the backslash operator
%   excitation_gain    independence of the arm minus independence of X0 at the same speed
%   choice_rule        admissible (both speeds): safety passes, no clipping instant (X3) or no
%                      out-of-range instant (X1, X2) on 60-180 s, torque_consistency <= 0.002 and
%                      excitation_gain >= 0.02 (admissible, admissible_amendment_1); retained: the
%                      admissible arm with the larger mean excitation_gain over the two speeds; between
%                      admissible arms whose mean excitation_gain differs from the largest by less than
%                      0.02, the first in the order X2, X1, X3 (tie); none admissible: X0 (retained)
%   Writes OUT/metrics_E4X.csv and OUT/verdict_E4X.txt (RETAINED: Xn and the values that decided it).

SPEC_E4X_SHA = '656659dcc47c98803e606e6fbc333a28174b48409ca66c76c52875c2a38d76d6';  % spec_E4X, amendment 1
TMAX      = 180;            % s, spec_E4X cases.duration
T_STAT    = 60;             % s, spec_E4X cases.duration (statistics on 60-180 s)
DT        = 0.00625;        % s, spec_E3 channels.output_format
Q4_MAX    = 1.2*12.1;       % rpm, spec_E3 criteria.Q4_overspeed (14.52 rpm, spec_E4X metrics.safety)
BETA_MIN  = 0;              % deg, spec_E4X metrics.safety (spec_E2 nmpc_interface.constraints)
BETA_MAX  = 30;             % deg, spec_E4X metrics.safety
VS_MAXTQ  = 47402.91;       % N m, spec_E4X metrics.torque_error (DISCON.F90 l.91)
CORNERFREQ = 1.570796;      % rad/s, DISCON.F90 l.58 (spec_E2 validation.V3_pitch_steps.compare)
TQ_MAX    = 0.002;          % spec_E4X choice_rule.admissible (torque_consistency <= 0.002)
GAIN_MIN  = 0.02;           % spec_E4X choice_rule.admissible (excitation_gain >= 0.02)
TIE       = 0.02;           % spec_E4X choice_rule.tie
SPEEDS    = [16 22];        % m/s, spec_E4X cases.mean_speeds
ARMS      = {'X0', 'X1', 'X2', 'X3'};   % spec_E4X cases.arms
TIE_ORDER = {'X2', 'X1', 'X3'};         % spec_E4X choice_rule.tie

ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(ROOT, 'openfast_q1', 'E2'));                    % rom_params, rom_torque_law
[~, ID] = fileparts(OUT);
ERRF = fullfile(OUT, 'errors_E4X.txt');

% --- refusals ---------------------------------------------------------------------------------
if ~strcmp(sha256_file(fullfile(ROOT, 'openfast_q1', 'E4', 'spec_E4X.yaml')), SPEC_E4X_SHA)
    error('analyse_E4X:spec', 'spec_E4X.yaml SHA-256 differs from %s.', SPEC_E4X_SHA);
end
L = load(fullfile(OUT, 'runs_E4X.mat'), 'R', 'W', 'X');
R = L.R;  W = L.W;  X = L.X;
if isempty(X) || ~strcmp(sha256_file(fullfile(OUT, 'excitation.mat')), X.sha)
    error('analyse_E4X:excitation', 'excitation.mat is missing or its SHA-256 differs from the one recorded by run_E4X.');
end
for k = 1:numel(R)
    r = R(k);
    if ~isempty(r.outb_sha) && ~strcmp(sha256_file(r.outb), r.outb_sha)
        error('analyse_E4X:outb', '%s: .outb SHA-256 differs from %s.', r.name, r.outb_sha);
    end
    if ~isempty(r.wraplog_sha) && ~strcmp(sha256_file(r.wraplog), r.wraplog_sha)
        error('analyse_E4X:wraplog', '%s: wrapper log SHA-256 differs from %s.', r.name, r.wraplog_sha);
    end
end
prm = rom_params();                                                % constants only (no Cp table)
if prm.VS_MaxTq ~= VS_MAXTQ, error('analyse_E4X:maxtq', 'rom_params VS_MaxTq differs from %g N m.', VS_MAXTQ); end

V = {sprintf('campaign: %s', ID), sprintf('spec: openfast_q1/E4/spec_E4X.yaml %s (amendment 1)', SPEC_E4X_SHA), ...
     'EXPLORATORY: no value of this campaign enters the values registry or the manuscript (campaign.status_rule)'};
for k = 1:numel(W)
    V{end+1} = sprintf('wind %s: TurbSim %s, %.1f s, bts %s', W(k).name, yn(W(k).ok), W(k).wall_s, W(k).bts_sha); %#ok<AGROW>
end
V{end+1} = sprintf('excitation: %d plateaus started before %g s, excitation.mat %s', X.n_plateaus, TMAX, X.sha);

% --- per run ----------------------------------------------------------------------------------
n = numel(R);
S = table('Size', [n 26], ...
    'VariableTypes', [{'string', 'double', 'string', 'string', 'logical', 'logical', 'double', 'double'}, ...
                      {'double', 'logical', 'double', 'double', 'logical', 'double', 'double', 'double', 'double'}, ...
                      {'logical', 'double', 'double', 'double', 'double', 'double', 'double', 'double', 'double'}], ...
    'VariableNames', {'run', 'speed', 'arm', 'status', 'Q2', 'Q2b', 'max_pitch_step_deg', 'min_RotSpeed_rpm', ...
                      'max_RotSpeed_rpm', 'pitch_in_0_30', 'min_pitch_deg', 'max_pitch_deg', 'safety', ...
                      'n_clip_60_180', 'n_out_60_180', 'n_clip_all', 'n_out_all', ...
                      'q1_same', 'torque_error', 'independence', 'torque_consistency', 'excitation_gain', ...
                      'torque_error_bp', 'independence_bp', 'torque_consistency_bp', 'excitation_gain_bp'});
for k = 1:n
    r = R(k);
    S.run(k) = r.name;  S.speed(k) = r.speed;  S.arm(k) = r.arm;  S.q1_same(k) = r.q1_same;
    S.Q2(k) = false;  S.Q2b(k) = false;  S.pitch_in_0_30(k) = false;  S.safety(k) = false;
    S{k, {'max_pitch_step_deg', 'min_RotSpeed_rpm', 'max_RotSpeed_rpm', 'min_pitch_deg', 'max_pitch_deg', ...
          'n_clip_60_180', 'n_out_60_180', 'n_clip_all', 'n_out_all', 'torque_error', 'independence', ...
          'torque_consistency', 'excitation_gain', 'torque_error_bp', 'independence_bp', ...
          'torque_consistency_bp', 'excitation_gain_bp'}} = NaN(1, 17);
    [D, ch, chk] = read_checked(r, ERRF);
    if isempty(chk), [G, chk] = read_blocklog(r, D(:, strcmpi(ch, 'Time')), DT, ERRF); end
    if ~isempty(chk)
        S.status(k) = "STOPPED: " + chk;
        continue
    end
    S.status(k) = "read";
    col = @(name) D(:, strcmpi(ch, name));
    t   = col('Time');
    sel = t >= T_STAT - DT/2;                                        % 60-180 s (cases.duration)
    ap  = G.command_applied_rad*180/pi;                              % applied pitch, deg (applied_pitch_amendment_1)
    bp1 = col('BldPitch1');                                          % deg, reported only
    gs  = col('GenSpeed')*pi/30;                                     % rad/s
    % safety (metrics.safety, safety_windows_amendment_1)
    S.Q2(k) = r.ok_run && t(end) >= TMAX - DT/2 && all(isfinite(D(:)));   % whole record (spec_E3 criteria.Q2_execution)
    [S.Q2b(k), S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k)] = q2b_pitch_loop(bp1, col('RotSpeed'), DT);   % whole record
    rs = col('RotSpeed');
    S.max_RotSpeed_rpm(k) = max(rs(sel));                            % 60-180 s
    S.min_pitch_deg(k) = min(ap(sel));  S.max_pitch_deg(k) = max(ap(sel));
    out = ap < BETA_MIN | ap > BETA_MAX;                             % out-of-range instants (bounds_amendment_1)
    S.pitch_in_0_30(k) = ~any(out(sel));                             % 60-180 s
    S.safety(k) = S.Q2(k) && S.Q2b(k) && S.max_RotSpeed_rpm(k) <= Q4_MAX && S.pitch_in_0_30(k);
    clip = G.clipped ~= 0;                                           % clipping instants (X3 only, bounds_amendment_1)
    S.n_clip_60_180(k) = nnz(clip(sel));  S.n_out_60_180(k) = nnz(out(sel));     % used by choice_rule
    S.n_clip_all(k) = nnz(clip);          S.n_out_all(k) = nnz(out);             % reported only
    % torque_error and independence with the applied pitch, and with BldPitch1 (reported only)
    gsf = dfilter(gs, DT, CORNERFREQ);
    S.torque_error(k)    = torque_error(col('GenTq'), gsf, ap, sel, prm, VS_MAXTQ);
    S.torque_error_bp(k) = torque_error(col('GenTq'), gsf, bp1, sel, prm, VS_MAXTQ);
    S.independence(k)    = independence(ap(sel), col('RtVAvgxh'), gs, sel);
    S.independence_bp(k) = independence(bp1(sel), col('RtVAvgxh'), gs, sel);
end

% --- differences to X0 at the same speed (torque_consistency, excitation_gain) ------------------
for k = 1:n
    i0 = find(S.speed == S.speed(k) & S.arm == "X0" & S.status == "read");
    if isscalar(i0)
        S.torque_consistency(k)    = S.torque_error(k)    - S.torque_error(i0);
        S.excitation_gain(k)       = S.independence(k)    - S.independence(i0);
        S.torque_consistency_bp(k) = S.torque_error_bp(k) - S.torque_error_bp(i0);
        S.excitation_gain_bp(k)    = S.independence_bp(k) - S.independence_bp(i0);
    end
end
writetable(S, fullfile(OUT, 'metrics_E4X.csv'), 'Delimiter', ';');

for k = 1:n
    V{end+1} = sprintf(['%-7s %s | Q2 %s Q2b %s (max step %.4f deg, min RotSpeed %.3f rpm) | 60-180 s: max RotSpeed %.3f rpm, ' ...
        'applied pitch [%.3f, %.3f] deg, safety %s, clipping %g, out of range %g | whole record: clipping %g, out of range %g | ' ...
        'torque_error %.6f, consistency %.6f | independence %.6f, gain %.6f | BldPitch1 (reported only): torque_error %.6f, ' ...
        'consistency %.6f, independence %.6f, gain %.6f | inputs unchanged %s'], ...
        S.run(k), S.status(k), pf(S.Q2(k)), pf(S.Q2b(k)), S.max_pitch_step_deg(k), S.min_RotSpeed_rpm(k), S.max_RotSpeed_rpm(k), ...
        S.min_pitch_deg(k), S.max_pitch_deg(k), pf(S.safety(k)), S.n_clip_60_180(k), S.n_out_60_180(k), S.n_clip_all(k), ...
        S.n_out_all(k), S.torque_error(k), S.torque_consistency(k), S.independence(k), S.excitation_gain(k), ...
        S.torque_error_bp(k), S.torque_consistency_bp(k), S.independence_bp(k), S.excitation_gain_bp(k), yesno(S.q1_same(k))); %#ok<AGROW>
end

% --- choice_rule ------------------------------------------------------------------------------
cand = ARMS(2:end);                                                 % X1-X3 (choice_rule.retained)
adm = false(size(cand));  mg = NaN(size(cand));
for a = 1:numel(cand)
    ok = true;  why = {};
    for u = SPEEDS
        i = find(S.speed == u & S.arm == cand{a});
        if numel(i) ~= 1 || S.status(i) ~= "read"
            ok = false;  why{end+1} = sprintf('%d m/s: not read', u); %#ok<AGROW>
            continue
        end
        if ~S.safety(i), ok = false;  why{end+1} = sprintf('%d m/s: safety fails', u); end %#ok<AGROW>
        if strcmp(cand{a}, 'X3')                                     % admissible_amendment_1
            if S.n_clip_60_180(i) ~= 0, ok = false;  why{end+1} = sprintf('%d m/s: %g clipping instants', u, S.n_clip_60_180(i)); end %#ok<AGROW>
        else
            if S.n_out_60_180(i) ~= 0, ok = false;  why{end+1} = sprintf('%d m/s: %g out-of-range instants', u, S.n_out_60_180(i)); end %#ok<AGROW>
        end
        if ~(S.torque_consistency(i) <= TQ_MAX)
            ok = false;  why{end+1} = sprintf('%d m/s: torque_consistency %.6f > %g', u, S.torque_consistency(i), TQ_MAX); %#ok<AGROW>
        end
        if ~(S.excitation_gain(i) >= GAIN_MIN)
            ok = false;  why{end+1} = sprintf('%d m/s: excitation_gain %.6f < %g', u, S.excitation_gain(i), GAIN_MIN); %#ok<AGROW>
        end
    end
    adm(a) = ok;
    mg(a) = mean(S.excitation_gain(S.arm == cand{a}));
    if ok, wtxt = 'admissible'; else, wtxt = ['not admissible (' strjoin(why, '; ') ')']; end
    V{end+1} = sprintf('%s: %s; mean excitation_gain over the two speeds %.6f', cand{a}, wtxt, mg(a)); %#ok<AGROW>
end
if ~any(adm)
    ret = 'X0';
    V{end+1} = 'no admissible arm: E4 uses X0 (DISCON only), to be stated in spec_E4 (choice_rule.retained)';
else
    best = max(mg(adm));
    near = cand(adm & best - mg < TIE);                              % tie: between admissible arms only
    ret = '';
    for a = 1:numel(TIE_ORDER)
        if any(strcmp(near, TIE_ORDER{a})), ret = TIE_ORDER{a}; break, end
    end
    V{end+1} = sprintf('largest mean excitation_gain among admissible arms %.6f; admissible arms within %g of it: %s; order X2, X1, X3 (choice_rule.tie)', ...
                       best, TIE, strjoin(near, ', '));
end
V{end+1} = sprintf('RETAINED: %s', ret);
write_lines(fullfile(OUT, 'verdict_E4X.txt'), V);
fprintf('%s\n', V{:});
end

% =============================================================================================
function gsf = dfilter(gs, DT, cf)
% DISCON low-pass filter rebuilt at every output step from t = 0 (spec_E2 validation.V3_pitch_steps.compare):
% GenSpeedF = (1 - Alpha) x GenSpeed + Alpha x GenSpeedF, Alpha = exp(-DT x CornerFreq),
% initial GenSpeedF = first GenSpeed (DISCON.F90 l.58, l.303, l.355, l.360)
alpha = exp(-DT*cf);
gsf = zeros(size(gs));
gsf(1) = gs(1);
for k = 2:numel(gs)
    gsf(k) = (1 - alpha)*gs(k) + alpha*gsf(k-1);
end
end

function e = torque_error(gentq_knm, gsf, pitch_deg, sel, prm, maxtq)
% RMS over sel of (GenTq x 1000 - Q_g)/VS_MaxTq; Q_g = rom_torque_law(omega_f, beta_deg, p) with
% beta_deg at step k = pitch at step k-1 and, at the first step, the pitch of that step
% (spec_E4X metrics.torque_error, torque_error_amendment_1)
beta = [pitch_deg(1); pitch_deg(1:end-1)];
qg = zeros(size(gsf));
for k = 1:numel(gsf)
    qg(k) = rom_torque_law(gsf(k), beta(k), prm);
end
x = (gentq_knm*1000 - qg)/maxtq;
e = sqrt(mean(x(sel).^2));
end

function v = independence(y, vw, gs, sel)
% 1 - R^2 of the least-squares fit of y on [1, RtVAvgxh, GenSpeed] at the same output step, over
% sel, solved with the backslash operator (spec_E4X metrics.independence)
A = [ones(nnz(sel), 1), vw(sel), gs(sel)];
b = A\y;
res = y - A*b;
v = sum(res.^2)/sum((y - mean(y)).^2);                              % 1 - R^2 = SS_res/SS_tot
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

function [G, chk] = read_blocklog(r, t, DT, errf)
% block log of run_E4X (spec_E4X excitation.logging), one row per output time, times checked
% against the .outb as analyse_E3b.m read_wraplog
G = [];  chk = '';
COLS = {'p_deg', 'p_prev_deg', 'genspeed_to_discon_rad_s', 'bldpitch_to_discon_rad', ...
        'command_before_clip_rad', 'command_applied_rad', 'clipped', 'electrical_power_applied_W', ...
        'pitch_command_rad', 'torque_Nm', 'electrical_power_W', 'record45_rad', 'record47_Nm', 'aviFAIL'};
if isempty(r.wraplog) || ~exist(r.wraplog, 'file'), chk = 'block log missing';  return, end
try
    L = load(r.wraplog, 't', 'g', 'cols', 'arm');
catch ME
    log_error(errf, [r.name ' block log'], ME);
    chk = 'block log not readable';  return
end
if ~isequal(L.cols, COLS) || size(L.g, 2) ~= numel(COLS) || ~strcmp(L.arm, r.arm)
    chk = 'block log columns or arm not recognised';  return
end
if numel(L.t) ~= numel(t) || max(abs(L.t(:) - t(:))) > DT/100
    chk = sprintf('block log times differ from the .outb (%d rows, %d output steps)', numel(L.t), numel(t));  return
end
G = struct('command_applied_rad', double(L.g(:, 6)), 'clipped', double(L.g(:, 7)));
end

function [D, N, chk] = read_checked(r, errf)
% read a .outb and check its OutList and units (spec_E3 channels.verified, channels.units), copied
% from run_E2_V4data.m (RtVAvgxh in m/s)
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
         'RtVAvgxh', 'm/s'};                                                     % spec_E4X metrics.independence
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
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function s = yesno(ok)
if ok, s = 'yes'; else, s = 'no'; end
end

function s = yn(ok)
if ok, s = 'completed'; else, s = 'error'; end
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
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
