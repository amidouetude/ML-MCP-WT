function out = run_double_2026_09_28(budget_s)
%RUN_DOUBLE_2026_09_28  Campagne P2-DOUBLE-2026-09-28-a.
%
%   Exécute la fiche docs/campagnes/P2-DOUBLE-2026-09-28-a.yaml, et rien
%   d'autre. Si le script et la fiche divergent, c'est la FICHE qui fait foi
%   et ce script est en faute.
%
%       run_double_2026_09_28(0)       % SMOKE TEST — 5 pas, graine 2025 seule
%       run_double_2026_09_28(600)     % campagne, tranches de 10 minutes
%
%   Reprend là où il s'est arrêté : un bras terminé n'est jamais recalculé.
%   Relancer jusqu'à « TOUT TERMINE ».
%
%   OBJET : la boucle fermée du 24/09 (P2-BYPASS-2026-09-24-a), à l'identique,
%   avec predict() appelé sur une COPIE EN DOUBLE du réseau (mode « double »).
%   Le mode « manual » et le mode « predict » (réseau d'origine) sont ceux du
%   24/09, sans changement.
%
%   DÉRIVÉ de run_bypass_2026_09_24.m (sha 3c9fc8e2…, commit 200fe22), dont il
%   reprend le verrou de reprise, le chargement des modèles par empreinte (D11),
%   la boucle d'un bras et la sauvegarde du vecteur brut. Différences, toutes
%   prescrites par la fiche :
%     . liste FERMÉE de 29 bras (11 au smoke), écrite dans
%       meta.expected_arm_ids et contrôlée par verifier_lot_campagne (D15) ;
%     . mode « double » : dlupdate(@double) sur une copie en mémoire du
%       dlnetwork (paramètres appris, et état s'il est non vide) ; la fonction
%       d'état est la fonction ORIGINALE ;
%     . avant le premier pas de CHAQUE bras, la fonction d'état est évaluée une
%       fois ; un bras « double » dont la sortie n'est pas de classe double est
%       REFUSÉ (erreur), jamais mesuré. Cet appel n'a pas d'effet sur le réseau
%       (predict et minibatchpredict n'en modifient pas l'état) et il est fait
%       dans TOUS les bras, pour que les temps double et manuel restent
%       comparables entre eux ;
%     . chaque bras enregistre arch, mode, model_key, model_sha256,
%       classe_sortie et conversion ;
%     . le modèle résiduel MLP n'est pas chargé (hors périmètre).
%
%   PREREQUIS : code, fiche et correctif D15 (59a1914) commités ; arbre propre
%   dans le périmètre surveillé ; machine au repos.

if nargin < 1, budget_s = 600; end
SMOKE = (budget_s == 0);

% ---------- racine du projet, indépendante du dossier courant ------------
HERE = fileparts(mfilename('fullpath'));          % piste_B_nominal_correction
ROOT = fileparts(HERE);
addpath(fullfile(ROOT,'common'), HERE);
RESDIR = fullfile(ROOT, 'results');
if ~exist(RESDIR,'dir'), mkdir(RESDIR); end

% ---------- modèles : UN chemin par modèle, relatif à la racine (D11) ------
MODELES = struct( ...
    'v2',    'common/stage2_models_v2.mat', ...       % SW-MLP, PINN-v2, TCN
    'v1',    'common/stage2_models.mat', ...          % LSTM
    'gpres', 'stage2_gp_residual_model.mat');         % GP résiduel (racine)
% Empreintes de la fiche (model_version) : une différence BLOQUE le lancement.
SHA_FICHE = struct( ...
    'v2',    '5ae6245330c290bb033db68270592c7d2e768a844aede889517b5e10174d069d', ...
    'v1',    '0561a48ac9a0d331e3d82614973fd357983338cabb66c420b38991a2574c1ffe', ...
    'gpres', '218e22f928fa5032b628b169f267bda0d6311d9a75f6c880a326f3cedbb196a1');

CID = 'P2-DOUBLE-2026-09-28-a';
if SMOKE
    FRES = fullfile(RESDIR, [CID '_SMOKE.mat']);
    fprintf(['\n*** SMOKE TEST ***  5 pas par bras, graine 2025 seule.\n' ...
             '    Sortie : %s\n' ...
             '    Ce fichier porte meta.smoke = true et sera REFUSE par la\n' ...
             '    verification de lot comme par l''analyse.\n\n'], FRES);
else
    FRES = fullfile(RESDIR, [CID '.mat']);
end

% ---------- transcription de la fiche ------------------------------------
cfg = stage0_config(); p = get_wt_params();
Ts = cfg.mpc.Ts; p.dt = Ts;
T_SIM = 60; V_MEAN = 14;
SEEDS = [2025 2026 2027];
N_DEF = round(T_SIM/Ts);           % 600
N_LSTM = 30;                       % tous les bras LSTM, cf. fiche
BUDGET_MS = 100;
if SMOKE, N_DEF = 5; N_LSTM = 5; SEEDS = SEEDS(1); end
BRAS = liste_bras(numel(SEEDS));   % liste FERMEE, ordre de la fiche

% ---------- estampille, ou reprise ---------------------------------------
if isfile(FRES)
    Z = load(FRES); meta = Z.meta; RES = Z.RES;
    % ---- VERROU DE REPRISE (repris de run_bypass_2026_09_24) -------------
    if ~isfield(meta, 'smoke')
        error('run_double:marqueur_absent', ...
            ['REPRISE IMPOSSIBLE. %s ne porte pas le champ meta.smoke : sa ' ...
             'nature est indeterminee.\nL''archiver, puis repartir a zero.'], FRES);
    end
    if meta.smoke ~= SMOKE
        error('run_double:mode', ...
            'Le fichier %s est un lot %s ; relance en mode %s. Incompatible.', ...
            FRES, mode_str(meta.smoke), mode_str(SMOKE));
    end
    sha_now = strtrim(gitout(ROOT, 'rev-parse HEAD'));
    if ~strcmp(sha_now, meta.code_sha1)
        error('run_double:commit_change', ...
            ['REPRISE IMPOSSIBLE. Campagne demarree sur le commit %s, HEAD ' ...
             'vaut %s.\nRevenir au commit d''origine, ou repartir sous un ' ...
             'NOUVEL identifiant avec sa propre fiche.'], ...
            court(meta.code_sha1), court(sha_now));
    end
    CODE_PATHS = perimetre_code();
    if ~strcmp(strjoin(CODE_PATHS, ' '), meta.code_scope)
        error('run_double:perimetre_change', ...
            ['REPRISE IMPOSSIBLE. Le perimetre surveille a change depuis le ' ...
             'demarrage.\n  au demarrage : %s\n  maintenant   : %s'], ...
            meta.code_scope, strjoin(CODE_PATHS, ' '));
    end
    [sale, detail_sale] = etat_proprete_code(ROOT, CODE_PATHS);
    if sale
        error('run_double:arbre_sale', ...
            'REPRISE IMPOSSIBLE. Le perimetre de code n''est plus propre :\n%s', ...
            detail_sale);
    end
    fic_now = strtrim(gitout(ROOT, ...
        ['log -1 --format=%H -- "docs/campagnes/' CID '.yaml"']));
    if ~strcmp(meta.fiche_commit, fic_now)
        error('run_double:fiche_change', ...
            'REPRISE IMPOSSIBLE. La fiche a ete recommitee (%s -> %s).', ...
            court(meta.fiche_commit), court(fic_now));
    end
    if ~isfield(meta, 'model_paths') || ~isequal(meta.model_paths, MODELES)
        error('run_double:modeles_change', ...
            'REPRISE IMPOSSIBLE. %s n''enregistre pas les memes chemins de modeles.', FRES);
    end
    if ~isfield(meta, 'expected_arm_ids') || ~isequal(meta.expected_arm_ids, BRAS)
        error('run_double:liste_change', ...
            ['REPRISE IMPOSSIBLE. La liste des bras enregistree dans %s differe ' ...
             'de celle de ce script.'], FRES);
    end
    if ~isfield(meta, 'n_batches')
        error('run_double:champ_absent', ...
            'REPRISE IMPOSSIBLE. %s ne porte pas meta.n_batches.', FRES);
    end
    meta.n_batches = meta.n_batches + 1;
    fprintf('[reprise] commit %s, fiche %s, %d bras mesures sur %d, tranche %d\n', ...
        court(sha_now), court(fic_now), numel(fieldnames(RES)), numel(BRAS), meta.n_batches);
else
    meta = stamp_campaign(CID, struct( ...
        'Np', cfg.mpc2.Np, 'Nc', cfg.mpc2.Nc, 'Ts', Ts, ...
        'seed', SEEDS, 'T_sim', T_SIM, 'V_mean', V_MEAN, ...
        'is_continuous_time', false, ...
        'solver', 'sqp', ...
        'ConstraintTolerance', 1e-4, 'OptimalityTolerance', 1e-4, ...
        'StepTolerance', 1e-4, ...
        'MaxIterations', 30, 'MaxFunctionEvaluations', 300, ...
        'n_repetitions', numel(SEEDS), ...
        'statistic', 'mediane + Q1/Q3 (pct7) ; facteur = med(double)/med(manuel)', ...
        'sample_size_default', N_DEF, 'sample_size_lstm', N_LSTM, ...
        'budget_ms', BUDGET_MS, ...
        'protocol_version', 'PROTO-P2-DOUBLE-v1', ...
        'reference_campaign', 'P2-BYPASS-2026-09-24-a', ...
        'conversion_double', 'dlupdate(@double) sur Learnables, et sur State si non vide', ...
        'plant_Tg_rated', p.Tg_rated, 'plant_K_opt', p.K_opt), ...
        struct('smoke', SMOKE));
    meta.model_paths  = MODELES;
    meta.model_sha256 = struct();
    for c = fieldnames(MODELES)'
        k = c{1}; pth = fullfile(ROOT, MODELES.(k));
        if ~isfile(pth)
            error('run_double:modele_absent', ...
                'Modele %s introuvable : %s. Aucun bras ne tourne sans empreinte.', ...
                k, MODELES.(k));
        end
        h = sha256_fichier(pth);
        if ~strcmp(h, SHA_FICHE.(k))
            error('run_double:modele_fiche', ...
                ['Le modele %s n''a pas l''empreinte inscrite dans la fiche.\n' ...
                 '  fiche  : %s\n  disque : %s'], MODELES.(k), SHA_FICHE.(k), h);
        end
        meta.model_sha256.(k) = h;
        fprintf('[modele] %-5s %-32s sha %s\n', k, MODELES.(k), h(1:12));
    end
    meta.expected_arm_ids = BRAS;        % LISTE FERMEE (D15)
    meta.expected_arms    = numel(BRAS);
    meta.n_batches = 1;
    RES = struct();
    save(FRES, 'meta', 'RES');
end
BATCH = meta.n_batches;
T0 = tic;

% ---------- boucle sur la liste fermée ------------------------------------
for ib = 1:numel(BRAS)
    fld = BRAS{ib};
    if isfield(RES, fld), continue; end
    tok = regexp(fld, '^([a-z0-9]+)_([a-z]+)_r(\d+)$', 'tokens', 'once');
    arch = tok{1}; mode = tok{2}; ir = str2double(tok{3});

    n_steps = N_DEF; if strcmp(arch,'lstm'), n_steps = N_LSTM; end
    fprintf('[%s] %s %s graine %d, %d pas\n', CID, arch, mode, SEEDS(ir), n_steps);
    r = bras_double(arch, mode, SEEDS(ir), n_steps, cfg, p, T_SIM, V_MEAN, BUDGET_MS, ROOT, meta);

    % ---- provenance par bras : un bras doit pouvoir se lire seul --------
    r.campaign_id  = CID;
    r.batch_id     = BATCH;
    r.arm_id       = fld;
    r.code_sha1    = meta.code_sha1;
    r.fiche_commit = meta.fiche_commit;
    r.repetition   = ir;
    r.seed         = SEEDS(ir);
    r.n_steps_requested = n_steps;
    r.statut = 'complete';
    if numel(r.cpu_ms) ~= n_steps
        r.statut = 'incomplete';
        warning('run_double:taille', 'bras %s : %d pas au lieu de %d', ...
            fld, numel(r.cpu_ms), n_steps);
    end
    RES.(fld) = r;
    save(FRES, 'meta', 'RES');

    fprintf('   med=%.2f ms  Q1=%.2f  Q3=%.2f  n=%d  depass=%d/%d  ExitFlag<0 : %d  [%s]\n', ...
        r.median_cpu_ms, r.q1_cpu_ms, r.q3_cpu_ms, numel(r.cpu_ms), ...
        r.n_overruns, numel(r.cpu_ms), r.n_infeasible, r.classe_sortie);

    if toc(T0) > budget_s && ~SMOKE
        out = sprintf('[EN COURS] dernier bras : %s', fld); disp(out); return
    end
end

out = 'TOUT TERMINE';
fprintf('\n%s — %d bras dans %s\n', out, numel(fieldnames(RES)), FRES);
if SMOKE
    fprintf(['\nSmoke test termine. Controles a faire A LA MAIN :\n' ...
             '  . les %d bras de la liste sont presents et ont 5 pas\n' ...
             '  . les bras double portent classe_sortie = double\n' ...
             '  . meta.smoke vaut true\n' ...
             'Puis ARCHIVER %s et lancer la campagne reelle.\n'], numel(BRAS), FRES);
    try
        verifier_lot_campagne(FRES);
        error('run_double:smokeAccepte', ...
            'ANOMALIE — le lot SMOKE a ete ACCEPTE par la verification.');
    catch ME
        switch ME.identifier
            case 'verifier_lot:refuse'
                fprintf('\n[smoke] refus conforme (%s) — comportement attendu.\n', ...
                    ME.identifier);
            otherwise
                rethrow(ME);
        end
    end
else
    verifier_lot_campagne(FRES);
end
end


% =========================================================================
function ids = liste_bras(n_rep)
%LISTE_BRAS  La liste fermée de la fiche (expected_arm_ids), dans son ordre.
%   Contrôles et témoin d'abord, puis, graine par graine et architecture par
%   architecture, double puis manuel. Au smoke (n_rep = 1) : les bras r1.
ids = {'swmlp_predict_r1', 'tcn_predict_r1'};
for ir = 1:n_rep
    ids{end+1} = sprintf('gpres_predict_r%d', ir); %#ok<AGROW>
end
for ir = 1:n_rep
    for a = {'swmlp','pinn','tcn','lstm'}
        for m = {'double','manual'}
            ids{end+1} = sprintf('%s_%s_r%d', a{1}, m{1}, ir); %#ok<AGROW>
        end
    end
end
end

function r = bras_double(arch, mode, seed, n_steps, cfg, p, T_SIM, V_MEAN, BUDGET_MS, ROOT, meta)
%BRAS_DOUBLE  Un bras. Boucle identique à bypass_arm (run_bypass_2026_09_24),
%   plus le mode « double » et le contrôle de classe avant le premier pas.
Ts = cfg.mpc.Ts;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, seed);

Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc;
npar = 2; useseq = false; seqlen = 10; conversion = 'aucune';
switch arch
  case 'gpres'
    cle = 'gpres'; S = charger_modele(cle, ROOT, meta); npar = 4;
    if strcmp(mode,'predict'), fcn='sf_gp_residual_predict'; mdl=S.mdl;
    else, error('run_double:mode_interdit', 'gpres : seul le mode predict est prevu'); end
  case 'swmlp'
    cle = 'v2'; V2 = charger_modele(cle, ROOT, meta); useseq = true;
    switch mode
      case 'predict', fcn='sf_swmlp';        mdl=V2.mdl_swmlp;
      case 'double',  fcn='sf_swmlp';        [mdl, conversion]=en_double(V2.mdl_swmlp);
      case 'manual',  fcn='sf_swmlp_manual'; mdl=extract_dlnetwork_generic(V2.mdl_swmlp,'net');
    end
  case 'pinn'
    cle = 'v2'; V2 = charger_modele(cle, ROOT, meta);
    switch mode
      case 'double',  fcn='sf_pinn';         [mdl, conversion]=en_double(V2.mdl_pinn_v2);
      case 'manual',  fcn='sf_pinn_manual';  mdl=extract_dlnetwork_generic(V2.mdl_pinn_v2,'net');
      otherwise, error('run_double:mode_interdit', 'pinn : mode %s non prevu', mode);
    end
  case 'tcn'
    cle = 'v2'; V2 = charger_modele(cle, ROOT, meta); useseq = true;
    switch mode
      case 'predict', fcn='sf_tcn';          mdl=V2.mdl_tcn;
      case 'double',  fcn='sf_tcn';          [mdl, conversion]=en_double(V2.mdl_tcn);
      case 'manual',  fcn='sf_tcn_manual';   mdl=extract_tcn_weights(V2.mdl_tcn);
    end
  case 'lstm'
    cle = 'v1'; V1 = charger_modele(cle, ROOT, meta); npar = 3; seqlen = V1.mdl_lstm.seq_len;
    switch mode
      case 'double',  fcn='sf_lstm';         [mdl, conversion]=en_double(V1.mdl_lstm);
      case 'manual',  fcn='sf_lstm_manual';  mdl=extract_lstm_weights(V1.mdl_lstm);
      otherwise, error('run_double:mode_interdit', 'lstm : mode %s non prevu', mode);
    end
  otherwise, error('run_double:architecture', 'architecture inconnue : %s', arch);
end
if ~exist('fcn', 'var')
    error('run_double:mode_interdit', '%s : mode %s non prevu', arch, mode);
end

nlobj = nlmpc(2,2,1);
nlobj.Model.IsContinuousTime = false;          % VERROU de la fiche
nlobj.Model.StateFcn = fcn;
nlobj.Model.NumberOfParameters = npar;
nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
nlobj.Optimization.SolverOptions.Algorithm              = 'sqp';
nlobj.Optimization.SolverOptions.MaxIterations          = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;

assert(nlobj.Model.IsContinuousTime == false, ...
    'VERROU FICHE : IsContinuousTime doit valoir false');

x = [p.omega_r*0.97; 3.5]; mv = x(2);
seq_buf = repmat([x(1), x(2), V_wind(1), mv], seqlen, 1);

% ---- contrôle de classe AVANT le premier pas (fiche, condition 14) --------
% Même état, même vent et mêmes paramètres que le premier appel de nlmpcmove.
if useseq, mdl.seq_buf = seq_buf; end
prm0 = parametres(npar, V_wind(1), mdl, p, Ts, seq_buf);
y0 = feval(fcn, x, mv, prm0{:});
classe_sortie = class(y0);
if strcmp(mode, 'double') && ~isa(y0, 'double')
    error('run_double:classe', ...
        ['Bras %s_%s : la fonction d''etat %s rend du %s avec le reseau converti.\n' ...
         'Le bras n''est pas mesure.'], arch, mode, fcn, classe_sortie);
end

cpu = zeros(n_steps,1); oh = zeros(n_steps,1); ef = zeros(n_steps,1); uh = zeros(n_steps,1);
op = nlmpcmoveopt;
ts_start = datestr(now, 'yyyy-mm-dd HH:MM:SS');
t_wall = tic;
for k = 1:n_steps
    Vk = V_wind(k);
    if useseq, mdl.seq_buf = seq_buf; end
    op.Parameters = parametres(npar, Vk, mdl, p, Ts, seq_buf);
    t0 = tic;
    [mv, op, info] = nlmpcmove(nlobj, x, mv, [p.omega_r, 0], [], op);
    cpu(k) = toc(t0)*1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    ef(k) = info.ExitFlag; uh(k) = mv(1);
    seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
    x = wt_step(x, mv(1), Vk, p, Ts);
    oh(k) = x(1)*30/pi;
end

r = struct();
r.arch = arch; r.mode = mode; r.state_fcn = fcn; r.Np = Np; r.Nc = Nc;
r.model_key = cle;
r.model_sha256 = meta.model_sha256.(cle);    % verifiee par charger_modele avant chargement
r.classe_sortie = classe_sortie;
r.conversion = conversion;
r.cpu_ms = cpu;                              % LE VECTEUR BRUT
r.omega_hist = oh; r.u_hist = uh; r.exitflag = ef;
r.median_cpu_ms = median(cpu);
r.q1_cpu_ms = pct7(cpu, 0.25);
r.q3_cpu_ms = pct7(cpu, 0.75);
r.mean_cpu_ms = mean(cpu);
r.max_cpu_ms = max(cpu);
r.n_overruns = sum(cpu > BUDGET_MS);         % > STRICT, cf. fiche
r.n_infeasible = sum(ef < 0);
r.rmse_omega_rpm = sqrt(mean((oh - p.omega_r*30/pi).^2));
r.wall_s = toc(t_wall);
r.timestamp_start = ts_start;
r.timestamp_end   = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end


% =========================================================================
function prm = parametres(npar, Vk, mdl, p, Ts, seq_buf)
%PARAMETRES  op.Parameters de bypass_arm, à l'identique.
switch npar
  case 4, prm = {Vk, mdl, p, Ts};
  case 3, prm = {Vk, mdl, seq_buf};
  otherwise, prm = {Vk, mdl};
end
end

function [md, conversion] = en_double(mp)
%EN_DOUBLE  Copie en mémoire du modèle, réseau converti en double. Le fichier
%   de modèle n'est ni modifié ni réécrit. Procédé de l'audit 64138a6.
if ~isa(mp.net, 'dlnetwork')
    error('run_double:type_reseau', ...
        'Conversion prevue pour un dlnetwork, recu %s.', class(mp.net));
end
md = mp;
md.net = dlupdate(@double, mp.net);
conversion = 'dlupdate(@double) sur Learnables';
if ~isempty(mp.net.State)
    md.net.State = dlupdate(@double, mp.net.State);
    conversion = [conversion ' et State'];
end
end

function o = gitout(root, args)
[~, o] = system(['git -C "' root '" ' args]);
end

function s = court(h)
if isempty(h), s = '(vide)'; else, s = h(1:min(8,numel(h))); end
end

function s = mode_str(b)
if b, s = 'SMOKE'; else, s = 'REEL'; end
end

function S = charger_modele(cle, ROOT, meta)
%CHARGER_MODELE  Repris de run_bypass_2026_09_24 (D11) : l'empreinte est
%   recalculée avant CHAQUE chargement et comparée à celle du démarrage.
pth = fullfile(ROOT, meta.model_paths.(cle));
h = sha256_fichier(pth);
if ~strcmp(h, meta.model_sha256.(cle))
    error('run_double:modele_modifie', ...
        ['Le modele %s n''a plus l''empreinte relevee au demarrage.\n' ...
         '  releve : %s\n  actuel : %s\nLe bras ne tourne pas.'], ...
        meta.model_paths.(cle), meta.model_sha256.(cle), h);
end
S = load(pth);
end
