function plot_E2_figure()
%PLOT_E2_FIGURE  Figure 1 of step E2 for Paper_Q1: median and P95 of e_max per mean wind speed, model
%v1 and model v2, case (a), with the acceptance thresholds (author's decision of 23/10/2026).
%
%   Run ONCE from the repository root (separate authorisation):
%       >> addpath('openfast_q1/E2');  plot_E2_figure
%
%   Reads ONLY the frozen analysis outputs below (rows group = all, 3 seeds pooled), checked by SHA-256:
%     results/Q1-E2-V4-2026-10-22-a/V4_per_speed.csv   model v1, hub-height wind Wind1VelX
%     results/Q1-E2-V4-2026-10-23-b/V4b_per_speed.csv  model v2, rotor-effective wind RtVAvgxh (assumed known)
%   Thresholds: median e_max 2 % and P95 e_max 5 % of rated rotor speed (openfast_q1/E2/spec_E2.yaml,
%   validation.V4_turbulent_segments.pass).
%   Refuses to run (error, nothing written) if openfast_q1/ is not clean in Git, if an input SHA-256
%   differs, or if the output folder results/Q1-E2-FIG-<yyyy-MM-dd>-a/ already exists.
%   Writes in that folder: E2_fig1_emax_by_speed.pdf (vector), E2_fig1_emax_by_speed.png (300 dpi)
%   and E2_fig1_emax_by_speed_stamp.txt (repository commit, clean-tree status, SHA-256 of this
%   script, of every file read and of every file written), as plot_E1_figures_v2.m.

NAME    = 'E2_fig1_emax_by_speed';
SPEEDS  = [12 14 16 18 20 22 24];          % m/s, spec_E3 E3b_region3_qualification.mean_speeds
THR_MED = 2;                               % %, spec_E2 validation.V4_turbulent_segments.pass (median e_max)
THR_P95 = 5;                               % %, spec_E2 validation.V4_turbulent_segments.pass (P95 e_max)
IN = struct( ...
  'rel',   {'results/Q1-E2-V4-2026-10-22-a/V4_per_speed.csv', 'results/Q1-E2-V4-2026-10-23-b/V4b_per_speed.csv'}, ...
  'sha',   {'8b51eebb8c191620da86e13e302e707b15a430c8c77ef6ff8b524bfbc9630bfc', ...
            'd9347ff0a530b18f0a713ca2487299702517ceb61432b5455812d7e8b2e5cdab'}, ...
  'label', {'model v1: hub-height wind Wind1VelX', 'model v2: rotor-effective wind RtVAvgxh (assumed known)'}, ...
  'style', {'-s', '-o'}, ...
  'face',  {'w', 'k'});
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
abs_ = @(rel) fullfile(ROOT, strrep(rel, '/', filesep));

% --- refusals ---------------------------------------------------------------------------------
[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1', ROOT));
if st ~= 0 || ~isempty(strtrim(o))
    error('plot_E2_figure:dirty', 'Working tree not clean (openfast_q1/):\n%s', o);
end
for k = 1:numel(IN)
    if ~exist(abs_(IN(k).rel), 'file') || ~strcmp(sha256_file(abs_(IN(k).rel)), IN(k).sha)
        error('plot_E2_figure:input', '%s is missing or its SHA-256 differs from %s.', IN(k).rel, IN(k).sha);
    end
end
ID  = ['Q1-E2-FIG-' char(datetime('now', 'Format', 'yyyy-MM-dd')) '-a'];
OUT = fullfile(ROOT, 'results', ID);
if isfolder(OUT), error('plot_E2_figure:exists', 'Output folder already exists: %s', OUT); end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);

% --- data: rows group = all ---------------------------------------------------------------------
for k = 1:numel(IN)
    T = readtable(abs_(IN(k).rel), 'Delimiter', ';', 'TextType', 'string');
    T = sortrows(T(T.group == "all", :), 'speed');
    if height(T) ~= numel(SPEEDS) || ~isequal(T.speed(:)', SPEEDS)
        error('plot_E2_figure:speeds', '%s: rows group = all do not cover exactly %s m/s.', IN(k).rel, mat2str(SPEEDS));
    end
    IN(k).med = 100*T.median_emax_a;                             % percent of rated rotor speed
    IN(k).p95 = 100*T.p95_emax_a;
    if ~all(isfinite([IN(k).med; IN(k).p95]))
        error('plot_E2_figure:value', '%s: a median or P95 of e_max is not finite.', IN(k).rel);
    end
end
mkdir(OUT);

% --- figure -----------------------------------------------------------------------------------
h = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 16 14]);
tl = tiledlayout(h, 2, 1, 'TileSpacing', 'compact');
panel(nexttile(tl), IN, SPEEDS, 'med', THR_MED, 'Median of e_{max} (% of rated rotor speed)');
panel(nexttile(tl), IN, SPEEDS, 'p95', THR_P95, 'P95 of e_{max} (% of rated rotor speed)');
xlabel(tl, 'Mean wind speed (m/s)');
png = fullfile(OUT, [NAME '.png']);  pdf = fullfile(OUT, [NAME '.pdf']);
exportgraphics(h, png, 'Resolution', 300);
exportgraphics(h, pdf, 'ContentType', 'vector');
close(h);

% --- stamp ------------------------------------------------------------------------------------
fid = fopen(fullfile(OUT, [NAME '_stamp.txt']), 'w');
fprintf(fid, 'figure: %s\n', NAME);
fprintf(fid, 'produced_at: %s\n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
fprintf(fid, 'repository_commit: %s (openfast_q1/ clean)\n', head);
fprintf(fid, 'script: %s  openfast_q1/E2/plot_E2_figure.m\n', sha256_file([mfilename('fullpath') '.m']));
for k = 1:numel(IN)
    fprintf(fid, 'input: %s  %s\n', IN(k).sha, IN(k).rel);
end
fprintf(fid, 'output: %s  %s\n', sha256_file(png), [NAME '.png']);
fprintf(fid, 'output: %s  %s\n', sha256_file(pdf), [NAME '.pdf']);
fprintf(fid, 'check: %d series of %d mean wind speeds (rows group = all), thresholds %g %% (median) and %g %% (P95)\n', ...
        numel(IN), numel(SPEEDS), THR_MED, THR_P95);
fclose(fid);
fprintf('Figure written to %s\n', OUT);
end

% =========================================================================================
function panel(ax, IN, speeds, field, thr, ylab)
% one panel: the two series (distinct markers, black and white), the threshold (dashed), a legend
hold(ax, 'on');
for k = 1:numel(IN)
    plot(ax, speeds, IN(k).(field), IN(k).style, 'Color', 'k', 'MarkerFaceColor', IN(k).face, ...
         'MarkerSize', 6, 'LineWidth', 1, 'DisplayName', IN(k).label);
end
yline(ax, thr, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1, 'DisplayName', sprintf('acceptance threshold (%g %%)', thr));
ymax = max([IN(1).(field); IN(2).(field); thr]);
xlim(ax, [speeds(1) - 1, speeds(end) + 1]);  ylim(ax, [0, 1.1*ymax]);
xticks(ax, speeds);  grid(ax, 'on');  box(ax, 'on');
ylabel(ax, ylab);
legend(ax, 'Location', 'northwest');
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
