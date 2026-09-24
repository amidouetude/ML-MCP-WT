function out = run_bypass_2026_09_24(budget_s)
%RUN_BYPASS_2026_09_24  Campagne P2-BYPASS-2026-09-24-a.
%
%   Exécute la fiche docs/campagnes/P2-BYPASS-2026-09-24-a.yaml, et rien
%   d'autre. Si le script et la fiche divergent, c'est la FICHE qui fait foi
%   et ce script est en faute.
%
%       run_bypass_2026_09_24(0)       % SMOKE TEST — 5 pas, fichier separe
%       run_bypass_2026_09_24(600)     % campagne, tranches de 10 minutes
%
%   Reprend là où il s'est arrêté : un bras terminé n'est jamais recalculé.
%   Relancer jusqu'à « TOUT TERMINE ». Durée totale ≈ 5 h 30.
%
%   PREREQUIS : results/ dans .gitignore ; code et fiche commités ; arbre
%   propre dans le périmètre surveillé.
%
%   Révision du 23/09/2026 (2e passe) — corrections D3, D4, hygiène :
%     . le smoke test écrit dans SES PROPRES fichiers et pose meta.smoke
%     . quartiles par pct7 (pas de dépendance Statistics Toolbox, et même
%       convention que numpy côté vérificateur)
%     . chemins déduits de mfilename, plus de dépendance au dossier courant
%     . git invoqué avec -C sur la racine
%     . fichier d'état mort supprimé (l'état vit dans le .mat lui-même)
%
%   Révision du 25/09/2026 — D11, trouvé par le premier smoke test :
%     . les modèles étaient chargés par NOM NU — load('stage2_residual_model.mat')
%       — donc résolus contre le dossier courant, alors que l'en-tête
%       promettait l'indépendance au dossier courant. Lancé depuis
%       piste_B_nominal_correction, comme le prescrivait la procédure, le
%       smoke test échouait au premier bras : MATLAB:ErrorRecovery:
%       ItemNoLongerOnPath.
%     . plus grave, l'empreinte des modèles était prise par which() et le
%       modèle chargé par load() : deux résolutions indépendantes, et un modèle
%       introuvable était SAUTÉ EN SILENCE (if ~isempty(pth)). Depuis ce
%       dossier, deux modèles sur quatre auraient tourné sans empreinte, et
%       aucun contrôle ne l'aurait dit.
%     . désormais UN chemin par modèle, relatif à la racine, inscrit dans
%       meta.model_paths ; un modèle absent ou illisible BLOQUE ; et avant
%       CHAQUE chargement l'empreinte du fichier est recalculée et comparée à
%       meta.model_sha256 — le modèle chargé est donc celui qui a été empreinté.
%     . la seconde définition locale de l'empreinte est supprimée au profit de
%       common/sha256_fichier.m, la définition unique.
%
%   Révision du 23/09/2026 (3e passe) — D8 et durcissement du verrou :
%     . le switch sur ME.identifier dans l'épilogue smoke (D8)
%     . le verrou de reprise contrôle la PRESENCE des champs avant leur
%       valeur : un artefact antérieur au marquage est refusé avec un
%       diagnostic explicite, non par une erreur MATLAB d'accès à un champ

if nargin < 1, budget_s = 600; end
SMOKE = (budget_s == 0);

% ---------- racine du projet, indépendante du dossier courant ------------
HERE = fileparts(mfilename('fullpath'));          % piste_B_nominal_correction
ROOT = fileparts(HERE);
addpath(fullfile(ROOT,'common'), HERE);
RESDIR = fullfile(ROOT, 'results');
if ~exist(RESDIR,'dir'), mkdir(RESDIR); end

% ---------- modèles : UN chemin par modèle, relatif à la racine (D11) ------
% Transcription de model_version dans la fiche. Aucun modèle n'est résolu par
% le dossier courant ni par le chemin MATLAB : ce qui est empreinté est ce qui
% est chargé.
MODELES = struct( ...
    'v2',    'common/stage2_models_v2.mat', ...       % SW-MLP, PINN-v2, TCN
    'v1',    'common/stage2_models.mat', ...          % LSTM
    'res',   'stage2_residual_model.mat', ...         % MLP résiduel (racine)
    'gpres', 'stage2_gp_residual_model.mat');         % GP résiduel  (racine)

CID = 'P2-BYPASS-2026-09-24-a';
if SMOKE
    FRES = fullfile(RESDIR, [CID '_SMOKE.mat']);   % D3 : fichier SEPARE
    fprintf(['\n*** SMOKE TEST ***  5 pas par bras, une seule graine.\n' ...
             '    Sortie : %s\n' ...
             '    Ce fichier porte meta.smoke = true et sera REFUSE par la\n' ...
             '    verification de lot comme par l''analyse. Il ne peut pas\n' ...
             '    etre confondu avec la campagne.\n\n'], FRES);
else
    FRES = fullfile(RESDIR, [CID '.mat']);
end

% ---------- transcription de la fiche ------------------------------------
cfg = stage0_config(); p = get_wt_params();
Ts = cfg.mpc.Ts; p.dt = Ts;
T_SIM = 60; V_MEAN = 14;
SEEDS = [2025 2026 2027];
N_DEF = round(T_SIM/Ts);           % 600
N_LSTM = 30;                       % les DEUX bras LSTM, cf. fiche
BUDGET_MS = 100;
if SMOKE, N_DEF = 5; N_LSTM = 5; SEEDS = SEEDS(1); end

ARCHS = {'mlpres','gpres','swmlp','pinn','tcn','lstm'};
MODES = {'predict','manual'};

% ---------- estampille, ou reprise ---------------------------------------
if isfile(FRES)
    Z = load(FRES); meta = Z.meta; RES = Z.RES;
    % ---- VERROU DE REPRISE --------------------------------------------
    % La campagne se reprend en plusieurs sessions. Si le code ou la fiche
    % changent entre deux tranches, les bras déjà mesurés et ceux qui restent
    % ne viennent plus du même état : le .mat serait un mélange, et rien ne
    % le signalerait.
    %
    % ORDRE : le marqueur de nature est contrôlé EN PREMIER. Un artefact
    % antérieur à l'introduction de meta.smoke échouerait sinon d'abord sur
    % le contrôle de commit, avec un diagnostic faux (« code modifié ») pour
    % une cause qui est en réalité « ce fichier ne vient pas de ce
    % dispositif ». Le contrôle le moins coûteux est aussi le plus
    % fondamental : c'est l'identité du fichier.
    if ~isfield(meta, 'smoke')
        error('run_bypass:marqueur_absent', ...
            ['REPRISE IMPOSSIBLE. %s ne porte pas le champ meta.smoke.\n' ...
             'Ce fichier est ANTERIEUR au dispositif de marquage (23/09/2026) : ' ...
             'sa nature\nest indeterminee — rien ne dit s''il vient d''un smoke ' ...
             'test ou d''une campagne.\nIl ne peut donc pas etre repris. ' ...
             'L''archiver ou le supprimer, puis repartir a zero\nsous cet ' ...
             'identifiant.'], FRES);
    end
    if meta.smoke ~= SMOKE
        error('run_bypass:mode', ...
            'Le fichier %s est un lot %s ; relance en mode %s. Incompatible.', ...
            FRES, mode_str(meta.smoke), mode_str(SMOKE));
    end
    sha_now = strtrim(gitout(ROOT, 'rev-parse HEAD'));
    if ~strcmp(sha_now, meta.code_sha1)
        error('run_bypass:commit_change', ...
            ['REPRISE IMPOSSIBLE. Campagne demarree sur le commit %s, HEAD ' ...
             'vaut %s.\nLes bras deja mesures et ceux qui restent ne ' ...
             'viendraient pas du meme code.\nRevenir au commit d''origine, ' ...
             'ou repartir sous un NOUVEL identifiant (suffixe -b) avec sa ' ...
             'propre fiche.'], court(meta.code_sha1), court(sha_now));
    end
    % D9 : meme definition de « propre » qu'au demarrage, et une seule.
    % La version precedente redisait ici le controle avec ses propres mots
    % (--untracked-files=no), donc avec le meme angle mort : un script de
    % mesure ajoute entre deux tranches et jamais commite passait inapercu.
    %
    % Le perimetre lui-meme est compare a celui inscrit au demarrage : l'elargir
    % ou le retrecir en cours de campagne changerait la signification du
    % controle sans rien changer a son verdict.
    CODE_PATHS = perimetre_code();
    if ~strcmp(strjoin(CODE_PATHS, ' '), meta.code_scope)
        error('run_bypass:perimetre_change', ...
            ['REPRISE IMPOSSIBLE. Le perimetre surveille a change depuis le ' ...
             'demarrage.\n  au demarrage : %s\n  maintenant   : %s\n' ...
             'Le controle de proprete ne porterait plus sur la meme chose. ' ...
             'Repartir sous\nun nouvel identifiant.'], ...
            meta.code_scope, strjoin(CODE_PATHS, ' '));
    end
    [sale, detail_sale] = etat_proprete_code(ROOT, CODE_PATHS);
    if sale
        error('run_bypass:arbre_sale', ...
            ['REPRISE IMPOSSIBLE. Le perimetre de code n''est plus propre :\n%s\n' ...
             'Les bras deja mesures et ceux qui restent ne viendraient pas du ' ...
             'meme etat.'], detail_sale);
    end
    fic_now = strtrim(gitout(ROOT, ...
        ['log -1 --format=%H -- "docs/campagnes/' CID '.yaml"']));
    if ~strcmp(meta.fiche_commit, fic_now)
        error('run_bypass:fiche_change', ...
            ['REPRISE IMPOSSIBLE. La fiche a ete recommitee (%s -> %s). ' ...
             'Repartir sous un nouvel identifiant.'], ...
            court(meta.fiche_commit), court(fic_now));
    end
    if ~isfield(meta, 'model_paths') || ~isequal(meta.model_paths, MODELES)
        error('run_bypass:modeles_change', ...
            ['REPRISE IMPOSSIBLE. %s n''enregistre pas les memes chemins de ' ...
             'modeles que ce script.\nLes bras deja mesures et ceux qui restent ' ...
             'ne viendraient pas des memes modeles.'], FRES);
    end
    if ~isfield(meta, 'n_batches')
        error('run_bypass:champ_absent', ...
            ['REPRISE IMPOSSIBLE. %s porte meta.smoke mais pas meta.n_batches : ' ...
             'structure\nde metadonnees incomplete. Ne pas reprendre un fichier ' ...
             'dont on ne sait pas\ncombien de tranches l''ont compose.'], FRES);
    end
    meta.n_batches = meta.n_batches + 1;
    fprintf('[reprise] commit %s, fiche %s, %d bras mesures, tranche %d\n', ...
        court(sha_now), court(fic_now), numel(fieldnames(RES)), meta.n_batches);
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
        'statistic', 'mediane + Q1/Q3 (pct7) ; facteur = med(predict)/med(manuel)', ...
        'sample_size_default', N_DEF, 'sample_size_lstm', N_LSTM, ...
        'budget_ms', BUDGET_MS, ...
        'protocol_version', 'PROTO-P2-BYPASS-v1', ...
        'plant_Tg_rated', p.Tg_rated, 'plant_K_opt', p.K_opt), ...
        struct('smoke', SMOKE));
    % D11 : un modele absent ou illisible BLOQUE. L'ancienne boucle le sautait
    % en silence, et le bras aurait tourne sans empreinte.
    meta.model_paths  = MODELES;
    meta.model_sha256 = struct();
    for c = fieldnames(MODELES)'
        k = c{1}; pth = fullfile(ROOT, MODELES.(k));
        if ~isfile(pth)
            error('run_bypass:modele_absent', ...
                'Modele %s introuvable : %s. Aucun bras ne tourne sans empreinte.', ...
                k, MODELES.(k));
        end
        h = sha256_fichier(pth);
        if strcmp(h, 'INDISPONIBLE')
            error('run_bypass:modele_illisible', ...
                'Empreinte indisponible pour %s. Une empreinte indisponible n''est pas une empreinte.', ...
                MODELES.(k));
        end
        meta.model_sha256.(k) = h;
        fprintf('[modele] %-5s %-32s sha %s\n', k, MODELES.(k), h(1:12));
    end
    meta.n_batches = 1;
    meta.expected_arms = numel(ARCHS)*numel(MODES)*numel(SEEDS);
    RES = struct();
    save(FRES, 'meta', 'RES');
end
BATCH = meta.n_batches;
T0 = tic;

% ---------- boucle sur les bras ------------------------------------------
for ir = 1:numel(SEEDS)
for ia = 1:numel(ARCHS)
for im = 1:numel(MODES)
    arch = ARCHS{ia}; mode = MODES{im};
    fld = sprintf('%s_%s_r%d', arch, mode, ir);
    if isfield(RES, fld), continue; end

    n_steps = N_DEF; if strcmp(arch,'lstm'), n_steps = N_LSTM; end
    fprintf('[%s] %s %s graine %d, %d pas\n', CID, arch, mode, SEEDS(ir), n_steps);
    r = bypass_arm(arch, mode, SEEDS(ir), n_steps, cfg, p, T_SIM, V_MEAN, BUDGET_MS, ROOT, meta);

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
        warning('run_bypass:taille', 'bras %s : %d pas au lieu de %d', ...
            fld, numel(r.cpu_ms), n_steps);
    end
    RES.(fld) = r;
    save(FRES, 'meta', 'RES');     % meta sauve aussi : n_batches a jour

    fprintf('   med=%.2f ms  Q1=%.2f  Q3=%.2f  n=%d  depass=%d/%d  ExitFlag<0 : %d\n', ...
        r.median_cpu_ms, r.q1_cpu_ms, r.q3_cpu_ms, numel(r.cpu_ms), ...
        r.n_overruns, numel(r.cpu_ms), r.n_infeasible);

    if toc(T0) > budget_s && ~SMOKE
        out = sprintf('[EN COURS] dernier bras : %s', fld); disp(out); return
    end
end
end
end

out = 'TOUT TERMINE';
fprintf('\n%s — %d bras dans %s\n', out, numel(fieldnames(RES)), FRES);
if SMOKE
    fprintf(['\nSmoke test termine. Controles a faire A LA MAIN :\n' ...
             '  . les 12 bras sont presents et ont 5 pas\n' ...
             '  . chaque bras porte cpu_ms, code_sha1, fiche_commit, statut\n' ...
             '  . meta.smoke vaut true\n' ...
             '  . le .mat se relit sans erreur\n' ...
             'Puis SUPPRIMER %s et lancer la campagne reelle.\n'], FRES);
    % D8 — n'accepter QUE l'erreur de refus prevue. Un try/catch large
    % presenterait un BUG du verificateur comme un refus attendu : le smoke
    % donnerait alors une fausse impression de reussite.
    try
        verifier_lot_campagne(FRES);
        error('run_bypass:smokeAccepte', ...
            ['ANOMALIE — le lot SMOKE a ete ACCEPTE par la verification. ' ...
             'Le verrou meta.smoke est defectueux : un smoke test pourrait ' ...
             'etre publie. Corriger verifier_lot_campagne avant toute suite.']);
    catch ME
        switch ME.identifier
            case 'verifier_lot:refuse'
                fprintf('\n[smoke] refus conforme (%s) — comportement attendu.\n', ...
                    ME.identifier);
            case 'run_bypass:smokeAccepte'
                rethrow(ME);
            otherwise
                fprintf(['\n[smoke] ERREUR INATTENDUE dans le verificateur ' ...
                         '(%s).\nCe n''est PAS le refus attendu : le controle ' ...
                         'lui-meme est en faute.\n'], ME.identifier);
                rethrow(ME);
        end
    end
else
    verifier_lot_campagne(FRES);
    fprintf('Lancer maintenant : analyse_bypass_2026_09_24\n');
end
end


% =========================================================================
function r = bypass_arm(arch, mode, seed, n_steps, cfg, p, T_SIM, V_MEAN, BUDGET_MS, ROOT, meta)
%BYPASS_ARM  Un bras. Structure reprise de remesure_arm.m (08/09), avec les
%            réglages de la fiche et la sauvegarde du VECTEUR cpu_ms complet.
Ts = cfg.mpc.Ts;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, seed);

Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc;
npar = 2; useseq = false; seqlen = 10;
switch arch
  case 'mlpres'
    S = charger_modele('res', ROOT, meta); npar = 4;
    if strcmp(mode,'predict'), fcn='sf_residual';        mdl=S.mdl;
    else,                      fcn='sf_residual_manual'; mdl=extract_residual_weights(S.mdl); end
  case 'gpres'
    S = charger_modele('gpres', ROOT, meta); npar = 4;
    if strcmp(mode,'predict'), fcn='sf_gp_residual_predict'; mdl=S.mdl;
    else,                      fcn='sf_gp_residual_manual';  mdl=extract_gp_weights(S.mdl); end
  case 'swmlp'
    V2 = charger_modele('v2', ROOT, meta); useseq = true;
    if strcmp(mode,'predict'), fcn='sf_swmlp';        mdl=V2.mdl_swmlp;
    else,                      fcn='sf_swmlp_manual'; mdl=extract_dlnetwork_generic(V2.mdl_swmlp,'net'); end
  case 'pinn'
    V2 = charger_modele('v2', ROOT, meta);
    if strcmp(mode,'predict'), fcn='sf_pinn';        mdl=V2.mdl_pinn_v2;
    else,                      fcn='sf_pinn_manual'; mdl=extract_dlnetwork_generic(V2.mdl_pinn_v2,'net'); end
  case 'tcn'
    V2 = charger_modele('v2', ROOT, meta); useseq = true;
    if strcmp(mode,'predict'), fcn='sf_tcn';        mdl=V2.mdl_tcn;
    else,                      fcn='sf_tcn_manual'; mdl=extract_tcn_weights(V2.mdl_tcn); end
  case 'lstm'
    V1 = charger_modele('v1', ROOT, meta); npar = 3; seqlen = V1.mdl_lstm.seq_len;
    if strcmp(mode,'predict'), fcn='sf_lstm';        mdl=V1.mdl_lstm;
    else,                      fcn='sf_lstm_manual'; mdl=extract_lstm_weights(V1.mdl_lstm); end
  otherwise, error('architecture inconnue : %s', arch);
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
cpu = zeros(n_steps,1); oh = zeros(n_steps,1); ef = zeros(n_steps,1); uh = zeros(n_steps,1);
op = nlmpcmoveopt;
ts_start = datestr(now, 'yyyy-mm-dd HH:MM:SS');
t_wall = tic;
for k = 1:n_steps
    Vk = V_wind(k);
    if useseq, mdl.seq_buf = seq_buf; end
    switch npar
      case 4, op.Parameters = {Vk, mdl, p, Ts};
      case 3, op.Parameters = {Vk, mdl, seq_buf};
      otherwise, op.Parameters = {Vk, mdl};
    end
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
r.cpu_ms = cpu;                              % LE VECTEUR BRUT
r.omega_hist = oh; r.u_hist = uh; r.exitflag = ef;
r.median_cpu_ms = median(cpu);
r.q1_cpu_ms = pct7(cpu, 0.25);               % D4 : convention figee
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
%CHARGER_MODELE  Charge le modele CLE depuis le chemin inscrit dans meta, apres
%   avoir verifie que son empreinte est TOUJOURS celle relevee au demarrage (D11).
%   Un modele remplace entre deux bras, ou entre deux tranches, est refuse.
pth = fullfile(ROOT, meta.model_paths.(cle));
h = sha256_fichier(pth);
if ~strcmp(h, meta.model_sha256.(cle))
    error('run_bypass:modele_modifie', ...
        ['Le modele %s n''a plus l''empreinte relevee au demarrage.\n' ...
         '  releve : %s\n  actuel : %s\nLe bras ne tourne pas.'], ...
        meta.model_paths.(cle), meta.model_sha256.(cle), h);
end
S = load(pth);
end
