function analyse_E3a(OUT, R, stopped)
%ANALYSE_E3A  Metrics, lag choice and verdict of E3a (openfast_q1/E3/spec_E3.yaml).
%
%   analyse_E3a(OUT, R, stopped)    called once by run_E3a at the end of the campaign
%
%   R: runs of run_E3a (run1_exe, run2_sfunc_lag0, run2_sfunc_lag1), with their expected channel
%   lists; stopped: '' or the reason why the S-function runs were not made.
%   - every .outb is read and its OutList and units checked again (spec_E3 channels.verified,
%     channels.units); a difference marks E3a STOPPED
%   - compared channels over 10 to 60 s (spec_E3 E3a_plant_equivalence.compared)
%   - metrics per channel (spec_E3 E3a_plant_equivalence.metrics):
%       max |diff| / (max - min of run 1)   and   mean |diff| / mean |run 1|
%   - retained lag: the lower RMS difference of RotSpeed over the same window; both lags
%     reported (spec_E3 E3a_plant_equivalence.lag_rule)
%   - pass at the retained lag (spec_E3 E3a_plant_equivalence.pass), written CONCORDANT AT EPSILON
%     or NOT CONCORDANT (spec_E3 E3a_plant_equivalence.wording)
%   Writes OUT/verdict_E3a.txt and OUT/metrics_E3a.csv.

COMPARED = {'RotSpeed', 'GenPwr', 'BldPitch1', 'TwrBsMyt', 'RootMyc1'};   % E3a_plant_equivalence.compared
WIN      = [10 60];                    % s, E3a_plant_equivalence.compared
TOL_MAX  = 1e-2;                       % max |diff| / range, E3a_plant_equivalence.pass
TOL_MEAN = 1e-3;                       % mean |diff| / mean |run 1|, E3a_plant_equivalence.pass
DT       = 0.00625;                    % s, channels.output_format

[~, ID] = fileparts(OUT);
V = {sprintf('campaign: %s', ID), 'spec: openfast_q1/E3/spec_E3.yaml (E3a_plant_equivalence)'};
for k = 1:numel(R)
    V{end+1} = sprintf('%s: run %s; wall %.1f s%s', R(k).name, yn(R(k).ok_run), R(k).wall_s, errtxt(R(k).err)); %#ok<AGROW>
end
verdict = '';
if ~isempty(stopped)
    verdict = ['STOPPED (' stopped ')'];
end

% --- read and check -----------------------------------------------------------------------------
D = cell(1, numel(R));
if isempty(verdict)
    for k = 1:numel(R)
        [D{k}, chk] = read_checked(R(k));
        if ~isempty(chk), verdict = sprintf('STOPPED (%s: %s)', R(k).name, chk);  break; end
    end
end
if isempty(verdict) && numel(R) ~= 3
    verdict = 'STOPPED (the two S-function runs are not both available)';
end
if isempty(verdict)
    n = size(D{1}, 1);
    for k = 2:3
        if size(D{k}, 1) ~= n || max(abs(D{k}(:,1) - D{1}(:,1))) > DT/100
            verdict = sprintf('STOPPED (%s: output times differ from run 1)', R(k).name);  break
        end
    end
end

% --- metrics ------------------------------------------------------------------------------------
T = table();
if isempty(verdict)
    t = D{1}(:,1);
    sel = t >= WIN(1) - DT/2 & t <= WIN(2) + DT/2;
    rmsw = zeros(1, 2);
    for k = 2:3
        lag = k - 2;
        for c = 1:numel(COMPARED)
            x1 = D{1}(sel, strcmpi(R(1).channels, COMPARED{c}));
            x2 = D{k}(sel, strcmpi(R(k).channels, COMPARED{c}));
            d  = abs(x2 - x1);
            mr = max(d)/(max(x1) - min(x1));
            me = mean(d)/mean(abs(x1));
            T = [T; table(lag, COMPARED(c), max(d), max(x1) - min(x1), mr, mean(d), mean(abs(x1)), me, ...
                 mr <= TOL_MAX && me <= TOL_MEAN, 'VariableNames', {'lag', 'channel', 'max_abs_diff', ...
                 'range_run1', 'max_rel', 'mean_abs_diff', 'mean_abs_run1', 'mean_rel', 'pass'})]; %#ok<AGROW>
            if strcmp(COMPARED{c}, 'RotSpeed'), rmsw(lag+1) = sqrt(mean((x2 - x1).^2)); end
        end
    end
    writetable(T, fullfile(OUT, 'metrics_E3a.csv'), 'Delimiter', ';');
    [~, i] = min(rmsw);  keep = i - 1;
    V{end+1} = sprintf('RMS difference of RotSpeed over %g-%g s: lag 0 %.6g rpm, lag 1 %.6g rpm; retained lag %d (lag_rule)', ...
                       WIN, rmsw(1), rmsw(2), keep);
    for r = 1:height(T)
        V{end+1} = sprintf('lag %d %-9s max|diff|/range %.3e (<= %.0e), mean|diff|/mean|run1| %.3e (<= %.0e): %s', ...
            T.lag(r), T.channel{r}, T.max_rel(r), TOL_MAX, T.mean_rel(r), TOL_MEAN, pf(T.pass(r))); %#ok<AGROW>
    end
    if all(T.pass(T.lag == keep)), verdict = 'CONCORDANT AT EPSILON'; else, verdict = 'NOT CONCORDANT'; end
    verdict = sprintf('%s (retained lag %d)', verdict, keep);
end
V{end+1} = ['VERDICT E3a: ' verdict];
write_lines(fullfile(OUT, 'verdict_E3a.txt'), V);
fprintf('%s\n', V{:});
end

% =============================================================================================
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
