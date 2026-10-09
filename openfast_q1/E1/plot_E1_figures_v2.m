function plot_E1_figures_v2(campaign_dir)
%PLOT_E1_FIGURES_V2  Corrected figures of step E1 (supervisor action 1, 09/10/2026).
%
%   plot_E1_figures_v2('results/Q1-E1-AEROMAP-2026-10-08-a')
%
%   Supersedes figures_E1.m (commit 49ab819), whose figure 3 selected pitch values with a
%   1e-9 tolerance and therefore missed 9 of the 13 pitch curves (single-precision outputs).
%   Here every grid value is selected by comparing ROUNDED values (6 decimals).
%   figures_E1.m and its output folder figures/ are left untouched.
%
%   Reads ONLY the accepted files of campaign Q1-E1-AEROMAP-2026-10-08-a:
%     model/5MW_Land_AeroMap/E1_B1.outb and E1_B3.outb   (batch accepted on 09/10/2026)
%     analyse/C3_C4_par_vent.csv                        (pre-registered analysis, verdict ACCEPTEE)
%   Writes to <campaign_dir>/figures_v2/ (refuses if the folder exists):
%     E1_fig1_Cp_surface                   Cp(lambda, beta) from sweep B3, lambda from 3 to 13
%     E1_fig2_equilibrium_pitch_vs_wind    equilibrium pitch vs wind speed (B2, via the analysis) and Table 7-1
%     E1_fig3_Cp_peak_region               Cp near its peak (B1, wind speed fixed at 8 m/s), all 13 pitch values
%   each as .png (300 dpi) and .pdf (vector), plus <name>_stamp.txt: repository commit, clean-tree
%   status, SHA-256 of this script, of every file read and of every file written.
%   Refuses to run if openfast_q1/ or common/ is not clean in Git.

TB   = 'C:\dev\matlab-toolbox\Utilities';            % ReadFASTbinary.m, commit 66256c2
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
CASE = fullfile(campaign_dir, 'model', '5MW_Land_AeroMap');
OUT  = fullfile(campaign_dir, 'figures_v2');
fB1  = fullfile(CASE, 'E1_B1.outb');
fB3  = fullfile(CASE, 'E1_B3.outb');
fcsv = fullfile(campaign_dir, 'analyse', 'C3_C4_par_vent.csv');

[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common', ROOT));
if st ~= 0 || ~isempty(strtrim(o))
    error('plot_E1_figures_v2:dirty', 'Working tree not clean (openfast_q1/ or common/):\n%s', o);
end
if isfolder(OUT), error('plot_E1_figures_v2:exists', 'Output folder already exists: %s', OUT); end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);

addpath(TB);  cleanup = onCleanup(@() rmpath(TB));
B1 = read_outb(fB1);  B3 = read_outb(fB3);
T  = readtable(fcsv, 'Delimiter', ';');
mkdir(OUT);
r6 = @(x) round(x, 6);

% --- Figure 1: Cp(lambda, beta), sweep B3, lambda from 3 to 13 --------------------------
sel  = r6(B3.TSR) >= 3;
lam  = unique(r6(B3.TSR(sel)));  bet = unique(r6(B3.Pitch(sel)));
Z    = nan(numel(bet), numel(lam));
[~, il] = ismember(r6(B3.TSR(sel)), lam);  [~, ib] = ismember(r6(B3.Pitch(sel)), bet);
cp   = B3.Cp(sel);
Z(sub2ind(size(Z), ib, il)) = cp;
assert(~any(isnan(Z(:))), 'Incomplete B3 grid');
h = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 16 11]);
contourf(lam, bet, max(Z, 0), 0:0.04:0.48, 'LineColor', [0.4 0.4 0.4]);  hold on
contour(lam, bet, Z, [0 0], 'k', 'LineWidth', 1.2);
plot(7.55, 0, 'kp', 'MarkerFaceColor', 'w', 'MarkerSize', 10);
cb = colorbar;  cb.Label.String = 'C_p (-)';  clim([0 0.5]);
xlabel('Tip-speed ratio \lambda (-)');  ylabel('Blade pitch \beta (deg)');
title('C_p(\lambda,\beta), OpenFAST v4.2.1 steady state, \Omega = 12.1 rpm');
legend({'C_p', 'C_p = 0', 'Peak, Jonkman et al. (2009)'}, 'Location', 'northeast');
save_figure(h, OUT, 'E1_fig1_Cp_surface', head, {fB3}, ...
    sprintf('grid: %d lambda x %d beta values, lambda in [%.2f, %.2f], beta in [%.1f, %.1f] deg', ...
    numel(lam), numel(bet), min(lam), max(lam), min(bet), max(bet)));

% --- Figure 2: equilibrium pitch vs wind speed -----------------------------------------
h = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 16 11]);
tiledlayout(2, 1, 'TileSpacing', 'compact');
nexttile([1 1]);
plot(T.vent_m_s, T.pas_tableau_7_1_deg, 'ks', 'MarkerSize', 7);  hold on
plot(T.vent_m_s, T.beta_eq_deg, 'o-', 'LineWidth', 1.2);
ylabel('\beta_{eq} (deg)');  grid on
legend({'Jonkman et al. (2009), Table 7-1', 'OpenFAST v4.2.1 (this work)'}, 'Location', 'southeast');
title('Above-rated equilibrium pitch, \Omega = 12.1 rpm, P_{aero} = 5.29661 MW');
nexttile;
bar(T.vent_m_s, T.beta_eq_deg - T.pas_tableau_7_1_deg, 0.5);
xlabel('Wind speed (m/s)');  ylabel('This work - Table 7-1 (deg)');  grid on
save_figure(h, OUT, 'E1_fig2_equilibrium_pitch_vs_wind', head, {fcsv}, ...
    sprintf('%d wind speeds, from %.1f to %.1f m/s', height(T), min(T.vent_m_s), max(T.vent_m_s)));

% --- Figure 3: Cp near its peak, sweep B1 (wind speed fixed at 8 m/s) ------------------
h = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 18 11]);
bp   = unique(r6(B1.Pitch));
cols = parula(numel(bp) + 2);
n_curves = 0;
for j = 1:numel(bp)
    k = r6(B1.Pitch) == bp(j);
    [x, o] = sort(B1.TSR(k));  y = B1.Cp(k);
    plot(x, y(o), '-', 'Color', cols(j,:), 'LineWidth', 1, ...
        'DisplayName', sprintf('\\beta = %.2f deg', bp(j)));  hold on
    n_curves = n_curves + 1;
end
[cpx, i] = max(B1.Cp);
plot(B1.TSR(i), cpx, 'ro', 'MarkerFaceColor', 'r', ...
    'DisplayName', sprintf('Grid maximum (%.4f)', cpx));
plot(7.55, 0.482, 'kp', 'MarkerFaceColor', 'w', 'MarkerSize', 10, 'DisplayName', 'Jonkman et al. (2009)');
xlabel('Tip-speed ratio \lambda (-)');  ylabel('C_p (-)');  grid on
title('C_p near its peak, wind speed fixed at 8 m/s');
legend('Location', 'eastoutside');
assert(n_curves == 13, 'Figure 3 shows %d pitch curves instead of 13', n_curves);
save_figure(h, OUT, 'E1_fig3_Cp_peak_region', head, {fB1}, ...
    sprintf('%d pitch curves plotted (expected 13): %s deg', n_curves, mat2str(bp.', 4)));
fprintf('Figures written to %s (figure 3: %d pitch curves)\n', OUT, n_curves);
end

% =========================================================================================
function S = read_outb(f)
[D, N] = ReadFASTbinary(f);
col = @(n) D(:, find(strcmp(strtrim(N), n), 1));
S.Pitch = col('Pitch');  S.TSR = col('TSR');  S.Cp = col('RtAeroCp');
end

function save_figure(h, OUT, name, head, inputs, check)
png = fullfile(OUT, [name '.png']);  pdf = fullfile(OUT, [name '.pdf']);
exportgraphics(h, png, 'Resolution', 300);
exportgraphics(h, pdf, 'ContentType', 'vector');
close(h);
fid = fopen(fullfile(OUT, [name '_stamp.txt']), 'w');
fprintf(fid, 'figure: %s\n', name);
fprintf(fid, 'produced_at: %s\n', char(datetime('now')));
fprintf(fid, 'repository_commit: %s (openfast_q1/ and common/ clean)\n', head);
fprintf(fid, 'script: %s  openfast_q1/E1/plot_E1_figures_v2.m\n', sha256_file([mfilename('fullpath') '.m']));
for k = 1:numel(inputs)
    fprintf(fid, 'input: %s  %s\n', sha256_file(inputs{k}), inputs{k});
end
fprintf(fid, 'output: %s  %s\n', sha256_file(png), [name '.png']);
fprintf(fid, 'output: %s  %s\n', sha256_file(pdf), [name '.pdf']);
fprintf(fid, 'check: %s\n', check);
fclose(fid);
end

function h = sha256_file(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
