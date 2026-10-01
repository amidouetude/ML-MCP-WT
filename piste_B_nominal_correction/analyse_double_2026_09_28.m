function A = analyse_double_2026_09_28()
%ANALYSE_DOUBLE_2026_09_28  Analyse pré-enregistrée de P2-DOUBLE-2026-09-28-a.
%
%   A = analyse_double_2026_09_28()
%
%   Applique, sans rien y ajouter, l'analyse figée dans la fiche
%   docs/campagnes/P2-DOUBLE-2026-09-28-a.yaml (commit 8cb0555), sections A,
%   B et C. Écrit après la campagne, commité AVANT sa première exécution.
%
%   ORDRE IMPOSÉ PAR LA FICHE
%     A. Reproductibilité. Bras par bras, vecteur par vecteur (exitflag,
%        u_hist, omega_hist) : même classe, même taille (orientation
%        comprise), mêmes octets (typecast(x(:),'uint8')), contre le bras de
%        MÊME NOM du 24/09. Aucune tolérance. isequaln est rapporté en
%        diagnostic et ne décide pas. Bras contrôlés : swmlp_predict_r1,
%        tcn_predict_r1, gpres_predict_r1..r3 et les 12 bras manual.
%        Le verdict est ENREGISTRÉ avant que la section B ne soit abordée.
%     B. Seulement si A = REPRODUCTIBLE. Pour chaque architecture et chaque
%        répétition k : n_inf = nombre de pas avec exitflag < 0, recompté sur
%        le VECTEUR brut (et non lu dans le champ agrégé) ;
%          D_k = n_inf_simple_k - n_inf_manuel_k
%          D_k > 0 -> G_k = (n_inf_simple_k - n_inf_double_k) / D_k
%          D_k = 0 -> G_k non défini, répétition NON DISCRIMINANTE
%          D_k < 0 -> ANOMALIE DE COMPARAISON
%        n_inf_simple_k vient du brut du 24/09 (<arch>_predict_rk), les deux
%        autres de cette campagne. Verdict par architecture, premier cas
%        applicable : ANOMALIE DE COMPARAISON, NON DISCRIMINANT, PRECISION
%        SUFFISANTE (G_k >= 0.9 pour les 3), PRECISION SANS EFFET (G_k <= 0.1
%        pour les 3), EFFET PARTIEL.
%     C. Descriptif, sans verdict : trajectoires double / manuel (max|Δu|,
%        max|Δω|, égalité des vecteurs exitflag) ; temps du pas de commande
%        complet (médiane, Q1, Q3 par pct7, facteur med(double)/med(manuel),
%        dépassements n/N avec cpu_ms > 100 strictement) ; classe de sortie.
%
%   RÈGLE D'INTERPRÉTATION DES TEMPS (fiche) : le facteur double/manuel n'est
%   présentable comme surcoût lié à predict() que pour une architecture au
%   verdict PRECISION SUFFISANTE, sous la forme « temps du pas de commande
%   avec réseau converti en double, comparé à l'implémentation manuelle ».
%   Ce script calcule le facteur pour toutes ; il ne l'interprète pour
%   aucune.
%
%   Aucun fichier brut n'est modifié. Sortie : results/analyse_double_2026-09-28.mat

HERE = fileparts(mfilename('fullpath'));
ROOT = fileparts(HERE);
addpath(fullfile(ROOT,'common'), HERE);

CID     = 'P2-DOUBLE-2026-09-28-a';
CID_REF = 'P2-BYPASS-2026-09-24-a';
SHA_REF = '8fb2962c942937860b5d20680583dc4843caddd71e7730f34970a2e57047bd4e';
SEUIL_SUFF = 0.9; SEUIL_SANS = 0.1; BUDGET_MS = 100;
ARCHS = {'swmlp','pinn','tcn','lstm'};
NOMS  = {'SW-MLP','PINN-v2','TCN','LSTM'};

% ---------- garde-fous -----------------------------------------------------
[sale, detail] = etat_proprete_code(ROOT);
if sale, error('analyse:code_sale', 'Perimetre de code non propre :\n%s', detail); end
[~, sha_ana] = system(['git -C "' ROOT '" rev-parse HEAD']); sha_ana = strtrim(sha_ana);

F    = fullfile(ROOT, 'results', [CID '.mat']);
FREF = fullfile(ROOT, 'results', [CID_REF '.mat']);
assert(isfile([F '.sha256']), 'analyse:lot', ...
    'pas de %s.sha256 : le lot n''a pas ete accepte par verifier_lot_campagne', CID);
sha_brut = strtrim(strtok(fileread([F '.sha256'])));
assert(strcmp(sha256_fichier(F), sha_brut), 'analyse:brut', 'empreinte du brut differente de son .sha256');
assert(strcmp(sha256_fichier(FREF), SHA_REF), 'analyse:ref', 'empreinte du brut de reference differente');

Z = load(F);    meta = Z.meta; RES = Z.RES;
Y = load(FREF); RREF = Y.RES;
assert(~meta.smoke, 'analyse:smoke', 'lot de smoke test : jamais analyse');
assert(strcmp(meta.campaign_id, CID), 'analyse:cid', 'campaign_id inattendu');
assert(meta.expected_arms == 29 && numel(fieldnames(RES)) == 29, 'analyse:bras', '29 bras attendus');

fprintf('\n=== ANALYSE %s — analyse %s | brut %s | code %s | reference %s ===\n', ...
    CID, court(sha_ana), sha_brut(1:16), court(meta.code_sha1), SHA_REF(1:16));

% =========================================================================
% A. REPRODUCTIBILITE
% =========================================================================
CONTROLES = [{'swmlp_predict_r1','tcn_predict_r1'}, ...
             arrayfun(@(k) sprintf('gpres_predict_r%d',k), 1:3, 'UniformOutput', false)];
for a = ARCHS
    for k = 1:3, CONTROLES{end+1} = sprintf('%s_manual_r%d', a{1}, k); end %#ok<AGROW>
end
VECT = {'exitflag','u_hist','omega_hist'};
rep = struct('bras',{},'vecteur',{},'meme_classe',{},'meme_taille',{},'memes_octets',{}, ...
             'isequaln',{},'ecart_max',{},'egal',{});
for i = 1:numel(CONTROLES)
    b = CONTROLES{i};
    assert(isfield(RES, b) && isfield(RREF, b), 'analyse:controle', 'bras controle absent : %s', b);
    for v = VECT
        x = RES.(b).(v{1}); y = RREF.(b).(v{1});
        mc = strcmp(class(x), class(y));
        mt = isequal(size(x), size(y));
        mo = mc && mt && isequal(octets(x), octets(y));
        en = isequaln(x, y);
        em = NaN; if mt && isnumeric(x) && isnumeric(y), em = max(abs(double(x(:)) - double(y(:)))); end
        rep(end+1) = struct('bras',b,'vecteur',v{1},'meme_classe',mc,'meme_taille',mt, ...
            'memes_octets',mo,'isequaln',en,'ecart_max',em,'egal',mo); %#ok<AGROW>
    end
end
reproductible = all([rep.egal]);
verdict_A = ternaire(reproductible, 'REPRODUCTIBLE', 'NON REPRODUCTIBLE');

fprintf('\nA. REPRODUCTIBILITE — %d bras x %d vecteurs, egalite octet par octet\n', ...
    numel(CONTROLES), numel(VECT));
for i = 1:numel(CONTROLES)
    s = rep(strcmp({rep.bras}, CONTROLES{i}));
    fprintf('   %-18s %s\n', CONTROLES{i}, strjoin(arrayfun(@(t) sprintf('%s:%s', t.vecteur, ...
        ternaire(t.egal, 'identique', sprintf('DIFFERENT (classe %d, taille %d, isequaln %d, ecart %.3g)', ...
        t.meme_classe, t.meme_taille, t.isequaln, t.ecart_max))), s, 'UniformOutput', false), '  '));
end
fprintf('   -> %s\n', verdict_A);
A = struct();
A.reproductibilite = struct('verdict', verdict_A, 'detail', rep, 'bras_controles', {CONTROLES});

% =========================================================================
% B. CRITERE PRINCIPAL — seulement si A = REPRODUCTIBLE
% =========================================================================
B = struct();
if ~reproductible
    fprintf(['\nB. NON CALCULE : reproductibilite echouee, toute comparaison ' ...
             'double / simple est interdite (fiche, section A).\n']);
    A.critere_principal = 'NON CALCULE — reproductibilite echouee';
else
    fprintf('\nB. CRITERE PRINCIPAL — G_k = (n_simple - n_double) / (n_simple - n_manuel)\n');
    fprintf('   %-8s %-4s %8s %8s %8s %6s %8s  %s\n', 'arch', 'rep', 'simple', 'double', 'manuel', 'D_k', 'G_k', 'statut');
    for ia = 1:numel(ARCHS)
        a = ARCHS{ia}; n_s = zeros(1,3); n_d = n_s; n_m = n_s; D = n_s; G = nan(1,3); st = cell(1,3);
        for k = 1:3
            n_s(k) = sum(RREF.(sprintf('%s_predict_r%d', a, k)).exitflag < 0);
            n_d(k) = sum(RES.(sprintf('%s_double_r%d',  a, k)).exitflag < 0);
            n_m(k) = sum(RES.(sprintf('%s_manual_r%d',  a, k)).exitflag < 0);
            D(k) = n_s(k) - n_m(k);
            if D(k) > 0
                G(k) = (n_s(k) - n_d(k)) / D(k); st{k} = 'G defini';
            elseif D(k) == 0
                st{k} = 'NON DISCRIMINANTE';
            else
                st{k} = 'ANOMALIE';
            end
            fprintf('   %-8s r%-3d %8d %8d %8d %6d %8s  %s\n', NOMS{ia}, k, n_s(k), n_d(k), n_m(k), ...
                D(k), ternaire(isnan(G(k)), '-', sprintf('%.3f', G(k))), st{k});
        end
        if any(D < 0),                     v = 'ANOMALIE DE COMPARAISON';
        elseif any(D == 0),                v = 'NON DISCRIMINANT';
        elseif all(G >= SEUIL_SUFF),       v = 'PRECISION SUFFISANTE';
        elseif all(G <= SEUIL_SANS),       v = 'PRECISION SANS EFFET';
        else,                              v = 'EFFET PARTIEL';
        end
        fprintf('   %-8s -> %s\n', NOMS{ia}, v);
        B.(a) = struct('n_inf_simple_ref', n_s, 'n_inf_double', n_d, 'n_inf_manuel', n_m, ...
            'D', D, 'G', G, 'statut_rep', {st}, 'verdict', v, ...
            'n_pas', numel(RES.(sprintf('%s_double_r1', a)).exitflag));
    end
    A.critere_principal = B;
end

% =========================================================================
% C. DESCRIPTIF — sans verdict
% =========================================================================
fprintf('\nC. DESCRIPTIF (pas de commande complet ; aucun verdict)\n');
fprintf('   %-8s %-3s %-7s | %9s [%8s %9s] | %9s [%7s %7s] | %8s | %7s %7s | %6s %6s | %s\n', ...
    'arch','rep','classe','med dbl','Q1','Q3','med man','Q1','Q3','facteur','dep dbl','dep man', ...
    'max|du|','max|dw|','exitflag');
C = struct();
for ia = 1:numel(ARCHS)
    a = ARCHS{ia}; L = struct([]);
    for k = 1:3
        d = RES.(sprintf('%s_double_r%d', a, k)); m = RES.(sprintf('%s_manual_r%d', a, k));
        t = struct('rep', k, 'classe_double', d.classe_sortie, 'classe_manuel', m.classe_sortie, ...
            'med_double', median(d.cpu_ms), 'q1_double', pct7(d.cpu_ms,0.25), 'q3_double', pct7(d.cpu_ms,0.75), ...
            'med_manuel', median(m.cpu_ms), 'q1_manuel', pct7(m.cpu_ms,0.25), 'q3_manuel', pct7(m.cpu_ms,0.75), ...
            'facteur', median(d.cpu_ms) / median(m.cpu_ms), ...
            'dep_double', sum(d.cpu_ms > BUDGET_MS), 'dep_manuel', sum(m.cpu_ms > BUDGET_MS), ...
            'N', numel(d.cpu_ms), ...
            'max_du', max(abs(d.u_hist(:) - m.u_hist(:))), ...
            'max_domega', max(abs(d.omega_hist(:) - m.omega_hist(:))), ...
            'exitflag_identiques', isequal(d.exitflag, m.exitflag));
        L = [L, t]; %#ok<AGROW>
        fprintf('   %-8s r%-2d %-7s | %9.2f [%8.2f %9.2f] | %9.2f [%7.2f %7.2f] | %8.1f | %3d/%-3d %3d/%-3d | %6.3g %6.3g | %s\n', ...
            NOMS{ia}, k, t.classe_double, t.med_double, t.q1_double, t.q3_double, ...
            t.med_manuel, t.q1_manuel, t.q3_manuel, t.facteur, t.dep_double, t.N, t.dep_manuel, t.N, ...
            t.max_du, t.max_domega, ternaire(t.exitflag_identiques, 'identiques', 'differents'));
    end
    C.(a) = L;
end
A.descriptif = C;

A.provenance = struct('campagne', CID, 'brut_sha256', sha_brut, 'code_campagne', meta.code_sha1, ...
    'fiche_commit', meta.fiche_commit, 'commit_analyse', sha_ana, ...
    'reference', CID_REF, 'reference_sha256', SHA_REF, ...
    'matlab', version, 'date', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
A.protocole = struct('SEUIL_SUFFISANTE', SEUIL_SUFF, 'SEUIL_SANS_EFFET', SEUIL_SANS, ...
    'BUDGET_MS', BUDGET_MS, 'egalite', 'classe + taille + octets (typecast uint8), sans tolerance');
fo = fullfile(ROOT, 'results', 'analyse_double_2026-09-28.mat');
save(fo, 'A');
fprintf('\nresultats : %s\nsha256 : %s\n', fo, sha256_fichier(fo));
end


% =========================================================================
function o = octets(x)
%OCTETS  Représentation binaire d'un tableau numérique ou logique, colonne.
if islogical(x), x = uint8(x); end
o = typecast(x(:), 'uint8');
end

function s = ternaire(c, a, b)
if c, s = a; else, s = b; end
end

function s = court(h)
if isempty(h), s = '(vide)'; else, s = h(1:min(8,numel(h))); end
end
