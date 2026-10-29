function plot_E3_figure()
%PLOT_E3_FIGURE  Figure E3-2 of Paper_Q1 (section 3.3): wind speed, rotor speed, blade pitch and
%mechanical generator power of two E3b runs on configuration O8, from 60 to 180 s
%(openfast_q1/docs/spec_figures_E3_E4.yaml, E3_2_signals).
%
%   Run ONCE from the repository root (separate authorisation, after the commit of this script):
%       >> addpath('openfast_q1/E3');  plot_E3_figure
%
%   Reads ONLY the two .outb of spec_figures_E3_E4 E3_2_signals.runs, checked by SHA-256:
%     left   results/Q1-E3-QUAL-2026-10-22-d/runs/U18_S31001/...SFunc.outb   18 m/s, seed 31001
%     right  results/Q1-E3-QUAL-2026-10-22-d/runs/U14_S31003/...SFunc.outb   14 m/s, seed 31003
%   with ReadFASTbinary of matlab-toolbox at TB_COMMIT (as run_E3b.m); the names and units of the
%   channels used are checked against the OutList of each file (spec_E3 channels.units).
%   Window 60 to 180 s for both columns (E3_2_signals.window). Panels (E3_2_signals.panels):
%     (1) Wind1VelX and RtVAvgxh (m/s)
%     (2) RotSpeed (rpm), horizontal lines at 12.1 rpm and 1.2 x 12.1 = 14.52 rpm
%         (spec_E3 criteria.Q4_overspeed)
%     (3) BldPitch1 (deg)
%     (4) mechanical generator power GenTq x 1000 x GenSpeed x pi/30 (MW), computed as in
%         analyse_E3b.m for criteria.Q3_power, with a horizontal line at VS_RtPwr = 5.296610 MW and
%         dashed lines at plus and minus 2 % (spec_E3 criteria.Q3_power)
%   Black and white, English labels with units (spec_figures_E3_E4 general.style). No value computed
%   from the data is written on the figure (general.text).
%   Refuses to run (error, nothing written) if openfast_q1/ is not clean in Git, if an input is
%   missing or its SHA-256 differs, if matlab-toolbox is not at TB_COMMIT, or if the output folder
%   results/Q1-E3-FIG-<yyyy-MM-dd>-a/ already exists.
%   Writes in that folder: E3_fig2_signals.pdf (vector), E3_fig2_signals.png (300 dpi) and
%   E3_fig2_signals_stamp.txt (repository commit, clean-tree status, SHA-256 of this script, of every
%   file read and of every file written), as openfast_q1/E2/plot_E2_figure.m
%   (spec_figures_E3_E4 general.data_figures). After the folder is created, a catch appends
%   getReport(ME, 'extended') to errors_E3_fig2.txt and rethrows the error.

NAME      = 'E3_fig2_signals';
T_WIN     = [60 180];                     % s, E3_2_signals.window
DT        = 0.00625;                      % s, output step, spec_E3 channels.output_format
RATED_RPM = 12.1;                         % rpm, spec_E3 criteria.Q4_overspeed
Q4_RPM    = 1.2*12.1;                     % rpm, spec_E3 criteria.Q4_overspeed (14.52 rpm)
VS_RTPWR  = 5296610;                      % W, spec_E3 criteria.Q3_power (DISCON.F90 l.96)
Q3_TOL    = 0.02;                         % spec_E3 criteria.Q3_power
TB_DIR    = 'C:\dev\matlab-toolbox';      % read only
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';   % ReadFASTbinary, as run_E3b.m
RUNS      = 'results/Q1-E3-QUAL-2026-10-22-d/runs/';
OUTB      = '/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.SFunc.outb';
IN = struct( ...                                                  % E3_2_signals.runs
  'rel',   {[RUNS 'U18_S31001' OUTB], [RUNS 'U14_S31003' OUTB]}, ...
  'sha',   {'f79c8785e0607fb3e3a2dc7ae2acfdfc45545ed7e8b68cc4fa62c8b70157d57e', ...
            '8dc40c3a45626651767e7b82468ebe4eb057fb7f3e2bb7ea327e9ee06fb223cc'}, ...
  'head',  {'18 m/s, seed 31001', '14 m/s, seed 31003'});
UNITS = {'Time', 's'; 'Wind1VelX', 'm/s'; 'RtVAvgxh', 'm/s'; 'RotSpeed', 'rpm'; ...
         'BldPitch1', 'deg'; 'GenTq', 'kN-m'; 'GenSpeed', 'rpm'};          % spec_E3 channels.units
GRAY  = [0.6 0.6 0.6];
ROOT  = fileparts(fileparts(fileparts(mfilename('fullpath'))));
abs_  = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals (nothing written) ---------------------------------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', ROOT));
if st ~= 0 || ~isempty(strtrim(o))
    error('plot_E3_figure:dirty', 'Working tree not clean (openfast_q1/):\n%s', o);
end
for k = 1:numel(IN)
    if ~isfile(abs_(IN(k).rel)) || ~strcmp(sha256_file(abs_(IN(k).rel)), IN(k).sha)
        error('plot_E3_figure:input', '%s is missing or its SHA-256 differs from %s.', IN(k).rel, IN(k).sha);
    end
end
[st, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if st ~= 0 || ~strcmp(strtrim(tb), TB_COMMIT)
    error('plot_E3_figure:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT);
end
ID  = ['Q1-E3-FIG-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if isfolder(OUT), error('plot_E3_figure:exists', 'Output folder already exists: %s', OUT); end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);
addpath(fullfile(TB_DIR, 'Utilities'));
mkdir(OUT);
ERRF = fullfile(OUT, 'errors_E3_fig2.txt');

try
    % --- data -----------------------------------------------------------------------------------
    S = cell(1, numel(IN));
    for k = 1:numel(IN)
        S{k} = read_window(abs_(IN(k).rel), UNITS, T_WIN, DT);
        S{k}.Pmech_MW = S{k}.GenTq*1000.*S{k}.GenSpeed*pi/30/1e6;   % W -> MW, as analyse_E3b.m (criteria.Q3_power)
    end

    % --- figure ---------------------------------------------------------------------------------
    h  = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 17 21]);
    tl = tiledlayout(h, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = gobjects(4, 2);
    for c = 1:numel(IN)
        t = S{c}.Time;
        ax(1,c) = nexttile(tl, c);
        hw = plot(ax(1,c), t, S{c}.Wind1VelX, '-', 'Color', GRAY, 'LineWidth', 1.0);
        hold(ax(1,c), 'on');
        hr = plot(ax(1,c), t, S{c}.RtVAvgxh, '--', 'Color', 'k', 'LineWidth', 0.8);
        title(ax(1,c), IN(c).head, 'FontWeight', 'normal');
        ax(2,c) = nexttile(tl, 2 + c);
        plot(ax(2,c), t, S{c}.RotSpeed, '-', 'Color', 'k', 'LineWidth', 0.8);
        yline(ax(2,c), RATED_RPM, '-.', 'rated rotor speed', 'Color', 'k', 'LineWidth', 0.8, 'FontSize', 7);
        yline(ax(2,c), Q4_RPM, ':', '1.2 \times rated rotor speed', 'Color', 'k', 'LineWidth', 1.0, 'FontSize', 7);
        ax(3,c) = nexttile(tl, 4 + c);
        plot(ax(3,c), t, S{c}.BldPitch1, '-', 'Color', 'k', 'LineWidth', 0.8);
        ax(4,c) = nexttile(tl, 6 + c);
        plot(ax(4,c), t, S{c}.Pmech_MW, '-', 'Color', 'k', 'LineWidth', 0.8);
        yline(ax(4,c), VS_RTPWR/1e6, '-', 'rated power', 'Color', GRAY, 'LineWidth', 1.0, 'FontSize', 7);
        yline(ax(4,c), (1 + Q3_TOL)*VS_RTPWR/1e6, '--', '+2 %', 'Color', 'k', 'LineWidth', 0.8, 'FontSize', 7);
        yline(ax(4,c), (1 - Q3_TOL)*VS_RTPWR/1e6, '--', '-2 %', 'Color', 'k', 'LineWidth', 0.8, ...
              'FontSize', 7, 'LabelVerticalAlignment', 'bottom');
        if c == 1
            lg = legend(ax(1,1), [hw hr], {'Wind1VelX (hub height)', 'RtVAvgxh (rotor-effective)'}, ...
                        'Orientation', 'horizontal');
            lg.Layout.Tile = 'north';
        end
    end
    % common y limits in each row, including the reference lines (rows 2 and 4)
    REF = {[], [RATED_RPM Q4_RPM], [], (1 + [-1 1]*Q3_TOL)*VS_RTPWR/1e6};
    FLD = {{'Wind1VelX', 'RtVAvgxh'}, {'RotSpeed'}, {'BldPitch1'}, {'Pmech_MW'}};
    YLB = {'Wind speed (m/s)', 'Rotor speed (rpm)', 'Blade 1 pitch (deg)', 'Mech. gen. power (MW)'};
    for r = 1:4
        v = REF{r}(:);
        for c = 1:numel(IN)
            for f = FLD{r}, v = [v; S{c}.(f{1})(:)]; end %#ok<AGROW>
        end
        lo = min(v);  hi = max(v);  pad = 0.05*(hi - lo);
        for c = 1:numel(IN)
            ylim(ax(r,c), [lo - pad, hi + pad]);  xlim(ax(r,c), T_WIN);
            grid(ax(r,c), 'on');  box(ax(r,c), 'on');
            if r < 4, xticklabels(ax(r,c), {}); end
        end
        ylabel(ax(r,1), YLB{r});
    end
    xlabel(tl, 'Time (s)');
    png = fullfile(OUT, [NAME '.png']);  pdf = fullfile(OUT, [NAME '.pdf']);
    exportgraphics(h, png, 'Resolution', 300);
    exportgraphics(h, pdf, 'ContentType', 'vector');
    close(h);

    % --- stamp ----------------------------------------------------------------------------------
    fid = fopen(fullfile(OUT, [NAME '_stamp.txt']), 'w');
    fprintf(fid, 'figure: %s (spec openfast_q1/docs/spec_figures_E3_E4.yaml, E3_2_signals)\n', NAME);
    fprintf(fid, 'produced_at: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    fprintf(fid, 'repository_commit: %s (openfast_q1/ clean)\n', head);
    fprintf(fid, 'script: %s  openfast_q1/E3/plot_E3_figure.m\n', sha256_file([mfilename('fullpath') '.m']));
    fprintf(fid, 'matlab_toolbox: %s (ReadFASTbinary)\n', TB_COMMIT);
    for k = 1:numel(IN)
        fprintf(fid, 'input: %s  %s\n', IN(k).sha, IN(k).rel);
    end
    fprintf(fid, 'output: %s  %s\n', sha256_file(png), [NAME '.png']);
    fprintf(fid, 'output: %s  %s\n', sha256_file(pdf), [NAME '.pdf']);
    fprintf(fid, 'check: %d runs, window %g-%g s, %d and %d output steps in the window\n', ...
            numel(IN), T_WIN, numel(S{1}.Time), numel(S{2}.Time));
    fclose(fid);
catch ME
    log_error(ERRF, NAME, ME);
    rethrow(ME);
end
fprintf('Figure written to %s\n', OUT);
end

% =========================================================================================
function S = read_window(f, units, win, dt)
% channels of units from one .outb (names and units checked), restricted to the window win (s)
[D, N, U] = ReadFASTbinary(f);
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
S = struct();
for k = 1:size(units, 1)
    j = find(strcmpi(N, units{k,1}));
    if ~isscalar(j) || ~strcmp(U{j}, units{k,2})
        error('plot_E3_figure:channel', '%s: channel %s not found once with unit %s.', f, units{k,1}, units{k,2});
    end
    S.(units{k,1}) = D(:, j);
end
t = S.Time;
if t(1) > win(1) + dt/2 || t(end) < win(2) - dt/2
    error('plot_E3_figure:window', '%s: the record does not cover %g-%g s.', f, win);
end
sel = t >= win(1) - dt/2 & t <= win(2) + dt/2;
S = structfun(@(v) v(sel), S, 'UniformOutput', false);
if any(cellfun(@(v) ~all(isfinite(v)), struct2cell(S)))
    error('plot_E3_figure:value', '%s: a value in the window is not finite.', f);
end
end

function log_error(f, tag, ME)
% append the full error report of a catch (getReport extended)
fid = fopen(f, 'a');
fprintf(fid, '===== %s (%s)\n%s\n', tag, char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
        getReport(ME, 'extended', 'hyperlinks', 'off'));
fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
