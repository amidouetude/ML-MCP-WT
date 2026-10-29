function plot_E4_figures()
%PLOT_E4_FIGURES  Figure E4-3 of Paper_Q1 (section 4): excitation signal p, applied pitch command
%and rotor speed of arms X0 and X3, from 60 to 120 s (openfast_q1/docs/spec_figures_E3_E4.yaml,
%E4_3_excitation).
%
%   Run ONCE from the repository root (separate authorisation, after the commit of this script):
%       >> addpath('openfast_q1/E4');  plot_E4_figures
%
%   Reads ONLY the four .outb and the four block logs of spec_figures_E3_E4 E4_3_excitation.runs,
%   checked by SHA-256: results/Q1-E4-DATA-2026-10-28-a/runs/<run>/5MW_Land_DLL_WTurb/
%   5MW_Land_DLL_WTurb.SFunc.outb and runs/<run>/wrapper_log.mat for U18_S34001_X0, U18_S34001_X3,
%   U12_S34001_X0 and U12_S34001_X3. The .outb is read with ReadFASTbinary of matlab-toolbox at
%   TB_COMMIT (as run_E4.m), the names and units of the channels used are checked; the block log
%   (variables t, g, cols, arm, written by run_E4.m) must have the 14 columns of run_E4.m, the
%   expected arm and the times of the .outb at every output step (as build_dataset_E4.m).
%   Window 60 to 120 s (E4_3_excitation.window). Panels (E4_3_excitation.panels):
%     (1) p(t) of U18_S34001_X3 (deg, block log column p_deg)
%     (2) applied pitch command at 18 m/s, X0 and X3 (deg, block log column command_applied_rad)
%     (3) RotSpeed at 18 m/s, X0 and X3 (rpm)
%     (4) applied pitch command at 12 m/s, X0 and X3 (deg), with a horizontal line at 0 deg (lower
%         bound of the clipping, spec_E4X bounds_amendment_1)
%   Black and white, English labels with units (general.style). No value of E4 is written on the
%   figure (general.text, E4_3_excitation.caption).
%   Refuses to run (error, nothing written) if openfast_q1/ is not clean in Git, if an input is
%   missing or its SHA-256 differs, if matlab-toolbox is not at TB_COMMIT, or if the output folder
%   results/Q1-E4-FIG-<yyyy-MM-dd>-a/ already exists.
%   Writes in that folder: E4_fig3_excitation.pdf (vector), E4_fig3_excitation.png (300 dpi) and
%   E4_fig3_excitation_stamp.txt (repository commit, clean-tree status, SHA-256 of this script, of
%   every file read and of every file written), as openfast_q1/E2/plot_E2_figure.m
%   (general.data_figures). After the folder is created, a catch appends getReport(ME, 'extended')
%   to errors_E4_fig3.txt and rethrows the error.

NAME      = 'E4_fig3_excitation';
T_WIN     = [60 120];                     % s, E4_3_excitation.window
DT        = 0.00625;                      % s, output step, spec_E3 channels.output_format
P_LOW     = 0;                            % deg, lower bound of the clipping, spec_E4X bounds_amendment_1
TB_DIR    = 'C:\dev\matlab-toolbox';      % read only
TB_COMMIT = '66256c22c8e03a8c3591439af6dc09ee1219a932';   % ReadFASTbinary, as run_E4.m
RUNS      = 'results/Q1-E4-DATA-2026-10-28-a/runs/';
OUTB      = '/5MW_Land_DLL_WTurb/5MW_Land_DLL_WTurb.SFunc.outb';
COLS = {'p_deg', 'p_prev_deg', 'genspeed_to_discon_rad_s', 'bldpitch_to_discon_rad', ...        % block log of run_E4.m
        'command_before_clip_rad', 'command_applied_rad', 'clipped', 'electrical_power_applied_W', ...
        'pitch_command_rad', 'torque_Nm', 'electrical_power_W', 'record45_rad', 'record47_Nm', 'aviFAIL'};
IN = struct( ...                                                  % E4_3_excitation.runs
  'run',     {'U18_S34001_X0', 'U18_S34001_X3', 'U12_S34001_X0', 'U12_S34001_X3'}, ...
  'arm',     {'X0', 'X3', 'X0', 'X3'}, ...
  'outb_sha', {'b9e2b2484d2d6e89e71a9fad4d8107d10e65c9525053603bbd8d04ab00eed739', ...
              '5cd3fb0ec360c4571eefda51bdf421d5096e0a2a5f787775eb4bf17bdce3a715', ...
              '4de1dba42c1067408d18370388b759788ecb559bd3df32b683d77504418e29bf', ...
              'fb06336bea33cf2b80004521c4ce4b0d129d71bf862a126d9c75db6e8e4356de'}, ...
  'log_sha', {'dd3796c82e373eea69d074be9a878f028bf33a250eef074a75dcb7cd5552b4ea', ...
              '9c2ee026963b71ebce94b4d14450913ea726039f585ba09ae11d27d3106b2e72', ...
              '7cc5569ad21c6d1b804e8397b626b25af1551a183a1629a93e8987d4adac51da', ...
              'af73c5e7824aa77566fa123911884b8c0163b8bf105dcc6b55f781d3b0ab23b9'});
UNITS = {'Time', 's'; 'RotSpeed', 'rpm'};                         % spec_E3 channels.units
STY   = struct('X0', {{'-', [0.6 0.6 0.6], 1.0}}, 'X3', {{'--', [0 0 0], 0.8}});   % line style, colour, width
ROOT  = fileparts(fileparts(fileparts(mfilename('fullpath'))));
abs_  = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));
for k = 1:numel(IN)
    IN(k).outb = [RUNS IN(k).run OUTB];
    IN(k).log  = [RUNS IN(k).run '/wrapper_log.mat'];
end

% --- refusals (nothing written) ---------------------------------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', ROOT));
if st ~= 0 || ~isempty(strtrim(o))
    error('plot_E4_figures:dirty', 'Working tree not clean (openfast_q1/):\n%s', o);
end
for k = 1:numel(IN)
    F = {IN(k).outb, IN(k).outb_sha; IN(k).log, IN(k).log_sha};
    for j = 1:2
        if ~isfile(abs_(F{j,1})) || ~strcmp(sha256_file(abs_(F{j,1})), F{j,2})
            error('plot_E4_figures:input', '%s is missing or its SHA-256 differs from %s.', F{j,1}, F{j,2});
        end
    end
end
[st, tb] = system(sprintf('git -C "%s" rev-parse HEAD', TB_DIR));
if st ~= 0 || ~strcmp(strtrim(tb), TB_COMMIT)
    error('plot_E4_figures:toolbox', 'matlab-toolbox is not at %s.', TB_COMMIT);
end
ID  = ['Q1-E4-FIG-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if isfolder(OUT), error('plot_E4_figures:exists', 'Output folder already exists: %s', OUT); end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);
addpath(fullfile(TB_DIR, 'Utilities'));
mkdir(OUT);
ERRF = fullfile(OUT, 'errors_E4_fig3.txt');

try
    % --- data -----------------------------------------------------------------------------------
    S = cell(1, numel(IN));
    for k = 1:numel(IN)
        S{k} = read_run(abs_(IN(k).outb), abs_(IN(k).log), IN(k).arm, UNITS, COLS, T_WIN, DT);
    end
    R = @(name) S{strcmp({IN.run}, name)};

    % --- figure ---------------------------------------------------------------------------------
    h  = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 17 18]);
    tl = tiledlayout(h, 4, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    ax = gobjects(4, 1);
    ax(1) = nexttile(tl, 1);                                          % (1) p of U18_S34001_X3
    a = R('U18_S34001_X3');
    plot(ax(1), a.t, a.p_deg, '-', 'Color', 'k', 'LineWidth', 0.8);
    title(ax(1), 'Excitation signal p, 18 m/s, seed 34001, arm X3', 'FontWeight', 'normal');
    ylabel(ax(1), 'p (deg)');
    ax(2) = nexttile(tl, 2);                                          % (2) applied command, 18 m/s
    hl = pair(ax(2), R('U18_S34001_X0'), R('U18_S34001_X3'), 'cmd_deg', STY);
    title(ax(2), 'Applied pitch command, 18 m/s, seed 34001', 'FontWeight', 'normal');
    ylabel(ax(2), 'Pitch command (deg)');
    ax(3) = nexttile(tl, 3);                                          % (3) RotSpeed, 18 m/s
    pair(ax(3), R('U18_S34001_X0'), R('U18_S34001_X3'), 'RotSpeed', STY);
    title(ax(3), 'Rotor speed, 18 m/s, seed 34001', 'FontWeight', 'normal');
    ylabel(ax(3), 'Rotor speed (rpm)');
    ax(4) = nexttile(tl, 4);                                          % (4) applied command, 12 m/s
    pair(ax(4), R('U12_S34001_X0'), R('U12_S34001_X3'), 'cmd_deg', STY);
    yline(ax(4), P_LOW, ':', 'lower bound of the clipping', 'Color', 'k', 'LineWidth', 1.0, ...
          'FontSize', 7, 'LabelVerticalAlignment', 'bottom');
    title(ax(4), 'Applied pitch command, 12 m/s, seed 34001', 'FontWeight', 'normal');
    ylabel(ax(4), 'Pitch command (deg)');
    lg = legend(ax(2), hl, {'X0: baseline controller only', 'X3: excitation added to the command'}, ...
                'Orientation', 'horizontal');
    lg.Layout.Tile = 'north';
    yl = ylim(ax(4));  ylim(ax(4), [min(yl(1), P_LOW - 0.05*diff(yl)), yl(2)]);   % 0 deg line inside the panel
    for r = 1:4
        xlim(ax(r), T_WIN);  grid(ax(r), 'on');  box(ax(r), 'on');
        if r < 4, xticklabels(ax(r), {}); end
    end
    xlabel(tl, 'Time (s)');
    png = fullfile(OUT, [NAME '.png']);  pdf = fullfile(OUT, [NAME '.pdf']);
    exportgraphics(h, png, 'Resolution', 300);
    exportgraphics(h, pdf, 'ContentType', 'vector');
    close(h);

    % --- stamp ----------------------------------------------------------------------------------
    fid = fopen(fullfile(OUT, [NAME '_stamp.txt']), 'w');
    fprintf(fid, 'figure: %s (spec openfast_q1/docs/spec_figures_E3_E4.yaml, E4_3_excitation)\n', NAME);
    fprintf(fid, 'produced_at: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
    fprintf(fid, 'repository_commit: %s (openfast_q1/ clean)\n', head);
    fprintf(fid, 'script: %s  openfast_q1/E4/plot_E4_figures.m\n', sha256_file([mfilename('fullpath') '.m']));
    fprintf(fid, 'matlab_toolbox: %s (ReadFASTbinary)\n', TB_COMMIT);
    for k = 1:numel(IN)
        fprintf(fid, 'input: %s  %s\n', IN(k).outb_sha, IN(k).outb);
        fprintf(fid, 'input: %s  %s\n', IN(k).log_sha, IN(k).log);
    end
    fprintf(fid, 'output: %s  %s\n', sha256_file(png), [NAME '.png']);
    fprintf(fid, 'output: %s  %s\n', sha256_file(pdf), [NAME '.pdf']);
    fprintf(fid, 'check: %d runs, window %g-%g s, output steps in the window: %s\n', ...
            numel(IN), T_WIN, strjoin(cellfun(@(s) sprintf('%d', numel(s.t)), S, 'UniformOutput', false), ', '));
    fclose(fid);
catch ME
    log_error(ERRF, NAME, ME);
    rethrow(ME);
end
fprintf('Figure written to %s\n', OUT);
end

% =========================================================================================
function hl = pair(ax, s0, s3, field, sty)
% X0 and X3 of the same speed and seed in one panel, distinct line styles (general.style)
st0 = sty.X0;  st3 = sty.X3;
hl = gobjects(1, 2);
hl(1) = plot(ax, s0.t, s0.(field), st0{1}, 'Color', st0{2}, 'LineWidth', st0{3});
hold(ax, 'on');
hl(2) = plot(ax, s3.t, s3.(field), st3{1}, 'Color', st3{2}, 'LineWidth', st3{3});
end

function S = read_run(fo, fl, arm, units, cols, win, dt)
% RotSpeed of the .outb (names and units checked) and p_deg, command_applied_rad of the block log
% (columns, arm and times checked against the .outb, as build_dataset_E4.m), in the window win (s)
[D, N, U] = ReadFASTbinary(fo);
N = strtrim(N(:));  U = erase(strtrim(U(:)), {'(', ')'});
C = struct();
for k = 1:size(units, 1)
    j = find(strcmpi(N, units{k,1}));
    if ~isscalar(j) || ~strcmp(U{j}, units{k,2})
        error('plot_E4_figures:channel', '%s: channel %s not found once with unit %s.', fo, units{k,1}, units{k,2});
    end
    C.(units{k,1}) = D(:, j);
end
t = C.Time;
L = load(fl, 't', 'g', 'cols', 'arm');
if numel(L.cols) ~= numel(cols) || ~all(strcmp(L.cols(:), cols(:))) || size(L.g, 2) ~= numel(cols) || ~strcmp(L.arm, arm)
    error('plot_E4_figures:log', '%s: block log columns or arm not recognised.', fl);
end
if numel(L.t) ~= numel(t) || max(abs(L.t(:) - t(:))) > dt/100
    error('plot_E4_figures:times', '%s: block log times differ from the .outb (%d rows, %d output steps).', fl, numel(L.t), numel(t));
end
if t(1) > win(1) + dt/2 || t(end) < win(2) - dt/2
    error('plot_E4_figures:window', '%s: the record does not cover %g-%g s.', fo, win);
end
sel = t >= win(1) - dt/2 & t <= win(2) + dt/2;
S = struct('t', t(sel), 'RotSpeed', C.RotSpeed(sel), ...
           'p_deg', double(L.g(sel, strcmp(cols, 'p_deg'))), ...
           'cmd_deg', double(L.g(sel, strcmp(cols, 'command_applied_rad')))*180/pi);   % rad -> deg
if any(cellfun(@(v) ~all(isfinite(v)), struct2cell(S)))
    error('plot_E4_figures:value', '%s: a value in the window is not finite.', fo);
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
