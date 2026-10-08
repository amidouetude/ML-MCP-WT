function verdict = analyse_E1(dossier_campagne)
%ANALYSE_E1  Analyse pre-enregistree de la campagne Q1-E1-AEROMAP-2026-10-08-a.
%
%   verdict = analyse_E1(dossier_campagne)
%
%   Lit model/5MW_Land_AeroMap/E1_B1.outb, E1_B2.outb, E1_B3.outb, calcule les criteres C1 a C6
%   definis dans openfast_q1/E1/fiche_E1.yaml, et ecrit dans <dossier_campagne>/analyse/ :
%     verdict_E1.txt        criteres, valeurs, tolerances, verdict
%     C3_C4_par_vent.csv    pas d'equilibre et dP/dtheta pour les 15 vents du tableau 7-1
%   Les criteres et tolerances sont codes ici tels qu'ils ont ete adoptes AVANT l'execution.
%   N'ecrit rien si le dossier analyse/ existe deja.

TB      = 'C:\dev\matlab-toolbox\Utilities';         % ReadFASTbinary.m, commit 66256c2
P0      = 5296610;                                   % W, puissance mecanique nominale
CP_REF  = 0.482;  TOL_CP = 0.010;                    % C1
LAM_INT = [7.30 7.80];  BET_INT = [-0.5 0.5];        % C2
TOL_C3  = 1.0;                                       % deg
TOLER   = 1e-4;   MAXIT = 50;                        % convergence (.drv)
N_ATT   = [793 3765 2745];
V71     = [11.4 12 13 14 15 16 17 18 19 20 21 22 23 24 25];
PAS71   = [0.00 3.83 6.60 8.70 10.45 12.06 13.54 14.92 16.23 17.47 18.70 19.94 21.18 22.35 23.47];
DPD71   = -1e6*[28.24 43.73 51.66 58.44 64.44 70.46 76.53 83.94 90.67 94.71 99.04 105.90 114.30 120.20 125.30];

CASE = fullfile(dossier_campagne, 'model', '5MW_Land_AeroMap');
OUT  = fullfile(dossier_campagne, 'analyse');
if isfolder(OUT), error('analyse_E1:existe', 'Le dossier analyse/ existe deja.'); end

addpath(TB);  nettoyage = onCleanup(@() rmpath(TB));
B = cell(1,3);
for k = 1:3
    B{k} = lire(fullfile(CASE, sprintf('E1_B%d.outb', k)), TOLER, MAXIT);
end
L = {};  ok = struct();

% --- C5 : coherence ------------------------------------------------------------------
manq = cellfun(@(x) numel(x.Cp), B) ~= N_ATT;
cpmax_all = max(cellfun(@(x) max(x.Cp(isfinite(x.Cp))), B));
nc = cellfun(@(x) sum(~x.conv), B);
z3 = B{3}.TSR >= 3-1e-6 & B{3}.TSR <= 10+1e-6 & B{3}.Pitch >= -1e-6 & B{3}.Pitch <= 25+1e-6;
nc_utile = sum(~B{2}.conv) + sum(~B{3}.conv & z3);
ok.C5 = cpmax_all <= 16/27 && ~any(manq) && nc_utile == 0;
L{end+1} = sprintf('C5 (acceptation) : Cp max toutes grilles = %.5f (limite 16/27 = %.5f) ; cas par balayage = %d/%d/%d (attendus 793/3765/2745) ; non converges B1/B2/B3 = %d/%d/%d ; dans la zone utile = %d -> %s', ...
    cpmax_all, 16/27, numel(B{1}.Cp), numel(B{2}.Cp), numel(B{3}.Cp), nc, nc_utile, oui(ok.C5));

% --- C1 et C2 : pic de Cp (B1) -----------------------------------------------------------
c = B{1}.conv;  cp = B{1}.Cp;  cp(~c) = -Inf;
[cpx, i] = max(cp);  lx = B{1}.TSR(i);  bx = B{1}.Pitch(i);
ok.C1 = abs(cpx - CP_REF) <= TOL_CP;
ok.C2 = lx >= LAM_INT(1) && lx <= LAM_INT(2) && bx >= BET_INT(1) && bx <= BET_INT(2);
L{end+1} = sprintf('C1 (acceptation) : Cp* = %.5f ; |Cp* - 0,482| = %.5f (tolerance 0,010) -> %s', cpx, abs(cpx-CP_REF), oui(ok.C1));
L{end+1} = sprintf('C2 (acceptation) : lambda* = %.4f (intervalle [7,30 ; 7,80]) ; beta* = %.3f deg (intervalle [-0,5 ; 0,5]) ; vent du cas = %.4f m/s -> %s', lx, bx, B{1}.V(i), oui(ok.C2));

% --- C3 et C4 : tableau 7-1 (B2) ------------------------------------------------------
beq = nan(1,15);  dpd = nan(1,15);  etat = strings(1,15);
for j = 1:15
    s = abs(B{2}.V - V71(j)) < 1e-6;
    [b, o] = sort(B{2}.Pitch(s));  P = B{2}.P(s);  P = P(o);
    if P(1) <= P0
        beq(j) = 0;  etat(j) = "sature a 0";
    else
        k = find(P(1:end-1) > P0 & P(2:end) <= P0, 1);
        if isempty(k), etat(j) = "non defini";
        else
            beq(j) = b(k) + (P0 - P(k)) * (b(k+1) - b(k)) / (P(k+1) - P(k));  etat(j) = "croisement";
        end
    end
    if ~isnan(beq(j))                                 % C4 : differences centrees, W/rad
        d = nan(size(P));
        d(2:end-1) = (P(3:end) - P(1:end-2)) ./ deg2rad(b(3:end) - b(1:end-2));
        d(1) = (P(2) - P(1)) / deg2rad(b(2) - b(1));
        d(end) = (P(end) - P(end-1)) / deg2rad(b(end) - b(end-1));
        dpd(j) = interp1(b, d, beq(j), 'linear');
    end
end
ec = abs(beq - PAS71);
ok.C3 = all(~isnan(beq)) && all(ec <= TOL_C3);
L{end+1} = sprintf('C3 (acceptation) : ecart max |beta_eq - tableau 7-1| = %.3f deg (tolerance 1,0 par vent) ; vents hors tolerance : %d ; non definis : %d -> %s', ...
    max(ec), sum(ec > TOL_C3), sum(isnan(beq)), oui(ok.C3));
L{end+1} = sprintf('C4 (indicatif, sans seuil) : rapport dP/dtheta / tableau 7-1 entre %.3f et %.3f. dP/dtheta compared indicatively; the reference values were obtained by frozen-wake linearization.', ...
    min(dpd./DPD71), max(dpd./DPD71));

% --- C6 : effet de la convention (B1 contre B3, beta = 0) -----------------------------
s1 = abs(B{1}.Pitch) < 1e-6 & B{1}.conv;   s3 = abs(B{3}.Pitch) < 1e-6 & B{3}.conv;
[l1, o1] = sort(B{1}.TSR(s1));  c1 = B{1}.Cp(s1);  c1 = c1(o1);
l3 = B{3}.TSR(s3);  c3 = B{3}.Cp(s3);
in = l3 >= min(l1) & l3 <= max(l1);
dc = c3(in) - interp1(l1, c1, l3(in), 'linear');
[~, i75] = min(abs(l3(in) - 7.5));  l3in = l3(in);
L{end+1} = sprintf('C6 (indicatif) : Cp(B3) - Cp(B1) a beta = 0, lambda dans [%.2f ; %.2f] : max |ecart| = %.5f ; a lambda = %.2f : %+.5f', ...
    min(l1), max(l1), max(abs(dc)), l3in(i75), dc(i75));

% --- verdict --------------------------------------------------------------------------
ech = {};  for c = {'C1','C2','C3','C5'}, if ~ok.(c{1}), ech{end+1} = c{1}; end, end %#ok<AGROW>
if isempty(ech), verdict = 'ACCEPTEE';
else, verdict = ['NON ACCEPTEE (criteres en echec : ' strjoin(ech, ', ') ')'];
end

mkdir(OUT);
fid = fopen(fullfile(OUT, 'verdict_E1.txt'), 'w');
fprintf(fid, 'Campagne Q1-E1-AEROMAP-2026-10-08-a - analyse pre-enregistree (openfast_q1/E1/analyse_E1.m)\n');
fprintf(fid, 'Analyse executee le %s\n\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
fprintf(fid, '%s\n', L{:});
fprintf(fid, '\nVERDICT : %s\n', verdict);
fclose(fid);
T = table(V71.', PAS71.', beq.', ec.', etat.', DPD71.', dpd.', (dpd./DPD71).', ...
    'VariableNames', {'vent_m_s','pas_tableau_7_1_deg','beta_eq_deg','ecart_deg','etat', ...
                      'dPdtheta_tableau_W_rad','dPdtheta_E1_W_rad','rapport'});
writetable(T, fullfile(OUT, 'C3_C4_par_vent.csv'), 'Delimiter', ';');
fprintf('%s\n', L{:});  fprintf('VERDICT : %s\n', verdict);
end

% =====================================================================================
function S = lire(f, toler, maxit)
[D, N] = ReadFASTbinary(f);
col = @(n) D(:, find(strcmp(strtrim(N), n), 1));
S.Pitch = col('Pitch');  S.TSR = col('TSR');  S.V = col('WindSpeed');  S.Rot = col('RotorSpeed');
S.Cp = col('RtAeroCp');  S.P = col('RtAeroPwr');
it = col('Iterations');  er = col('AvgError');
fin = isfinite(S.Pitch) & isfinite(S.TSR) & isfinite(S.V) & isfinite(S.Rot) & isfinite(S.Cp) & isfinite(S.P);
S.conv = fin & it < maxit & er <= toler;
end

function s = oui(b)
if b, s = 'SATISFAIT'; else, s = 'ECHEC'; end
end
