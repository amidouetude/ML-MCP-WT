function figures_E1(dossier_campagne)
%FIGURES_E1  Figures de l'etape E1 (action E1-4a), a partir des seuls fichiers acceptes.
%
%   figures_E1('results/Q1-E1-AEROMAP-2026-10-08-a')
%
%   Lit UNIQUEMENT :
%     model/5MW_Land_AeroMap/E1_B1.outb et E1_B3.outb   (lot accepte le 09/10/2026)
%     analyse/C3_C4_par_vent.csv                        (analyse pre-enregistree, verdict ACCEPTEE)
%   Produit dans <dossier_campagne>/figures/ (refuse si ce dossier existe) :
%     E1_fig1_surface_Cp.png / .pdf      surface Cp(lambda, beta) de B3, lambda de 3 a 13
%     E1_fig2_beta_eq.png / .pdf         pas d'equilibre selon le vent (B2, via l'analyse) et tableau 7-1
%     E1_fig3_pic_Cp.png / .pdf          zone du pic (B1, vent fixe 8 m/s)
%   et, pour chaque figure, une estampille <nom>_estampille.txt : commit du depot, proprete,
%   SHA-256 du script, de chaque fichier lu et de chaque fichier produit.
%   Refuse si openfast_q1/ ou common/ n'est pas propre dans Git.

TB   = 'C:\dev\matlab-toolbox\Utilities';            % ReadFASTbinary.m, commit 66256c2
ROOT = fileparts(fileparts(fileparts(mfilename('fullpath'))));
CASE = fullfile(dossier_campagne, 'model', '5MW_Land_AeroMap');
FIG  = fullfile(dossier_campagne, 'figures');
f1   = fullfile(CASE, 'E1_B1.outb');
f3   = fullfile(CASE, 'E1_B3.outb');
fc   = fullfile(dossier_campagne, 'analyse', 'C3_C4_par_vent.csv');

[st, o] = system(sprintf('git -C "%s" status --porcelain -- openfast_q1 common', ROOT));
if st ~= 0 || ~isempty(strtrim(o))
    error('figures_E1:sale', 'Arbre non propre (openfast_q1/ ou common/) :\n%s', o);
end
if isfolder(FIG), error('figures_E1:existe', 'Le dossier figures/ existe deja.'); end
[~, head] = system(sprintf('git -C "%s" rev-parse HEAD', ROOT));  head = strtrim(head);

addpath(TB);  nettoyage = onCleanup(@() rmpath(TB));
B1 = lire(f1);  B3 = lire(f3);
T  = readtable(fc, 'Delimiter', ';');
mkdir(FIG);

% --- Figure 1 : surface Cp(lambda, beta), B3, lambda de 3 a 13 -------------------------
s  = B3.TSR >= 3 - 1e-9;
L  = unique(round(B3.TSR(s), 6));  Bt = unique(round(B3.Pitch(s), 6));
Z  = nan(numel(Bt), numel(L));
for i = find(s).'
    Z(abs(Bt - round(B3.Pitch(i),6)) < 1e-9, abs(L - round(B3.TSR(i),6)) < 1e-9) = B3.Cp(i);
end
h = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 16 11]);
contourf(L, Bt, max(Z, 0), 0:0.04:0.48, 'LineColor', [0.4 0.4 0.4]);  hold on
contour(L, Bt, Z, [0 0], 'k', 'LineWidth', 1.2);
plot(7.55, 0, 'kp', 'MarkerFaceColor', 'w', 'MarkerSize', 10);
cb = colorbar;  cb.Label.String = 'C_p (-)';  clim([0 0.5]);
xlabel('Tip-speed ratio \lambda (-)');  ylabel('Blade pitch \beta (deg)');
title('C_p(\lambda,\beta), OpenFAST v4.2.1 steady state, \Omega = 12.1 rpm');
legend({'C_p', 'C_p = 0', 'Jonkman et al. (2009) peak'}, 'Location', 'northeast');
sauver(h, FIG, 'E1_fig1_surface_Cp', head, {f3}, mfilename('fullpath'));

% --- Figure 2 : pas d'equilibre selon le vent ------------------------------------------
h = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 16 10]);
plot(T.vent_m_s, T.pas_tableau_7_1_deg, 'ks', 'MarkerSize', 7, 'DisplayName', 'Jonkman et al. (2009), Table 7-1');  hold on
plot(T.vent_m_s, T.beta_eq_deg, 'o-', 'LineWidth', 1.2, 'DisplayName', 'OpenFAST v4.2.1 (this work)');
yyaxis right;  bar(T.vent_m_s, T.beta_eq_deg - T.pas_tableau_7_1_deg, 0.4, 'FaceAlpha', 0.3, 'DisplayName', 'Difference');
ylabel('Difference (deg)');  yyaxis left;
xlabel('Wind speed (m/s)');  ylabel('Equilibrium pitch \beta_{eq} (deg)');  grid on
title('Above-rated equilibrium pitch at \Omega = 12.1 rpm, P_{aero} = 5.29661 MW');
legend('Location', 'northwest');
sauver(h, FIG, 'E1_fig2_beta_eq', head, {fc}, mfilename('fullpath'));

% --- Figure 3 : zone du pic, B1 (vent fixe 8 m/s) --------------------------------------
h = figure('Visible', 'off', 'Units', 'centimeters', 'Position', [2 2 16 10]);
Bp = unique(round(B1.Pitch, 6));  col = parula(numel(Bp) + 1);
for j = 1:numel(Bp)
    k = abs(B1.Pitch - Bp(j)) < 1e-9;  [x, o] = sort(B1.TSR(k));  y = B1.Cp(k);
    plot(x, y(o), '-', 'Color', col(j,:), 'DisplayName', sprintf('\\beta = %.2f deg', Bp(j)));  hold on
end
[cpx, i] = max(B1.Cp);
plot(B1.TSR(i), cpx, 'ro', 'MarkerFaceColor', 'r', 'DisplayName', sprintf('grid maximum (%.4f)', cpx));
plot(7.55, 0.482, 'kp', 'MarkerFaceColor', 'w', 'MarkerSize', 10, 'DisplayName', 'Jonkman et al. (2009)');
xlabel('Tip-speed ratio \lambda (-)');  ylabel('C_p (-)');  grid on
title('C_p near its peak, wind speed fixed at 8 m/s');
legend('Location', 'eastoutside');
sauver(h, FIG, 'E1_fig3_pic_Cp', head, {f1}, mfilename('fullpath'));
fprintf('Figures ecrites dans %s\n', FIG);
end

% =====================================================================================
function S = lire(f)
[D, N] = ReadFASTbinary(f);
col = @(n) D(:, find(strcmp(strtrim(N), n), 1));
S.Pitch = col('Pitch');  S.TSR = col('TSR');  S.Cp = col('RtAeroCp');
end

function sauver(h, FIG, nom, head, entrees, script)
png = fullfile(FIG, [nom '.png']);  pdf = fullfile(FIG, [nom '.pdf']);
exportgraphics(h, png, 'Resolution', 300);
exportgraphics(h, pdf, 'ContentType', 'vector');
close(h);
fid = fopen(fullfile(FIG, [nom '_estampille.txt']), 'w');
fprintf(fid, 'figure: %s\n', nom);
fprintf(fid, 'produite_le: %s\n', char(datetime('now')));
fprintf(fid, 'commit_depot: %s (openfast_q1/ et common/ propres)\n', head);
fprintf(fid, 'script: %s  openfast_q1/E1/figures_E1.m\n', sha256f([script '.m']));
for k = 1:numel(entrees)
    fprintf(fid, 'lu: %s  %s\n', sha256f(entrees{k}), entrees{k});
end
fprintf(fid, 'produit: %s  %s\n', sha256f(png), [nom '.png']);
fprintf(fid, 'produit: %s  %s\n', sha256f(pdf), [nom '.pdf']);
fclose(fid);
end

function h = sha256f(p)
md = java.security.MessageDigest.getInstance('SHA-256');
d  = md.digest(java.nio.file.Files.readAllBytes(java.io.File(p).toPath()));
h  = lower(reshape(dec2hex(typecast(d, 'uint8'), 2).', 1, []));
end
