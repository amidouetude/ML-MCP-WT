function R = audit_double_2026_09_26()
%AUDIT_DOUBLE_2026_09_26  predict() evalue en DOUBLE precision rejoint-il le
%   calcul manuel ?
%
%   R = audit_double_2026_09_26()
%
%   SUITE DE audit_equivalence_2026_09_26 (commit 80779b1, resultat 091351c2).
%   L'audit a montre que predict() renvoie des sorties `single` pour SW-MLP,
%   PINN-v2, TCN et LSTM, que les jacobiennes que nlmpc en tire par
%   differences avant sont faussees de 13 a 100 %, et que SW-MLP (2/60 points)
%   et LSTM (58/60) ont des sorties divergentes. Ce test separe trois causes :
%     (a) la simple precision de predict() ;
%     (b) une implementation manuelle differente du reseau ;
%     (c) autre chose dans la fonction d'etat.
%
%   METHODE
%     Pour chaque architecture, une COPIE EN MEMOIRE du reseau est convertie
%     en double (dlupdate(@double) sur Learnables et, s'il existe, sur State).
%     La fonction d'etat ORIGINALE (sf_swmlp, sf_pinn, sf_tcn, sf_lstm) est
%     appelee avec cette copie : seul le type des parametres change, le code
%     est le meme. Aucun fichier de modele n'est modifie.
%     Si la sortie obtenue n'est pas `double` (cas possible de minibatchpredict
%     pour le LSTM), la voie double utilise predict(net, dlarray(buf,'TC')),
%     et l'equivalence de cette voie est d'abord CONTROLEE en simple precision
%     contre minibatchpredict (TOL_VOIE). Si ce controle echoue, le test double
%     du LSTM est declare NON REALISE.
%     Pour le LSTM, l'etat initial stocke dans net.State est rapporte : le
%     calcul manuel suppose un etat initial NUL (extract_lstm_weights.m).
%
%   POINTS : exactement ceux de l'audit (memes regles, meme reconstruction,
%     controlee contre omega_hist). CONTROLE DE REPRODUCTION : l'ecart de
%     sortie predict(single) / manuel doit retrouver celui de l'audit
%     (TOL_REPRO en relatif) ; sinon les points ne sont pas les memes et le
%     test s'arrete.
%
%   PROTOCOLE FIGE AVANT EXECUTION (commite avant de tourner)
%     TOL_OUT_D = 1e-9   sorties predict(double) / manuel : deux calculs en
%                        double du meme reseau different au plus de quelques
%                        eps(double) par couche ; 1e-9 laisse 4 ordres de marge.
%     TOL_OUT   = 1e-5   seuil de l'audit (erreur de structure si depasse).
%     TOL_JAC   = 1e-3   seuil de l'audit, meme reference centree, meme regle
%                        d'evaluabilite, memes 5 %.
%     TOL_VOIE  = 1e-5   voies minibatchpredict / predict-dlarray en single.
%     TOL_REPRO = 1e-6   reproduction relative des ecarts de l'audit.
%
%   LECTURE, dans cet ordre, par architecture
%     TEST NON REALISE          sortie de la voie double non `double`, ou
%                               voie de substitution non equivalente
%     IMPLEMENTATION DIFFERENTE ecart predict(double) / manuel > TOL_OUT
%     ECART RESIDUEL EN DOUBLE  TOL_OUT_D < ecart <= TOL_OUT
%     MEME FONCTION             ecart <= TOL_OUT_D
%   puis, pour les derivees de predict(double) :
%     DERIVEES RETABLIES        <= 5 % des points evaluables au-dela de TOL_JAC
%     DERIVEES TOUJOURS FAUSSEES sinon
%   « MEME FONCTION + DERIVEES RETABLIES » attribue a la seule simple precision
%   les divergences de sorties et de derivees relevees par l'audit. Ce test NE
%   dit RIEN de la cause des echecs du solveur : il faudrait pour cela une
%   boucle fermee avec predict en double, qui n'est pas lancee ici.

HERE = fileparts(mfilename('fullpath'));
ROOT = fileparts(HERE);
addpath(fullfile(ROOT,'common'), HERE);

CID = 'P2-BYPASS-2026-09-24-a';
TOL_OUT_D = 1e-9; TOL_OUT = 1e-5; TOL_JAC = 1e-3; TOL_VOIE = 1e-5; TOL_REPRO = 1e-6;
H_REF = 1e-5; FRAC_DIV = 0.05; PTS_PAR_BRAS = 10; GRILLE = 3; TOL_RECON_RPM = 1e-8;

[sale, detail] = etat_proprete_code(ROOT);
if sale, error('audit:code_sale', 'Perimetre de code non propre :\n%s', detail); end
[~, sha_test] = system(['git -C "' ROOT '" rev-parse HEAD']); sha_test = strtrim(sha_test);

FRES = fullfile(ROOT, 'results', [CID '.mat']);
sha_brut = strtrim(strtok(fileread([FRES '.sha256'])));
assert(strcmp(sha256_fichier(FRES), sha_brut), 'audit:brut', 'empreinte du brut differente');
Z = load(FRES); meta = Z.meta; RES = Z.RES;
MOD = meta.model_paths;
for c = fieldnames(MOD)'
    assert(strcmp(sha256_fichier(fullfile(ROOT, MOD.(c{1}))), meta.model_sha256.(c{1})), ...
        'audit:modele', 'modele %s modifie depuis la campagne', MOD.(c{1}));
end
V2 = load(fullfile(ROOT, MOD.v2)); V1 = load(fullfile(ROOT, MOD.v1));
A0 = load(fullfile(ROOT, 'results', 'audit_equivalence_2026-09-26.mat')); A0 = A0.R;

cfg = stage0_config(); p = get_wt_params(); Ts = cfg.mpc.Ts; p.dt = Ts;
fprintf('\n=== TEST EN DOUBLE PRECISION — code %s | campagne %s | brut %s ===\n', ...
    sha_test(1:8), CID, sha_brut(1:16));
fprintf('TOL_OUT_D %.0e | TOL_OUT %.0e | TOL_JAC %.0e | TOL_VOIE %.0e\n\n', TOL_OUT_D, TOL_OUT, TOL_JAC, TOL_VOIE);

ARCHS = {'swmlp','pinn','tcn','lstm'};
NOMS  = {'SW-MLP','PINN-v2','TCN','LSTM'};
R = struct();

for ia = 1:numel(ARCHS)
    a = ARCHS{ia};
    switch a
      case 'swmlp', mp = V2.mdl_swmlp;   fp = @sf_swmlp; fm = @sf_swmlp_manual; mm = extract_dlnetwork_generic(mp,'net'); kind = 'sequence'; seqlen = 10;
      case 'pinn',  mp = V2.mdl_pinn_v2; fp = @sf_pinn;  fm = @sf_pinn_manual;  mm = extract_dlnetwork_generic(mp,'net'); kind = 'simple';   seqlen = 10;
      case 'tcn',   mp = V2.mdl_tcn;     fp = @sf_tcn;   fm = @sf_tcn_manual;   mm = extract_tcn_weights(mp);            kind = 'sequence'; seqlen = 10;
      case 'lstm',  mp = V1.mdl_lstm;    fp = @sf_lstm;  fm = @sf_lstm_manual;  mm = extract_lstm_weights(mp);           kind = 'lstm';     seqlen = mp.seq_len;
    end
    md = mp; md.net = dlupdate(@double, mp.net);
    etat = '';
    if isprop(mp.net, 'State') && ~isempty(mp.net.State)
        md.net.State = dlupdate(@double, mp.net.State);
        nrm = cellfun(@(v) norm(double(extractdata_si(v)), 'fro'), mp.net.State.Value);
        etat = strjoin(arrayfun(@(i) sprintf('%s/%s |%.3g|', mp.net.State.Layer{i}, ...
            mp.net.State.Parameter{i}, nrm(i)), 1:numel(nrm), 'UniformOutput', false), '  ');
    end

    % ---- memes points que l'audit -----------------------------------------
    P = struct('src',{},'bras',{},'k',{},'x',{},'u',{},'V',{},'B',{});
    for mode = {'predict','manual'}
        for r = 1:meta.n_repetitions
            f = sprintf('%s_%s_r%d', a, mode{1}, r);
            [pts, err] = reconstruire(RES.(f), meta.seed(r), seqlen, p, Ts);
            if err > TOL_RECON_RPM, continue; end
            for k = unique(round(linspace(1, numel(pts), PTS_PAR_BRAS)))
                q = pts(k); q.src = 'brut_reconstruit'; q.bras = f; q.k = k; P(end+1) = q; %#ok<AGROW>
            end
        end
    end
    if strcmp(kind, 'simple') && ~isempty(P)
        X = [arrayfun(@(q) q.x(1), P); arrayfun(@(q) q.x(2), P); [P.V]; [P.u]];
        lv = arrayfun(@(i) linspace(min(X(i,:)), max(X(i,:)), GRILLE), 1:4, 'UniformOutput', false);
        [g1,g2,g3,g4] = ndgrid(lv{:});
        for j = 1:numel(g1)
            P(end+1) = struct('src','grille','bras','','k',0,'x',[g1(j);g2(j)],'u',g4(j),'V',g3(j),'B',[]); %#ok<AGROW>
        end
    end
    n = numel(P);
    assert(n > 0, 'audit:points', '%s : aucun point reconstruit', a);

    % ---- voie double : la fonction d'etat originale avec la copie double -----
    voie = 'fonction d''etat originale, reseau en double';
    fd = fp;
    prm1 = params(kind, P(1), md, p, Ts);
    y0 = fp(P(1).x, P(1).u, prm1{:});
    cls_d = class(y0);
    err_voie = NaN;
    if ~strcmp(cls_d, 'double') && strcmp(a, 'lstm')
        voie = 'predict(net, dlarray(buf,''TC'')) en double (minibatchpredict ne rend pas du double)';
        fd = @sf_lstm_dl;
        ev = zeros(1,n);
        for j = 1:n
            q = P(j); prm = params(kind, q, mp, p, Ts);
            ya = double(fp(q.x, q.u, prm{:})); yb = double(sf_lstm_dl(q.x, q.u, prm{:}));
            ev(j) = max(abs(ya(:) - yb(:)) ./ max(abs(ya(:)), 1e-3));
        end
        err_voie = max(ev);
        cls_d = class(fd(P(1).x, P(1).u, prm1{:}));
    end
    realise = strcmp(cls_d, 'double') && (isnan(err_voie) || err_voie <= TOL_VOIE);

    % ---- mesures ---------------------------------------------------------------
    err_s = nan(1,n); err_d = nan(1,n); e_d = nan(1,n); e_m = nan(1,n);
    if realise
        for j = 1:n
            q = P(j);
            pp = params(kind, q, mp, p, Ts); pm = params(kind, q, mm, p, Ts); pd = params(kind, q, md, p, Ts);
            ys = double(fp(q.x, q.u, pp{:})); ym = fm(q.x, q.u, pm{:}); yd = fd(q.x, q.u, pd{:});
            den = max(abs(double(ym(:))), 1e-3);
            err_s(j) = max(abs(ys(:) - double(ym(:))) ./ den);
            err_d(j) = max(abs(double(yd(:)) - double(ym(:))) ./ den);
            [Jxd, Jud] = mpc.internal.nlmpc.computeJacobianState(2, 1, 1, fd, pd, yd, q.x, q.u);
            [Jxm, Jum] = mpc.internal.nlmpc.computeJacobianState(2, 1, 1, fm, pm, ym, q.x, q.u);
            Jref = jac_centree(fm, pm, q.x, q.u, H_REF); nr = norm(Jref, 'fro');
            if nr > 0
                e_d(j) = norm([Jxd Jud] - Jref, 'fro') / nr;
                e_m(j) = norm([Jxm Jum] - Jref, 'fro') / nr;
            end
        end
        % controle de reproduction de l'audit
        repro = abs(max(err_s) - A0.(a).err_out_max) / max(A0.(a).err_out_max, eps) <= TOL_REPRO ...
                && n == A0.(a).n_points;
        assert(repro, 'audit:repro', ['%s : les points ne reproduisent pas l''audit (ecart max %.3e ' ...
            'contre %.3e, %d points contre %d)'], a, max(err_s), A0.(a).err_out_max, n, A0.(a).n_points);
    end

    ev = e_m <= TOL_JAC; n_eval = sum(ev);
    frac_div_d = sum(ev & e_d > TOL_JAC) / max(n_eval, 1);
    if ~realise
        v_out = 'TEST NON REALISE'; v_jac = '-';
    else
        m = max(err_d);
        if m > TOL_OUT, v_out = 'IMPLEMENTATION DIFFERENTE';
        elseif m > TOL_OUT_D, v_out = 'ECART RESIDUEL EN DOUBLE';
        else, v_out = 'MEME FONCTION'; end
        if frac_div_d <= FRAC_DIV, v_jac = 'DERIVEES RETABLIES'; else, v_jac = 'DERIVEES TOUJOURS FAUSSEES'; end
    end

    R.(a) = struct('nom',NOMS{ia},'n_points',n,'voie_double',voie,'classe_voie_double',cls_d, ...
        'ecart_voie_single',err_voie,'etat_initial_reseau',etat, ...
        'err_single_max',max(err_s),'err_double_max',max(err_d),'err_double_median',median(err_d), ...
        'n_double_sup_tol_out',sum(err_d > TOL_OUT),'e_double_median',median(e_d(ev)),'e_double_max',max(e_d(ev)), ...
        'e_manuel_median',median(e_m(ev)),'frac_derivees_double_faussees',frac_div_d, ...
        'frac_non_evaluables',1 - n_eval/max(n,1),'verdict_sorties',v_out,'verdict_derivees',v_jac, ...
        'err_single',err_s,'err_double',err_d,'e_double',e_d,'e_manuel',e_m,'points',P);

    fprintf('%-8s %3d pts | voie double : %s -> %s\n', NOMS{ia}, n, voie, cls_d);
    if ~isnan(err_voie), fprintf('         equivalence de la voie en single : ecart max %.2e\n', err_voie); end
    if ~isempty(etat), fprintf('         etat initial stocke dans le reseau : %s\n', etat); end
    fprintf('         sorties : single %.2e (audit %.2e) | DOUBLE max %.2e, med %.2e, %d pts > TOL_OUT\n', ...
        max(err_s), A0.(a).err_out_max, max(err_d), median(err_d), sum(err_d > TOL_OUT));
    fprintf('         derivees : double med %.1e max %.1e | manuel med %.1e | faussees %.0f %% | non eval %.0f %%\n', ...
        R.(a).e_double_median, R.(a).e_double_max, R.(a).e_manuel_median, 100*frac_div_d, 100*R.(a).frac_non_evaluables);
    fprintf('         -> %s ; %s\n\n', v_out, v_jac);
end

R.protocole = struct('TOL_OUT_D',TOL_OUT_D,'TOL_OUT',TOL_OUT,'TOL_JAC',TOL_JAC,'TOL_VOIE',TOL_VOIE, ...
    'TOL_REPRO',TOL_REPRO,'H_REF',H_REF,'DV_NLMPC',1e-6,'FRAC_DIV',FRAC_DIV);
R.provenance = struct('commit_test',sha_test,'campagne',CID,'brut_sha256',sha_brut, ...
    'audit_reference','80779b1 / 091351c2','matlab',version,'date',datestr(now,'yyyy-mm-dd HH:MM:SS'));
fo = fullfile(ROOT, 'results', 'audit_double_2026-09-26.mat');
save(fo, 'R');
fprintf('resultats : %s\nsha256 : %s\n', fo, sha256_fichier(fo));
end


% =========================================================================
function xnext = sf_lstm_dl(x, u, V, mdl, seq_buf)
%SF_LSTM_DL  sf_lstm a l'identique, sauf l'appel au reseau : predict sur un
%   dlarray 'TC' au lieu de minibatchpredict sur une cellule. N'est utilisee
%   que si minibatchpredict ne rend pas du double, et apres controle de son
%   equivalence en simple precision.
new_row = [x(1), x(2), V, u(1)];
buf_new = [seq_buf(2:end, :); new_row];
buf_n = (buf_new - mdl.xmu) ./ mdl.xsig;
yn = extractdata(predict(mdl.net, dlarray(buf_n, 'TC')));
yn = reshape(yn, 1, []);
xnext = (yn .* mdl.ysig + mdl.ymu)';
end

function v = extractdata_si(v)
if isa(v, 'dlarray'), v = extractdata(v); end
end

function prm = params(kind, q, mdl, p, Ts) %#ok<INUSD>
switch kind
  case 'simple',   prm = {q.V, mdl};
  case 'sequence', mdl.seq_buf = q.B; prm = {q.V, mdl};
  case 'lstm',     prm = {q.V, mdl, q.B};
end
end

function [pts, err] = reconstruire(A, seed, seqlen, p, Ts)
V = kaimal_wind(14, 60, Ts, seed);
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
