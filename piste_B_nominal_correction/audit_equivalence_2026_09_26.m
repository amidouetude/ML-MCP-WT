function R = audit_equivalence_2026_09_26()
%AUDIT_EQUIVALENCE_2026_09_26  Les fonctions d'etat « predict » et « manuel »
%   resolvent-elles le MEME probleme d'optimisation ?
%
%   R = audit_equivalence_2026_09_26()
%
%   QUESTION
%     La campagne P2-BYPASS-2026-09-24-a mesure le cout du pas de commande
%     quand le substitut est evalue par predict() ou par une implementation
%     manuelle. Pour SW-MLP, PINN-v2, TCN et LSTM, le solveur echoue beaucoup
%     plus souvent en predict (PINN : 598/600 contre 0/600). Le facteur ne
%     mesure le seul surcout de predict() que si les deux fonctions d'etat
%     sont equivalentes pour le solveur : memes SORTIES, et memes DERIVEES
%     telles que nlmpc les calcule.
%
%   UNITE COMPAREE : la fonction d'etat entiere, telle que nlmpc l'appelle
%     (mise en forme, normalisation, modele, denormalisation, et pour les
%     residuels le modele nominal wt_step), jamais le seul reseau.
%
%   DERIVEES : EXACTEMENT celles de nlmpc. En R2024a, nlmpc calcule la
%     jacobienne d'etat par mpc.internal.nlmpc.computeJacobianState :
%     differences AVANT, pas dv = 1e-6 * max(|z_j|, 1) (source lue le 26/09,
%     toolbox/mpc/mpcutils/+mpc/+internal/+nlmpc/computeJacobianState.m,
%     lignes 17-40). L'audit appelle CETTE fonction, il ne la reimplemente
%     pas. Reference : differences CENTREES sur la fonction manuelle
%     (double), pas 1e-5 * max(|z_j|, 1).
%
%   POINTS D'EVALUATION, chacun avec son origine
%     brut_reconstruit : pour chaque architecture, 10 pas regulierement
%       espaces dans CHACUN des 6 bras (predict/manuel x 3 repetitions).
%       L'etat complet x_k (le pitch n'est pas enregistre) et la fenetre de
%       sequence sont RECONSTRUITS en rejouant wt_step avec les commandes
%       enregistrees (u_hist) et le vent recalcule par kaimal_wind (graine
%       du bras). La reconstruction est CONTROLEE : la vitesse reconstruite
%       doit egaler omega_hist a 1e-8 rpm pres, sinon le bras est exclu.
%     grille : pour les modeles sans fenetre (MLP residuel, GP residuel,
%       PINN-v2), grille 3^4 sur [min, max] des points reconstruits.
%
%   PROTOCOLE FIGE AVANT EXECUTION (ce fichier est commite avant de tourner)
%     TOL_OUT   = 1e-5   ecart relatif max des sorties, denominateur
%                        max(|f_manuel|, 1e-3). ~80 eps(single) : admet
%                        l'arrondi d'un calcul en simple precision, rejette
%                        une erreur de structure (axe de normalisation,
%                        ordre des portes), qui donne des ecarts >= 1e-3.
%     TOL_JAC   = 1e-3   ecart relatif de Frobenius d'une jacobienne nlmpc
%                        a la reference. En double, l'erreur attendue des
%                        differences avant a dv = 1e-6 est ~1e-6 ; si la
%                        sortie est en simple precision, l'arrondi
%                        (~1.2e-7 |f|) divise par dv donne ~1e-1. 1e-3
%                        separe les deux regimes d'un facteur 100 ou plus.
%     Un point est NON EVALUABLE si la jacobienne nlmpc de la fonction
%     MANUELLE elle-meme s'ecarte de la reference de plus de TOL_JAC (point
%     anguleux : saturations de wt_step, ReLU) ; il est rapporte, pas juge.
%
%   VERDICTS, dans cet ordre
%     AUDIT NON CONCLUANT                      aucun point reconstruit, ou
%                                              > 20 % de points non evaluables
%     SORTIES DIVERGENTES                      un ecart de sortie > TOL_OUT
%     SORTIES EQUIVALENTES, DERIVEES DIVERGENTES
%                                              sorties conformes, mais la
%                                              jacobienne nlmpc de predict
%                                              s'ecarte de > TOL_JAC sur plus
%                                              de 5 % des points evaluables
%     EQUIVALENCE ETABLIE                      sinon
%
%   CONTROLES
%     positif : le MLP residuel et le GP residuel passent par le MEME code.
%       Leurs SORTIES doivent etre conformes (propriete deja verifiee a la
%       campagne : ecarts 1e-7 et 1e-10). Sinon l'audit est en cause avant
%       les modeles. Leurs derivees sont un RESULTAT, pas un controle.
%     negatif : pour chaque architecture, le modele manuel est perturbe
%       (biais de la derniere couche, ou beta0 du GP, + 0.1 en unites
%       normalisees) sur une COPIE en memoire ; l'audit doit alors rendre
%       des sorties divergentes. Le fichier du modele n'est jamais touche.
%
%   GARDE-FOUS : code du perimetre propre et commite ; empreinte du brut
%   egale au .sha256 de la campagne ; empreinte de chaque modele egale a
%   meta.model_sha256 de la campagne. Sorties : results/audit_equivalence_
%   2026-09-26.mat (hors git, reference par empreinte).

HERE = fileparts(mfilename('fullpath'));
ROOT = fileparts(HERE);
addpath(fullfile(ROOT,'common'), HERE);

CID = 'P2-BYPASS-2026-09-24-a';
TOL_OUT = 1e-5;  TOL_JAC = 1e-3;  H_REF = 1e-5;
FRAC_DIV = 0.05; FRAC_NONEVAL = 0.20;
NEG_DELTA = 0.1; PTS_PAR_BRAS = 10; GRILLE = 3; TOL_RECON_RPM = 1e-8;

% ---------- garde-fous ------------------------------------------------------
[sale, detail] = etat_proprete_code(ROOT);
if sale
    error('audit:code_sale', 'Perimetre de code non propre :\n%s\nCommiter avant.', detail);
end
[~, sha_audit] = system(['git -C "' ROOT '" rev-parse HEAD']); sha_audit = strtrim(sha_audit);

FRES = fullfile(ROOT, 'results', [CID '.mat']);
sha_brut = strtrim(strtok(fileread([FRES '.sha256'])));
assert(strcmp(sha256_fichier(FRES), sha_brut), 'audit:brut', 'empreinte du brut differente du .sha256');
Z = load(FRES); meta = Z.meta; RES = Z.RES;

MOD = meta.model_paths;
for c = fieldnames(MOD)'
    h = sha256_fichier(fullfile(ROOT, MOD.(c{1})));
    assert(strcmp(h, meta.model_sha256.(c{1})), 'audit:modele', ...
        'modele %s : empreinte %s, campagne %s', MOD.(c{1}), h(1:12), meta.model_sha256.(c{1})(1:12));
end
S_res = load(fullfile(ROOT, MOD.res));  S_gp = load(fullfile(ROOT, MOD.gpres));
V2 = load(fullfile(ROOT, MOD.v2));      V1 = load(fullfile(ROOT, MOD.v1));

cfg = stage0_config(); p = get_wt_params(); Ts = cfg.mpc.Ts; p.dt = Ts;
fprintf('\n=== AUDIT D''EQUIVALENCE — code %s | campagne %s (code %s) | brut %s ===\n', ...
    court(sha_audit), CID, court(meta.code_sha1), sha_brut(1:16));
fprintf('TOL_OUT %.0e | TOL_JAC %.0e | pas nlmpc 1e-6 (computeJacobianState) | reference centree %.0e\n\n', ...
    TOL_OUT, TOL_JAC, H_REF);

ARCHS = {'mlpres','gpres','swmlp','pinn','tcn','lstm'};
NOMS  = {'MLP-residuel','GP-residuel','SW-MLP','PINN-v2','TCN','LSTM'};
R = struct();

for ia = 1:numel(ARCHS)
    a = ARCHS{ia};
    [fp, fm, mp, mm, seqlen, kind] = preparer(a, S_res, S_gp, V2, V1);
    mneg = perturber(a, mm, NEG_DELTA);

    % ---- points reconstruits depuis le brut --------------------------------
    P = struct('src',{},'bras',{},'k',{},'x',{},'u',{},'V',{},'B',{});
    recon_ok = true(1,0); recon_err = [];
    for mode = {'predict','manual'}
        for r = 1:meta.n_repetitions
            f = sprintf('%s_%s_r%d', a, mode{1}, r);
            A = RES.(f);
            [pts, err] = reconstruire(A, meta.seed(r), seqlen, cfg, p, Ts);
            recon_err(end+1) = err; %#ok<AGROW>
            if err > TOL_RECON_RPM, recon_ok(end+1) = false; continue; end %#ok<AGROW>
            recon_ok(end+1) = true; %#ok<AGROW>
            idx = unique(round(linspace(1, numel(pts), PTS_PAR_BRAS)));
            for k = idx
                q = pts(k); q.src = 'brut_reconstruit'; q.bras = f; q.k = k;
                P(end+1) = q; %#ok<AGROW>
            end
        end
    end
    % ---- grille, modeles sans fenetre ----------------------------------------
    if any(strcmp(kind, {'residuel','simple'})) && ~isempty(P)
        X = [arrayfun(@(q) q.x(1), P); arrayfun(@(q) q.x(2), P); [P.V]; [P.u]];
        lv = arrayfun(@(i) linspace(min(X(i,:)), max(X(i,:)), GRILLE), 1:4, 'UniformOutput', false);
        [g1,g2,g3,g4] = ndgrid(lv{:});
        for j = 1:numel(g1)
            P(end+1) = struct('src','grille','bras','','k',0,'x',[g1(j);g2(j)], ...
                              'u',g4(j),'V',g3(j),'B',[]); %#ok<AGROW>
        end
    end

    % ---- evaluation ------------------------------------------------------------
    n = numel(P);
    err_out = nan(1,n); err_neg = nan(1,n); e_p = nan(1,n); e_m = nan(1,n);
    cls_p = cell(1,n); cls_m = cell(1,n);
    for j = 1:n
        q = P(j);
        prm_p = params(kind, q, mp, p, Ts);  prm_m = params(kind, q, mm, p, Ts);
        prm_n = params(kind, q, mneg, p, Ts);
        yp = fp(q.x, q.u, prm_p{:});  ym = fm(q.x, q.u, prm_m{:});  yn = fm(q.x, q.u, prm_n{:});
        cls_p{j} = class(yp); cls_m{j} = class(ym);
        den = max(abs(double(ym(:))), 1e-3);
        err_out(j) = max(abs(double(yp(:)) - double(ym(:))) ./ den);
        err_neg(j) = max(abs(double(yp(:)) - double(yn(:))) ./ den);

        [Jxp, Jup] = mpc.internal.nlmpc.computeJacobianState(2, 1, 1, fp, prm_p, yp, q.x, q.u);
        [Jxm, Jum] = mpc.internal.nlmpc.computeJacobianState(2, 1, 1, fm, prm_m, ym, q.x, q.u);
        Jref = jac_centree(fm, prm_m, q.x, q.u, H_REF);
        nr = norm(Jref, 'fro');
        if nr > 0
            e_p(j) = norm([Jxp Jup] - Jref, 'fro') / nr;
            e_m(j) = norm([Jxm Jum] - Jref, 'fro') / nr;
        end
    end

    evaluable = e_m <= TOL_JAC;                       % NaN (Jref nulle) -> non evaluable
    n_eval = sum(evaluable); frac_noneval = 1 - n_eval / max(n,1);
    frac_div = sum(evaluable & e_p > TOL_JAC) / max(n_eval,1);
    if n == 0
        verdict = 'AUDIT NON CONCLUANT (aucun point reconstruit)';
    elseif max(err_out) > TOL_OUT
        verdict = 'SORTIES DIVERGENTES';
    elseif frac_noneval > FRAC_NONEVAL
        verdict = 'AUDIT NON CONCLUANT (derivees non evaluables)';
    elseif frac_div > FRAC_DIV
        verdict = 'SORTIES EQUIVALENTES, DERIVEES DIVERGENTES';
    else
        verdict = 'EQUIVALENCE ETABLIE';
    end
    neg_ok = n > 0 && max(err_neg) > TOL_OUT;

    R.(a) = struct('nom', NOMS{ia}, 'n_points', n, ...
        'n_brut', sum(strcmp({P.src},'brut_reconstruit')), 'n_grille', sum(strcmp({P.src},'grille')), ...
        'bras_reconstruits', sum(recon_ok), 'bras_total', numel(recon_ok), 'recon_err_max_rpm', max(recon_err), ...
        'classe_predict', strjoin(unique(cls_p), '/'), 'classe_manuel', strjoin(unique(cls_m), '/'), ...
        'err_out_max', max(err_out), 'err_neg_min', min(err_neg), 'controle_negatif_detecte', neg_ok, ...
        'e_p_median', median(e_p(evaluable)), 'e_m_median', median(e_m(evaluable)), ...
        'e_p_max', max(e_p(evaluable)), 'frac_derivees_divergentes', frac_div, ...
        'frac_non_evaluables', frac_noneval, 'verdict', verdict, ...
        'points', P, 'err_out', err_out, 'err_neg', err_neg, 'e_p', e_p, 'e_m', e_m);

    fprintf('%-13s %3d pts (%d brut, %d grille) | bras %d/%d, recon %.1e rpm | classes %s / %s\n', ...
        NOMS{ia}, n, R.(a).n_brut, R.(a).n_grille, sum(recon_ok), numel(recon_ok), max(recon_err), ...
        R.(a).classe_predict, R.(a).classe_manuel);
    fprintf('              sorties : ecart max %.2e | derivees : e_p med %.1e max %.1e, e_m med %.1e | div %.0f %% | non eval %.0f %%\n', ...
        R.(a).err_out_max, R.(a).e_p_median, R.(a).e_p_max, R.(a).e_m_median, 100*frac_div, 100*frac_noneval);
    fprintf('              controle negatif : %s (ecart min %.1e)\n', ...
        ternaire(neg_ok, 'DETECTE', '*** NON DETECTE ***'), R.(a).err_neg_min);
    fprintf('              -> %s\n\n', verdict);
end

% ---------- controle positif ---------------------------------------------------
pos_ok = R.mlpres.err_out_max <= TOL_OUT && R.gpres.err_out_max <= TOL_OUT;
neg_tous = all(cellfun(@(a) R.(a).controle_negatif_detecte, ARCHS));
fprintf('CONTROLE POSITIF (sorties MLP-residuel et GP-residuel conformes) : %s\n', ...
    ternaire(pos_ok, 'OK', '*** ECHEC — l''audit est en cause avant les modeles ***'));
fprintf('CONTROLE NEGATIF (perturbation detectee pour les 6)              : %s\n', ...
    ternaire(neg_tous, 'OK', '*** ECHEC — l''audit ne detecte pas une divergence connue ***'));

R.protocole = struct('TOL_OUT',TOL_OUT,'TOL_JAC',TOL_JAC,'H_REF',H_REF,'DV_NLMPC',1e-6, ...
    'FRAC_DIV',FRAC_DIV,'FRAC_NONEVAL',FRAC_NONEVAL,'NEG_DELTA',NEG_DELTA, ...
    'PTS_PAR_BRAS',PTS_PAR_BRAS,'GRILLE',GRILLE,'TOL_RECON_RPM',TOL_RECON_RPM);
R.provenance = struct('commit_audit',sha_audit,'campagne',CID,'brut_sha256',sha_brut, ...
    'code_campagne',meta.code_sha1,'matlab',version,'date',datestr(now,'yyyy-mm-dd HH:MM:SS'));
R.controle_positif = pos_ok; R.controle_negatif = neg_tous;
fo = fullfile(ROOT, 'results', 'audit_equivalence_2026-09-26.mat');
save(fo, 'R');
fprintf('\nresultats : %s\nsha256 : %s\n', fo, sha256_fichier(fo));
end


% =========================================================================
function [fp, fm, mp, mm, seqlen, kind] = preparer(a, S_res, S_gp, V2, V1)
%PREPARER  Memes fonctions et memes modeles que bypass_arm (run_bypass).
seqlen = 10;
switch a
  case 'mlpres'
    fp = @sf_residual;           mp = S_res.mdl;  fm = @sf_residual_manual;    mm = extract_residual_weights(S_res.mdl); kind = 'residuel';
  case 'gpres'
    fp = @sf_gp_residual_predict; mp = S_gp.mdl;  fm = @sf_gp_residual_manual; mm = extract_gp_weights(S_gp.mdl);       kind = 'residuel';
  case 'swmlp'
    fp = @sf_swmlp;  mp = V2.mdl_swmlp;   fm = @sf_swmlp_manual; mm = extract_dlnetwork_generic(V2.mdl_swmlp,'net');    kind = 'sequence';
  case 'pinn'
    fp = @sf_pinn;   mp = V2.mdl_pinn_v2; fm = @sf_pinn_manual;  mm = extract_dlnetwork_generic(V2.mdl_pinn_v2,'net');  kind = 'simple';
  case 'tcn'
    fp = @sf_tcn;    mp = V2.mdl_tcn;     fm = @sf_tcn_manual;   mm = extract_tcn_weights(V2.mdl_tcn);                 kind = 'sequence';
  case 'lstm'
    fp = @sf_lstm;   mp = V1.mdl_lstm;    fm = @sf_lstm_manual;  mm = extract_lstm_weights(V1.mdl_lstm);               kind = 'lstm';
    seqlen = V1.mdl_lstm.seq_len;
end
end

function prm = params(kind, q, mdl, p, Ts)
switch kind
  case 'residuel', prm = {q.V, mdl, p, Ts};
  case 'simple',   prm = {q.V, mdl};
  case 'sequence', mdl.seq_buf = q.B; prm = {q.V, mdl};
  case 'lstm',     prm = {q.V, mdl, q.B};
end
end

function m = perturber(a, m, d)
%PERTURBER  Copie en memoire du modele manuel, biais de sortie + d (normalise).
switch a
  case 'mlpres',        m.b3(1) = m.b3(1) + d;
  case 'gpres',         m.beta0_o = m.beta0_o + d;
  case {'swmlp','pinn'}, m.manual_b{end}(1) = m.manual_b{end}(1) + d;
  case {'tcn','lstm'},  m.fc_b(1) = m.fc_b(1) + d;
end
end

function [pts, err] = reconstruire(A, seed, seqlen, cfg, p, Ts) %#ok<INUSL>
%RECONSTRUIRE  Rejoue la boucle de bypass_arm avec les commandes enregistrees.
V = kaimal_wind(14, 60, Ts, seed);                 % V_MEAN, T_SIM de la fiche
x = [p.omega_r*0.97; 3.5]; mv = x(2);
B = repmat([x(1), x(2), V(1), mv], seqlen, 1);
n = numel(A.u_hist); pts = repmat(struct('src','','bras','','k',0,'x',[],'u',0,'V',0,'B',[]), 1, n);
om = zeros(n,1);
for k = 1:n
    pts(k).x = x; pts(k).u = A.u_hist(k); pts(k).V = V(k); pts(k).B = B;
    B = [B(2:end,:); x(1), x(2), V(k), A.u_hist(k)];
    x = wt_step(x, A.u_hist(k), V(k), p, Ts);
    om(k) = x(1)*30/pi;
end
err = max(abs(om - A.omega_hist(:)));
if isempty(err), err = inf; end
end

function J = jac_centree(f, prm, x, u, h)
z = [x; u]; J = zeros(2,3);
for j = 1:3
    d = h*max(abs(z(j)),1); zp = z; zm = z; zp(j) = zp(j)+d; zm(j) = zm(j)-d;
    J(:,j) = (double(f(zp(1:2), zp(3), prm{:})) - double(f(zm(1:2), zm(3), prm{:}))) / (2*d);
end
end

function s = ternaire(c, a, b)
if c, s = a; else, s = b; end
end

function s = court(h)
if isempty(h), s = '(vide)'; else, s = h(1:min(8,numel(h))); end
end
