function analyse_bypass_2026_09_24()
%ANALYSE_BYPASS_2026_09_24  Du brut au tableau publié, en un seul script.
%
%   Maillon « script de calcul » de la règle 2. Toute valeur publiée sort
%   d'ici, jamais d'une lecture à l'œil de la console.
%
%   Produit :
%     1. le tableau LaTeX qui remplace tab:predict_bypass ;
%     2. les lignes de registre, SHA-256 du brut inclus, prêtes à coller
%        dans registre_valeurs_publiees.csv.
%
%   Révision du 23/09/2026 (2e passe) — corrections D2, D3, D4, D5 :
%     . comparaison de version sur le préfixe numérique (D2)
%     . refus explicite d'un lot smoke (D3)
%     . quartiles par pct7, même convention que numpy (D4)
%     . le SHA-256 est un CHAMP CONSTRUIT, plus un remplacement de motif (D5)

HERE = fileparts(mfilename('fullpath'));
ROOT = fileparts(HERE);
addpath(fullfile(ROOT,'common'), HERE);

CID  = 'P2-BYPASS-2026-09-24-a';
FRES = fullfile(ROOT, 'results', [CID '.mat']);
assert(isfile(FRES), 'brut absent : %s — lancer run_bypass_2026_09_24', FRES);

verifier_lot_campagne(FRES);     % six conditions, bloquantes, AVANT tout calcul
Z = load(FRES); meta = Z.meta; RES = Z.RES;

% ---------- contrôles de conformité à la fiche ---------------------------
assert(~isfield(meta,'smoke') || ~meta.smoke, ...            % D3
    'analyse:smoke', 'Fichier de SMOKE TEST : interdit pour publication.');
assert(~meta.code_dirty, 'meta.code_dirty = true : campagne non publiable');
assert(meta.is_continuous_time == false, 'IsContinuousTime != false');
assert(meta.MaxIterations == 30 && meta.MaxFunctionEvaluations == 300, ...
    'reglages solveur differents de la fiche');

% D2 — version() renvoie « 24.1.0.2537033 (R2024a) » : comparer le prefixe.
VERSION_FICHE = '24.1.0.2537033';
RELEASE_FICHE = '2024a';
num = regexp(meta.matlab_version, '^\d+(\.\d+)+', 'match', 'once');
assert(strcmp(num, VERSION_FICHE), ...
    'version MATLAB %s (prefixe %s) au lieu de %s (fiche)', ...
    meta.matlab_version, num, VERSION_FICHE);
assert(strcmp(meta.matlab_release, RELEASE_FICHE), ...
    'release MATLAB %s au lieu de %s (fiche)', meta.matlab_release, RELEASE_FICHE);

% empreinte du brut, produite par la vérification de lot
sha = strtrim(strtok(fileread([FRES '.sha256'])));
assert(numel(sha) == 64, 'empreinte du brut illisible dans %s.sha256', FRES);
brut_rel = ['results/' CID '.mat'];

ARCHS = {'mlpres','gpres','swmlp','pinn','tcn','lstm'};
NOMS  = {'MLP-residuel','GP-residuel','SW-MLP','PINN-v2','TCN','LSTM'};
reps  = meta.n_repetitions;

fprintf('\n%% ---- tableau de remplacement de tab:predict_bypass ----\n');
fprintf('%% campagne %s | commit %s | MATLAB %s | brut sha256 %s\n', ...
    CID, meta.code_sha1(1:min(8,end)), meta.matlab_release, sha(1:16));
fprintf('\\begin{tabular}{lccccccc}\n\\toprule\n');
fprintf(['Substitut & $n_{\\text{pred}}$ & $n_{\\text{man}}$ & ' ...
         'med. \\texttt{predict()} (ms) & med. manuel (ms) & ' ...
         'facteur & depass. manuel & duree \\\\\n\\midrule\n']);

L = {};   % lignes de registre, construites champ par champ
for i = 1:numel(ARCHS)
    a = ARCHS{i};
    [mp, q1p, q3p, np_, ~]  = agrege(RES, a, 'predict', reps);
    [mm, q1m, q3m, nm, ovm] = agrege(RES, a, 'manual',  reps);
    if isnan(mp) || isnan(mm), continue; end
    fac = mp / mm;                       % MEME statistique aux deux bras
    duree = duree_totale(RES, a, reps);

    fprintf(['%s & %d & %d & %.1f [%.1f, %.1f] & %.2f [%.2f, %.2f] & ' ...
             '$%.1f\\times$ & %d/%d & %.0f s \\\\\n'], ...
        NOMS{i}, np_, nm, mp, q1p, q3p, mm, q1m, q3m, fac, ovm, nm, duree);

    % ---- D5 : le SHA est un CHAMP, pas un motif a remplacer ------------
    L{end+1} = ligne_registre(sprintf('%s-%s-medpredict', CID, a), ...
        'tab:predict_bypass', NOMS{i}, 'med_predict_ms', sprintf('%.4f', mp), ...
        '0.005', CID, brut_rel, sha, ...
        sprintf('med(bras(''%s_predict_r1'').cpu_ms)', a)); %#ok<AGROW>
    L{end+1} = ligne_registre(sprintf('%s-%s-medmanuel', CID, a), ...
        'tab:predict_bypass', NOMS{i}, 'med_manuel_ms', sprintf('%.4f', mm), ...
        '0.005', CID, brut_rel, sha, ...
        sprintf('med(bras(''%s_manual_r1'').cpu_ms)', a)); %#ok<AGROW>
    L{end+1} = ligne_registre(sprintf('%s-%s-npred', CID, a), ...
        'tab:predict_bypass', NOMS{i}, 'n_predict', sprintf('%d', np_), ...
        '0.0', CID, brut_rel, sha, ...
        sprintf('n(bras(''%s_predict_r1'').cpu_ms)', a)); %#ok<AGROW>
    L{end+1} = ligne_registre(sprintf('%s-%s-depassmanuel', CID, a), ...
        'tab:predict_bypass', NOMS{i}, 'depassements_manuel', sprintf('%d', ovm), ...
        '0.0', CID, brut_rel, sha, ...
        sprintf('nb_sup(bras(''%s_manual_r1'').cpu_ms, %d)', a, meta.budget_ms)); %#ok<AGROW>
end
fprintf('\\bottomrule\n\\end{tabular}\n');

fprintf(['\n%% NOTE OBLIGATOIRE — le LSTM est mesure sur %d pas par ' ...
         'repetition, les cinq autres sur %d.\n'], ...
         meta.sample_size_lstm, meta.sample_size_default);
fprintf(['%% Son facteur n''est pas directement comparable ; il est ' ...
         'rapporte comme mesure separee.\n']);

% ---------- ecriture du registre -----------------------------------------
fr = fullfile(ROOT, 'results', [CID '_registre.csv']);
fid = fopen(fr, 'w');
fprintf(fid, ['id;manuscrit;tableau;ligne;colonne;valeur_publiee;tolerance;' ...
              'campagne;fichier_brut;sha256_brut;calcul\n']);
for i = 1:numel(L), fprintf(fid, '%s\n', L{i}); end
fclose(fid);

% ---- D5 : verification que chaque ligne a bien 11 champs et le bon SHA --
v = fopen(fr, 'r'); k = 0;
while true
    ln = fgetl(v);
    if ~ischar(ln), break; end
    k = k + 1;
    if k == 1, continue; end
    ch = strsplit(ln, ';');
    assert(numel(ch) == 11, ...
        'ligne %d du registre : %d champs au lieu de 11', k, numel(ch));
    assert(strcmp(ch{10}, sha), ...
        'ligne %d du registre : SHA absent ou different', k);
end
fclose(v);
fprintf('\n%d lignes de registre ecrites dans %s\n', numel(L), fr);
fprintf('  11 champs par ligne, SHA-256 verifie sur chacune.\n');
fprintf('Les coller dans registre_valeurs_publiees.csv, puis verifier_chaine.py\n');
end


% =========================================================================
function s = ligne_registre(id, tableau, ligne, colonne, valeur, tol, ...
                            campagne, brut, sha, calcul)
champs = {id, 'P2', tableau, ligne, colonne, valeur, tol, campagne, brut, sha, calcul};
for i = 1:numel(champs)
    assert(~contains(champs{i}, ';'), ...
        'champ %d contient un point-virgule, il casserait le CSV : %s', i, champs{i});
end
s = strjoin(champs, ';');
end


function [med, q1, q3, n, ovr] = agrege(RES, arch, mode, reps)
%AGREGE  Mediane des medianes par repetition ; quartiles sur l'ensemble des
%        pas ; n et depassements cumules. Quartiles par pct7 (cf. D4).
meds = []; n = 0; ovr = 0; tous = [];
for r = 1:reps
    f = sprintf('%s_%s_r%d', arch, mode, r);
    if ~isfield(RES, f), continue; end
    c = RES.(f).cpu_ms;
    meds(end+1) = median(c); %#ok<AGROW>
    tous = [tous; c(:)];     %#ok<AGROW>
    n = n + numel(c); ovr = ovr + RES.(f).n_overruns;
end
if isempty(meds), med=NaN; q1=NaN; q3=NaN; return; end
med = median(meds);
q1 = pct7(tous, 0.25); q3 = pct7(tous, 0.75);
end


function d = duree_totale(RES, arch, reps)
d = 0;
for m = {'predict','manual'}
    for r = 1:reps
        f = sprintf('%s_%s_r%d', arch, m{1}, r);
        if isfield(RES, f), d = d + RES.(f).wall_s; end
    end
end
end
