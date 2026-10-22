function analyse_E2_V3(OUT, R, cp_file)
%ANALYSE_E2_V3  Comparison of the E2 reduced-order model with OpenFAST for the V3 pitch steps
%(openfast_q1/E2/spec_E2.yaml, validation.V3_pitch_steps, amendment 6).
%
%   analyse_E2_V3(OUT, R, cp_file)    called once by run_E2_V3 at the end of the campaign
%
%   R: the 6 runs of run_E2_V3; cp_file: Cp table of E2 (rom_params).
%   Every catch appends getReport(ME, 'extended') to OUT/errors_E2_V3.txt.
%   Every .outb is read and its OutList and units checked (RotSpeed and GenSpeed in rpm, BldPitch1 in
%   deg, Wind1VelX and RtVAvgxh in m/s); a difference marks the run STOPPED (not evaluated).
%   compare   (validation.V3_pitch_steps.compare) omega_f rebuilt at every output step from t = 0 from
%             GenSpeed (rad/s) with the DISCON filter, GenSpeedF = (1 - Alpha) x GenSpeed +
%             Alpha x GenSpeedF, Alpha = exp(-DT x CornerFreq), initial GenSpeedF = first GenSpeed;
%             model initialised at t = 60 s with x0 = [RotSpeed(60 s) x pi/30; omega_f(60 s)], then for
%             k = 0..199 x(k+1) = rom_step(x(k), BldPitch1(60 + k Ts), Wind1VelX(60 + k Ts), variant, p)
%             (inputs held over one Ts = 0.05 s, rom_step); each instant 60 + k Ts is found by index and
%             checked against Time within DT/100; for variants 'i' and 'ii'
%   errors    e(k) = |omega_r model - RotSpeed x pi/30| / omega_r_rated at 60 + k Ts; e_max over
%             k = 0..30 (first 1.5 s) and over k = 0..200 (10 s, reported only), max with 'includenan'
%   variant_rule  the variant with the lower sum over the 6 runs of e_max (1.5 s) is retained; equal
%             sums: 'i' (author decision of 22/10/2026); if a sum is not finite (a run not evaluated or
%             a NaN error), no variant is retained
%   pass      per run, e_max (1.5 s) of the retained variant <= 2 % of rated rotor speed; V3 is
%             SATISFAIT if the 6 runs pass (pass judged on the retained variant, the other reported;
%             author decision of 22/10/2026)
%   reported_only  realised step BlPitchF - BldPitch1(60 s); max |BldPitch1(t) - BldPitch1(60 s)| over
%             50-60 s; RotSpeed change at 61.5 s and at 70 s relative to RotSpeed(60 s); ratio
%             RtVAvgxh / Wind1VelX over 60-70 s (mean, min, max; outputs_added); n_domain and n_guard
%             of the model per variant; inputs unchanged before and after each run
%   Writes OUT/verdict_E2_V3.txt, OUT/V3_runs.csv and OUT/V3_trajectories.mat.

T0      = 60;                   % s, validation.V3_pitch_steps.maneuver (TPitManS) and .compare
DT      = 0.00625;              % s, spec_E3 channels.output_format (DT_Out = DT)
K_PASS  = 30;                   % steps, first 1.5 s at Ts = 0.05 s (validation.V3_pitch_steps.pass)
K_ALL   = 200;                  % steps, 10 s window (validation.V3_pitch_steps.pass, reported only)
E_PASS  = 0.02;                 % fraction of rated rotor speed, validation.V3_pitch_steps.pass
VARS    = {'i', 'ii'};          % validation.V3_pitch_steps.variant_rule (spec_E2 model.disturbance)
T_PREV  = [50 60];              % s, validation.V3_pitch_steps.reported_only
T_DROT  = [61.5 70];            % s, validation.V3_pitch_steps.reported_only

[~, ID] = fileparts(OUT);
ERRF = fullfile(OUT, 'errors_E2_V3.txt');
p  = rom_params(cp_file);
Ts = p.Ts;                      % 0.05 s, spec_E2 nmpc_interface.Ts
n  = numel(R);
nv = numel(VARS);
S = table('Size', [n 15], 'VariableTypes', [{'string', 'double', 'string', 'string', 'double', 'logical'}, repmat({'double'}, 1, 9)], ...
          'VariableNames', {'run', 'speed', 'dir', 'status', 'BlPitchF_deg', 'inputs_same', 'realised_step_deg', ...
                            'max_pitch_dev_50_60_deg', 'dRotSpeed_61p5_rpm', 'dRotSpeed_70_rpm', 'ratio_RtVAvgxh_mean', ...
                            'ratio_RtVAvgxh_min', 'ratio_RtVAvgxh_max', 'wall_s', 'ncalls'});
EM15 = nan(n, nv);  EM10 = nan(n, nv);  NDOM = nan(n, nv);  NGRD = nan(n, nv);
TR = struct('run', {}, 't', {}, 'omega_openfast', {}, 'omega_model', {}, 'beta_deg', {}, 'V_hub', {});
for k = 1:n
    r = R(k);
    S.run(k) = r.name;  S.speed(k) = r.speed;  S.dir(k) = r.dir;  S.BlPitchF_deg(k) = str2double(r.BlPitchF);
    S.inputs_same(k) = r.inputs_same;  S.wall_s(k) = r.wall_s;  S.ncalls(k) = r.ncalls;
    S{k, 7:13} = NaN(1, 7);
    [D, ch, chk] = read_checked(r, ERRF);
    if isempty(chk)
        col = @(name) D(:, strcmpi(ch, name));
        t = col('Time');
        tk = T0 + (0:K_ALL)'*Ts;                                   % instants 60 + k Ts
        ik = round(tk/DT) + 1;
        if ik(end) > numel(t) || any(abs(t(min(ik, numel(t))) - tk) > DT/100)
            chk = 'output times do not contain the instants 60 + k Ts';
        end
    end
    if ~isempty(chk)
        S.status(k) = "STOPPED: " + chk;
        continue
    end
    S.status(k) = "read";
    rs = col('RotSpeed');  bp = col('BldPitch1');  vx = col('Wind1VelX');
    gs = col('GenSpeed')*pi/30;                                    % rpm -> rad/s
    alpha = exp(-DT*p.CornerFreq);                                 % Alpha (DISCON.F90 l.355, constant DT)
    gsf = zeros(size(gs));  gsf(1) = gs(1);                        % initial GenSpeedF = first GenSpeed (l.303)
    for m = 2:numel(gs), gsf(m) = (1 - alpha)*gs(m) + alpha*gsf(m-1); end   % l.360
    om_of = rs(ik)*pi/30;
    om_md = nan(K_ALL + 1, nv);
    for v = 1:nv
        x = [rs(ik(1))*pi/30; gsf(ik(1))];
        om_md(1, v) = x(1);  nd = 0;  ng = 0;
        for q = 1:K_ALL                                            % k = 0..199
            [x, info] = rom_step(x, bp(ik(q)), vx(ik(q)), VARS{v}, p);
            om_md(q + 1, v) = x(1);  nd = nd + info.n_domain;  ng = ng + info.n_guard;
        end
        e = abs(om_md(:, v) - om_of)/p.omega_r_rated;
        EM15(k, v) = max(e(1:K_PASS + 1), [], 'includenan');
        EM10(k, v) = max(e, [], 'includenan');
        NDOM(k, v) = nd;  NGRD(k, v) = ng;
    end
    i60 = ik(1);
    S.realised_step_deg(k) = S.BlPitchF_deg(k) - bp(i60);
    sp = t >= T_PREV(1) - DT/2 & t <= T_PREV(2) + DT/2;
    S.max_pitch_dev_50_60_deg(k) = max(abs(bp(sp) - bp(i60)), [], 'includenan');
    S.dRotSpeed_61p5_rpm(k) = rs(round(T_DROT(1)/DT) + 1) - rs(i60);
    S.dRotSpeed_70_rpm(k)   = rs(round(T_DROT(2)/DT) + 1) - rs(i60);
    sw = t >= T0 - DT/2 & t <= T_DROT(2) + DT/2;
    ratio = col('RtVAvgxh')./vx;
    S.ratio_RtVAvgxh_mean(k) = mean(ratio(sw));
    S.ratio_RtVAvgxh_min(k)  = min(ratio(sw), [], 'includenan');
    S.ratio_RtVAvgxh_max(k)  = max(ratio(sw), [], 'includenan');
    TR(end+1) = struct('run', r.name, 't', tk, 'omega_openfast', om_of, 'omega_model', om_md, ...
                       'beta_deg', bp(ik), 'V_hub', vx(ik)); %#ok<AGROW>
end

% --- variant rule and pass ------------------------------------------------------------------------
sums = sum(EM15, 1);                                               % NaN if a run is not evaluated
if all(isfinite(sums))
    if sums(2) < sums(1), iv = 2; else, iv = 1; end                % equal sums: 'i'
    retained = VARS{iv};
    pass_run = EM15(:, iv) <= E_PASS;
else
    iv = 0;  retained = 'none (a sum is not finite)';
    pass_run = false(n, 1);
end
ok = n == 6 && iv > 0 && all(pass_run);

% --- tables ---------------------------------------------------------------------------------------
for v = 1:nv
    S.(sprintf('emax_1p5s_%s', VARS{v})) = EM15(:, v);
    S.(sprintf('emax_10s_%s', VARS{v}))  = EM10(:, v);
    S.(sprintf('n_domain_%s', VARS{v}))  = NDOM(:, v);
    S.(sprintf('n_guard_%s', VARS{v}))   = NGRD(:, v);
end
S.pass_retained = pass_run;
writetable(S, fullfile(OUT, 'V3_runs.csv'), 'Delimiter', ';');
variants = VARS;
save(fullfile(OUT, 'V3_trajectories.mat'), 'TR', 'variants');

% --- report ---------------------------------------------------------------------------------------
V = {sprintf('campaign: %s', ID), 'spec: openfast_q1/E2/spec_E2.yaml (validation.V3_pitch_steps)', ...
     sprintf('cp_table: %s', cp_file)};
for k = 1:n
    V{end+1} = sprintf(['%-7s %s | BlPitchF %.4f deg, realised step %.4f deg, max |pitch - pitch(60 s)| 50-60 s %.4f deg, ' ...
        'RotSpeed change %.4f rpm at 61.5 s, %.4f rpm at 70 s, RtVAvgxh/Wind1VelX %.4f [%.4f, %.4f], inputs unchanged %d, wall %.1f s'], ...
        S.run(k), S.status(k), S.BlPitchF_deg(k), S.realised_step_deg(k), S.max_pitch_dev_50_60_deg(k), ...
        S.dRotSpeed_61p5_rpm(k), S.dRotSpeed_70_rpm(k), S.ratio_RtVAvgxh_mean(k), S.ratio_RtVAvgxh_min(k), ...
        S.ratio_RtVAvgxh_max(k), S.inputs_same(k), S.wall_s(k)); %#ok<AGROW>
    for v = 1:nv
        V{end+1} = sprintf('        variant %-2s: e_max 1.5 s %.5f, e_max 10 s %.5f (fraction of rated rotor speed), n_domain %g, n_guard %g', ...
                           VARS{v}, EM15(k, v), EM10(k, v), NDOM(k, v), NGRD(k, v)); %#ok<AGROW>
    end
end
V{end+1} = sprintf('variant_rule: sum of e_max (1.5 s) over the 6 runs: i %.5f, ii %.5f; retained: %s', sums(1), sums(2), retained);
for k = 1:n
    if iv > 0, e = EM15(k, iv); else, e = NaN; end
    V{end+1} = sprintf('pass (retained variant): %-7s e_max 1.5 s %.5f <= %.2f: %s', S.run(k), e, E_PASS, pf(pass_run(k))); %#ok<AGROW>
end
if ok, verdict = 'SATISFAIT'; else, verdict = 'NON SATISFAIT'; end
V{end+1} = ['VERDICT E2 V3: ' verdict];
write_lines(fullfile(OUT, 'verdict_E2_V3.txt'), V);
fprintf('%s\n', V{:});
end

% =============================================================================================
function [D, N, chk] = read_checked(r, errf)
% read a .outb and check its OutList and units
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
UNITS = {'RotSpeed', 'rpm'; 'GenSpeed', 'rpm'; 'BldPitch1', 'deg'; 'Wind1VelX', 'm/s'; 'RtVAvgxh', 'm/s'};
for k = 1:size(UNITS, 1)
    u = U(strcmpi(N, UNITS{k,1}));
    if numel(u) ~= 1 || ~strcmp(u{1}, UNITS{k,2})
        chk = sprintf('channel %s not found once with unit %s', UNITS{k,1}, UNITS{k,2});  return
    end
end
if isempty(D), chk = 'empty .outb'; end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function s = pf(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end

function write_lines(f, L)
fid = fopen(f, 'w');
fprintf(fid, '%s\n', L{:});
fclose(fid);
end
