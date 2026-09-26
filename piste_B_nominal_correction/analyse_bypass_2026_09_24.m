function analyse_bypass_2026_09_24()
%ANALYSE_BYPASS_2026_09_24  Du brut au tableau publié, en un seul script.
%
%   Maillon « script de calcul » de la règle 2. Toute valeur publiée sort
%   d'ici, jamais d'une lecture à l'œil de la console.
%
%   Produit :
%     1. le tableau LaTeX qui remplace tab:predict_bypass ;
%     2. le tableau par répétition, tab:predict_bypass_par_repetition ;
%     3. results/<CID>_registre.csv : UNE ligne par nombre affiché dans les
%        deux tableaux, SHA-256 du brut inclus, à vérifier par
%        docs/verifier_chaine.py AVANT tout report dans
%        registre_valeurs_publiees.csv.
%
%   Révision du 26/09/2026 — D13, la chaîne n'était pas raccordée :
%     . les formules du registre visaient la seule répétition 1
%       (« med(bras('x_predict_r1').cpu_ms) ») alors que la valeur écrite
%       agrégeait les trois : la formule ne décrivait pas le nombre publié ;
%     . 24 nombres seulement étaient enregistrés sur 66 affichés : quartiles,
%       n_man, facteur et durée n'avaient aucune ligne ;
%     . verifier_chaine.py ne savait pas lire le format RES/meta : 0/24.
%     Désormais CHAQUE nombre du tableau est produit par cellule(), qui écrit
%     à la fois le texte affiché et sa ligne de registre ; un nombre ne peut
%     donc pas figurer au tableau sans ligne, ni une ligne sans nombre. La
%     formule décrit exactement la statistique : médiane des médianes par
%     répétition, quartiles sur l'ensemble des pas. La valeur enregistrée est
%     le TEXTE affiché, et la tolérance est la demi-unité de sa dernière
%     décimale : le vérificateur contrôle donc que le nombre imprimé est
%     l'arrondi exact de la valeur recalculée, pas seulement « à 0,5 % près ».
%     La statistique elle-même N'EST PAS modifiée : elle a été figée avant
%     l'exécution (commit 200fe22), la changer maintenant serait un choix
%     fait après avoir vu les résultats.
%     Ajouts : tableau par répétition (règle de la fiche pour le LSTM, utile
%     pour tous), avec les échecs du solveur (ExitFlag < 0) par bras ;
%     l'analyse refuse de tourner sur du code non commité ; une répétition
%     manquante est une erreur, plus un saut silencieux.
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
BUDGET = meta.budget_ms;
assert(reps == numel(meta.seed), 'n_repetitions (%d) != nombre de graines (%d)', ...
       reps, numel(meta.seed));

% ---------- l'analyse elle-même doit être du code commité ------------------
% Une valeur publiée dépend du code qui l'a calculée autant que du brut.
[sale, detail_sale] = etat_proprete_code(ROOT);
if sale
    error('analyse:code_sale', ['Le perimetre de code n''est pas propre :\n%s\n' ...
        'Commiter avant d''analyser : une valeur publiee doit venir d''un ' ...
        'code identifie.'], detail_sale);
end
[~, sha_analyse] = system(['git -C "' ROOT '" rev-parse HEAD']); sha_analyse = strtrim(sha_analyse);

REG = {};      % lignes de registre ; ne sont remplies QUE par cellule()

% ========================================================================
% 1. TABLEAU PRINCIPAL
% ========================================================================
fprintf('\n%% ---- tableau de remplacement de tab:predict_bypass ----\n');
fprintf('%% campagne %s | code execute %s | analyse %s | MATLAB %s | brut sha256 %s\n', ...
    CID, court(meta.code_sha1), court(sha_analyse), meta.matlab_release, sha(1:16));
fprintf(['%% med. = MEDIANE DES %d MEDIANES par repetition ; [Q1, Q3] = quartiles ' ...
         'sur l''ensemble des n pas (pct7).\n'], reps);
fprintf('%% Avec %d repetitions, la mediane des medianes est celle de la repetition du milieu.\n', reps);
fprintf('\\begin{tabular}{lcccccccc}\n\\toprule\n');
fprintf(['Substitut & $n_{\\text{pred}}$ & $n_{\\text{man}}$ & ' ...
         'med. \\texttt{predict()} (ms) & med. manuel (ms) & ' ...
         'facteur & depass. manuel & duree \\\\\n\\midrule\n']);
T = 'tab:predict_bypass';
for i = 1:numel(ARCHS)
    a = ARCHS{i}; nom = NOMS{i};
    Bp = arrayfun(@(r) bras_f(a,'predict',r), 1:reps, 'UniformOutput', false);
    Bm = arrayfun(@(r) bras_f(a,'manual', r), 1:reps, 'UniformOutput', false);
    Cp = vecteurs(RES, a, 'predict', reps);
    Cm = vecteurs(RES, a, 'manual',  reps);

    mp = median(cellfun(@median, Cp));  mm = median(cellfun(@median, Cm));
    tp = vertcat(Cp{:});                tm = vertcat(Cm{:});

    ids = @(col) sprintf('%s-%s-%s', CID, a, col);
    [s_np,  REG] = cellule(REG, ids('n_predict'), T, nom, 'n_predict', numel(tp), -1, ...
                           sprintf('n(%s)', cat_f(Bp)), CID, brut_rel, sha);
    [s_nm,  REG] = cellule(REG, ids('n_manuel'), T, nom, 'n_manuel', numel(tm), -1, ...
                           sprintf('n(%s)', cat_f(Bm)), CID, brut_rel, sha);
    [s_mp,  REG] = cellule(REG, ids('med_predict'), T, nom, 'med_predict_ms', mp, 1, ...
                           medmed_f(Bp), CID, brut_rel, sha);
    [s_q1p, REG] = cellule(REG, ids('q1_predict'), T, nom, 'q1_predict_ms', pct7(tp,0.25), 1, ...
                           sprintf('q(%s, 0.25)', cat_f(Bp)), CID, brut_rel, sha);
    [s_q3p, REG] = cellule(REG, ids('q3_predict'), T, nom, 'q3_predict_ms', pct7(tp,0.75), 1, ...
                           sprintf('q(%s, 0.75)', cat_f(Bp)), CID, brut_rel, sha);
    [s_mm,  REG] = cellule(REG, ids('med_manuel'), T, nom, 'med_manuel_ms', mm, 2, ...
                           medmed_f(Bm), CID, brut_rel, sha);
    [s_q1m, REG] = cellule(REG, ids('q1_manuel'), T, nom, 'q1_manuel_ms', pct7(tm,0.25), 2, ...
                           sprintf('q(%s, 0.25)', cat_f(Bm)), CID, brut_rel, sha);
    [s_q3m, REG] = cellule(REG, ids('q3_manuel'), T, nom, 'q3_manuel_ms', pct7(tm,0.75), 2, ...
                           sprintf('q(%s, 0.75)', cat_f(Bm)), CID, brut_rel, sha);
    [s_fac, REG] = cellule(REG, ids('facteur'), T, nom, 'facteur', mp/mm, 1, ...
                           sprintf('%s / %s', medmed_f(Bp), medmed_f(Bm)), CID, brut_rel, sha);
    [s_dep, REG] = cellule(REG, ids('depass_manuel'), T, nom, 'depassements_manuel', ...
                           sum(tm > BUDGET), -1, ...
                           sprintf('nb_sup(%s, %d)', cat_f(Bm), BUDGET), CID, brut_rel, sha);
    Wall = strrep([Bp, Bm], '.cpu_ms', '.wall_s');   % bras('x_mode_rK').wall_s
    [s_dur, REG] = cellule(REG, ids('duree'), T, nom, 'duree_s', duree_totale(RES, a, reps), 0, ...
                           strjoin(Wall, ' + '), CID, brut_rel, sha);

    fprintf('%s & %s & %s & %s [%s, %s] & %s [%s, %s] & $%s\\times$ & %s/%s & %s s \\\\\n', ...
        nom, s_np, s_nm, s_mp, s_q1p, s_q3p, s_mm, s_q1m, s_q3m, s_fac, s_dep, s_nm, s_dur);
end
fprintf('\\bottomrule\n\\end{tabular}\n');
fprintf(['\n%% NOTE OBLIGATOIRE — le LSTM est mesure sur %d pas par ' ...
         'repetition, les cinq autres sur %d.\n'], ...
         meta.sample_size_lstm, meta.sample_size_default);
fprintf(['%% Son facteur n''est pas directement comparable ; il est ' ...
         'rapporte comme mesure separee, repetition par repetition (tableau suivant).\n']);

% ========================================================================
% 2. TABLEAU PAR REPETITION
% ========================================================================
T2 = 'tab:predict_bypass_par_repetition';
fprintf('\n%% ---- tableau par repetition : %s ----\n', T2);
fprintf('\\begin{tabular}{llccccccc}\n\\toprule\n');
fprintf(['Substitut & rep. (graine) & $n_{\\text{pred}}$ & $n_{\\text{man}}$ & ' ...
         'med. \\texttt{predict()} (ms) & med. manuel (ms) & facteur & ' ...
         'depass. manuel & ExitFlag$<0$ pred. / man. \\\\\n\\midrule\n']);
for i = 1:numel(ARCHS)
    a = ARCHS{i}; nom = NOMS{i};
    for r = 1:reps
        bp = bras_f(a,'predict',r); bm = bras_f(a,'manual',r);
        Xp = RES.(sprintf('%s_predict_r%d',a,r));  Xm = RES.(sprintf('%s_manual_r%d',a,r));
        lab = sprintf('%s r%d', nom, r);
        ids = @(col) sprintf('%s-%s-r%d-%s', CID, a, r, col);
        [s_np, REG] = cellule(REG, ids('n_predict'), T2, lab, 'n_predict', numel(Xp.cpu_ms), -1, ...
                              sprintf('n(%s)', bp), CID, brut_rel, sha);
        [s_nm, REG] = cellule(REG, ids('n_manuel'), T2, lab, 'n_manuel', numel(Xm.cpu_ms), -1, ...
                              sprintf('n(%s)', bm), CID, brut_rel, sha);
        [s_mp, REG] = cellule(REG, ids('med_predict'), T2, lab, 'med_predict_ms', median(Xp.cpu_ms), 1, ...
                              sprintf('med(%s)', bp), CID, brut_rel, sha);
        [s_mm, REG] = cellule(REG, ids('med_manuel'), T2, lab, 'med_manuel_ms', median(Xm.cpu_ms), 2, ...
                              sprintf('med(%s)', bm), CID, brut_rel, sha);
        [s_fc, REG] = cellule(REG, ids('facteur'), T2, lab, 'facteur', ...
                              median(Xp.cpu_ms)/median(Xm.cpu_ms), 1, ...
                              sprintf('med(%s) / med(%s)', bp, bm), CID, brut_rel, sha);
        [s_dp, REG] = cellule(REG, ids('depass_manuel'), T2, lab, 'depassements_manuel', ...
                              sum(Xm.cpu_ms > BUDGET), -1, ...
                              sprintf('nb_sup(%s, %d)', bm, BUDGET), CID, brut_rel, sha);
        efp = strrep(bp, '.cpu_ms', '.exitflag'); efm = strrep(bm, '.cpu_ms', '.exitflag');
        [s_ep, REG] = cellule(REG, ids('exitflag_neg_predict'), T2, lab, 'exitflag_neg_predict', ...
                              sum(Xp.exitflag < 0), -1, sprintf('nb_inf(%s, 0)', efp), CID, brut_rel, sha);
        [s_em, REG] = cellule(REG, ids('exitflag_neg_manuel'), T2, lab, 'exitflag_neg_manuel', ...
                              sum(Xm.exitflag < 0), -1, sprintf('nb_inf(%s, 0)', efm), CID, brut_rel, sha);
        fprintf('%s & r%d (%d) & %s & %s & %s & %s & $%s\\times$ & %s/%s & %s / %s \\\\\n', ...
            nom, r, meta.seed(r), s_np, s_nm, s_mp, s_mm, s_fc, s_dp, s_nm, s_ep, s_em);
    end
    if i < numel(ARCHS), fprintf('\\midrule\n'); end
end
fprintf('\\bottomrule\n\\end{tabular}\n');

% ========================================================================
% 3. REGISTRE
% ========================================================================
ids_tous = cellfun(@(s) strtok(s, ';'), REG, 'UniformOutput', false);
assert(numel(unique(ids_tous)) == numel(ids_tous), 'identifiants de registre en double');

fr = fullfile(ROOT, 'results', [CID '_registre.csv']);
fid = fopen(fr, 'w');
fprintf(fid, ['id;manuscrit;tableau;ligne;colonne;valeur_publiee;tolerance;' ...
              'campagne;fichier_brut;sha256_brut;calcul\n']);
for i = 1:numel(REG), fprintf(fid, '%s\n', REG{i}); end
fclose(fid);

% ---- D5 : chaque ligne relue a bien 11 champs et le bon SHA ---------------
v = fopen(fr, 'r'); k = 0;
while true
    ln = fgetl(v);
    if ~ischar(ln), break; end
    k = k + 1;
    if k == 1, continue; end
    ch = strsplit(ln, ';');
    assert(numel(ch) == 11, 'ligne %d du registre : %d champs au lieu de 11', k, numel(ch));
    assert(strcmp(ch{10}, sha), 'ligne %d du registre : SHA absent ou different', k);
end
fclose(v);
assert(k - 1 == numel(REG), 'relu %d lignes, %d ecrites', k - 1, numel(REG));

fprintf(['\n%d lignes de registre ecrites dans %s\n' ...
         '  une par nombre affiche dans les deux tableaux (diagnostic, non critere),\n' ...
         '  11 champs par ligne, SHA-256 verifie sur chacune.\n'], numel(REG), fr);
fprintf(['ETAPE SUIVANTE — verifier, AVANT tout report :\n' ...
         '  python docs/verifier_chaine.py --registre results/%s_registre.csv --racine .\n' ...
         'Ne reporter dans registre_valeurs_publiees.csv qu''au moment ou le tableau ' ...
         'entre dans le manuscrit.\n'], CID);
end


% =========================================================================
function [txt, REG] = cellule(REG, id, tableau, ligne, colonne, v, nd, calcul, ...
                              campagne, brut, sha)
%CELLULE  Seule porte d'entree d'un nombre dans un tableau publie (D13).
%   Renvoie le TEXTE affiche et ajoute la ligne de registre correspondante.
%   nd = nombre de decimales ; nd < 0 : entier, tolerance nulle.
%   Pour un reel, la tolerance relative est la demi-unite de la derniere
%   decimale affichee : le verificateur controle alors que le texte imprime
%   est l'arrondi exact de la valeur recalculee depuis le brut.
assert(isscalar(v) && isfinite(v), 'cellule %s : valeur non finie', id);
if nd < 0
    assert(v == round(v), 'cellule %s : entier attendu, %g obtenu', id, v);
    txt = sprintf('%d', round(v));
    tol = '0.0';
else
    txt = sprintf('%.*f', nd, v);
    pub = str2double(txt);
    assert(pub ~= 0, 'cellule %s : %g s''arrondit a zero avec %d decimale(s)', id, v, nd);
    tol = sprintf('%.6g', 0.5 * 10^(-nd) / abs(pub) * 1.001);
end
champs = {id, 'P2', tableau, ligne, colonne, txt, tol, campagne, brut, sha, calcul};
for i = 1:numel(champs)
    assert(~contains(champs{i}, ';'), ...
        'champ %d contient un point-virgule, il casserait le CSV : %s', i, champs{i});
end
REG{end+1} = strjoin(champs, ';');
end


function s = bras_f(arch, mode, r)
s = sprintf('bras(''%s_%s_r%d'').cpu_ms', arch, mode, r);
end

function s = cat_f(B)
s = sprintf('cat(%s)', strjoin(B, ', '));
end

function s = medmed_f(B)
s = sprintf('med([%s])', strjoin(cellfun(@(b) sprintf('med(%s)', b), B, ...
    'UniformOutput', false), ', '));
end

function C = vecteurs(RES, arch, mode, reps)
%VECTEURS  Les vecteurs bruts des REPS repetitions. Une repetition absente est
%          une ERREUR : l'ancienne version la sautait en silence.
C = cell(1, reps);
for r = 1:reps
    f = sprintf('%s_%s_r%d', arch, mode, r);
    if ~isfield(RES, f)
        error('analyse:repetition_absente', 'bras absent : %s', f);
    end
    C{r} = RES.(f).cpu_ms(:);
end
end

function d = duree_totale(RES, arch, reps)
d = 0;
for m = {'predict','manual'}
    for r = 1:reps
        f = sprintf('%s_%s_r%d', arch, m{1}, r);
        if ~isfield(RES, f)
            error('analyse:repetition_absente', 'bras absent : %s', f);
        end
        d = d + RES.(f).wall_s;
    end
end
end

function s = court(h)
if isempty(h), s = '(vide)'; else, s = h(1:min(8,numel(h))); end
end
