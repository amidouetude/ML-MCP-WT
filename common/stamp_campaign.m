function meta = stamp_campaign(campaign_id, extra, opts)
%STAMP_CAMPAIGN  Metadonnees obligatoires a enregistrer avec CHAQUE resultat.
%
%   Regle 1 : aucun chiffre n'entre dans un manuscrit s'il n'est pas associe a
%   une campagne identifiee, un protocole versionne et un fichier brut
%   verifiable. Cette fonction produit la partie « protocole versionne ».
%
%       meta = stamp_campaign(cid, protocole)            % campagne reelle
%       meta = stamp_campaign(cid, protocole, struct('smoke',true))
%
%   PERIMETRE DE PROPRETE — le controle ne porte QUE sur les fichiers suivis
%   par git dans CODE_PATHS. results/ en est exclu : les artefacts produits
%   par la campagne ne doivent pas la rendre non conforme.
%
%   Revision du 23/09/2026 (2e passe) : correction du formatage fprintf,
%   ajout du marqueur smoke, git invoque avec -C sur la racine du projet.

if nargin < 2, extra = struct(); end
if nargin < 3, opts  = struct(); end
SMOKE = isfield(opts,'smoke') && opts.smoke;

% racine du projet, deduite de l'emplacement de CE fichier (common/)
ROOT = fileparts(fileparts(mfilename('fullpath')));
G = @(c) gitcmd(ROOT, c);

CODE_PATHS = perimetre_code();      % definition unique, partagee avec run_bypass

meta = struct();
meta.campaign_id  = campaign_id;
meta.smoke        = SMOKE;          % MARQUEUR : un lot smoke n'est jamais publiable
meta.project_root = ROOT;
meta.run_datetime = datestr(now, 'yyyy-mm-dd HH:MM:SS');
meta.run_datenum  = now;

% --- provenance du code --------------------------------------------------
[st, sha] = G('rev-parse HEAD');
meta.code_sha1 = strtrim(sha);
if st ~= 0, meta.code_sha1 = 'INDISPONIBLE'; end

meta.code_scope = strjoin(CODE_PATHS, ' ');

% --- proprete du perimetre de code ---------------------------------------
% D9 (23/09/2026, 3e passe) — DEFAUT DE LA CORRECTION PRECEDENTE.
%
% La version precedente employait --untracked-files=no pour que les artefacts
% de results/ ne rendent pas la campagne sale. Effet de bord non vu : un
% script de mesure JAMAIS COMMITE devenait invisible au controle. Constate sur
% ce depot le 23/09/2026 : les cinq fichiers du dispositif (stamp_campaign,
% verifier_lot_campagne, pct7, run_bypass, analyse_bypass) ET LA FICHE etaient
% non suivis, et le controle rapportait code_dirty = false. La campagne se
% serait lancee en inscrivant un code_sha1 designant un commit ou AUCUN de ces
% fichiers n'existe : exactement le defaut que la regle 1 doit rendre
% impossible.
%
% La regle est desormais DEFINIE UNE SEULE FOIS, dans etat_proprete_code, et
% partagee avec le verrou de reprise de run_bypass. Un controle ecrit deux fois
% est un controle dont on ne corrige jamais que la moitie.
[meta.code_dirty, meta.code_dirty_detail, ...
 meta.code_dirty_modifies, meta.code_dirty_non_suivis] = ...
        etat_proprete_code(ROOT, CODE_PATHS);

if strcmp(meta.code_sha1, 'INDISPONIBLE')
    error('stamp_campaign:git_muet', ...
        ['git n''a pas rendu de HEAD dans %s.\nL''etat du code est INCONNU, ' ...
         'ce qui n''est pas la meme chose que propre.\nAucune campagne ne se ' ...
         'lance ainsi.'], ROOT);
end
if meta.code_dirty
    if SMOKE
        % Le smoke test sert justement a iterer sur le code : on l'autorise
        % sur un arbre non propre, mais le lot reste non publiable (meta.smoke).
        warning('stamp_campaign:dirty_smoke', ...
            ['[SMOKE] Arbre de code non propre :\n%s\nTolere pour un smoke ' ...
             'test, qui n''est de toute facon pas publiable.'], ...
            meta.code_dirty_detail);
    else
        % Sinon : blocage immediat. Inutile de lancer 5 h 30 de mesures qui
        % seront rejetees a l'arrivee.
        error('stamp_campaign:dirty', ...
            ['Perimetre de code non propre : %d fichier(s) suivi(s) modifie(s), ' ...
             '%d fichier(s)\nde code jamais commite(s).\n%s\n' ...
             'Commiter avant de lancer la campagne. La regle 1 impose un ' ...
             'etat versionne AU DEMARRAGE, pas a l''arrivee. Un fichier marque ' ...
             '\n<-- CODE NON VERSIONNE est le cas le plus grave : le code_sha1 ' ...
             'inscrit dans\nles resultats designerait un commit ou ce fichier ' ...
             'n''existe pas.'], ...
            numel(meta.code_dirty_modifies), ...
            numel(meta.code_dirty_non_suivis), ...
            meta.code_dirty_detail);
    end
end

% --- la fiche de campagne est-elle commitee et intacte ? -----------------
fiche_rel = ['docs/campagnes/' campaign_id '.yaml'];
meta.fiche_path = fiche_rel;
meta.fiche_exists = isfile(fullfile(ROOT, fiche_rel));
if meta.fiche_exists
    [st, o] = G(['log -1 --format=%H -- "' fiche_rel '"']);
    meta.fiche_commit = strtrim(o);
    meta.fiche_committed = (st == 0) && ~isempty(meta.fiche_commit);
    [st, o] = G(['status --porcelain -- "' fiche_rel '"']);
    meta.fiche_dirty = (st == 0) && ~isempty(strtrim(o));
else
    meta.fiche_commit = ''; meta.fiche_committed = false; meta.fiche_dirty = true;
end
if ~meta.fiche_exists || ~meta.fiche_committed || meta.fiche_dirty
    error('stamp_campaign:fiche', ...
        ['La fiche %s doit exister, etre commitee et non modifiee AVANT le ' ...
         'lancement.\nRegle 1 : un protocole non versionne ne produit aucun ' ...
         'chiffre publiable.'], fiche_rel);
end

% --- provenance du script appelant ---------------------------------------
%
% LE CHEMIN SEUL NE SUFFIT PAS — decision du 23/09/2026.
%
% Le depot contient run_sensitivity_maxiter.m en DEUX exemplaires, a la racine
% et dans piste_B_nominal_correction. Un registre qui ne porte que le nom du
% script ne dit donc pas lequel a tourne, et l'audit ne peut pas trancher : il
% n'a pas le droit de choisir la copie sur la proximite du chemin ou la
% ressemblance du contenu. Le seul enregistrement qui tranche est l'EMPREINTE du
% fichier reellement execute, prise au moment du run.
stk = dbstack('-completenames');
if numel(stk) >= 2
    meta.script = stk(2).file; meta.script_line = stk(2).line;
else
    meta.script = 'console'; meta.script_line = 0;
end

meta.working_directory     = pwd;
meta.script_path_effective = meta.script;      % chemin ABSOLU reellement execute
meta.script_sha256         = 'SANS OBJET (console)';
meta.script_commit         = '';
meta.script_suivi          = false;
meta.script_dirty          = true;
meta.script_homonymes      = {};

if ~strcmp(meta.script, 'console')
    meta.script_sha256 = sha256_fichier(meta.script);
    if strcmp(meta.script_sha256, 'INDISPONIBLE')
        error('stamp_campaign:script_illisible', ...
            ['Empreinte du script appelant illisible (%s).\nSans empreinte du ' ...
             'code execute, la regle 1 n''est pas satisfaite.'], meta.script);
    end

    % chemin relatif a la racine, pour interroger git
    rel = meta.script;
    if startsWith(rel, ROOT), rel = rel(numel(ROOT)+2:end); end
    rel = strrep(rel, filesep, '/');
    meta.script_rel = rel;

    [~, o] = G(['ls-files -- "' rel '"']);
    meta.script_suivi = ~isempty(strtrim(o));
    if meta.script_suivi
        [~, o] = G(['log -1 --format=%H -- "' rel '"']);
        meta.script_commit = strtrim(o);
        [~, o] = G(['diff --name-only HEAD -- "' rel '"']);
        meta.script_dirty = ~isempty(strtrim(o));
    end

    % --- refus des homonymes ---------------------------------------------
    % Plusieurs fichiers de meme nom dans le depot rendent le registre
    % ambigu meme si l'empreinte leve l'ambiguite techniquement : un lecteur
    % du registre ne saurait pas de quel fichier on parle.
    [~, base, ext] = fileparts(meta.script);
    [~, o] = G(['ls-files -- "*' base ext '"']);
    cand = {};
    if ~isempty(strtrim(o))
        parts = strsplit(strtrim(strrep(char(o), char(13), '')), char(10));
        for i = 1:numel(parts)
            p = strtrim(parts{i});
            [~, b2, e2] = fileparts(p);
            if strcmp([b2 e2], [base ext]), cand{end+1} = p; end %#ok<AGROW>
        end
    end
    meta.script_homonymes = cand;
    if numel(cand) > 1
        msg = sprintf(['%d fichiers suivis portent le nom %s :\n  %s\n' ...
                       'Le registre ne pourrait pas dire lequel a produit les ' ...
                       'chiffres.\nRenommer, ou supprimer la copie inutile, ' ...
                       'avant de lancer la campagne.'], ...
                      numel(cand), [base ext], strjoin(cand, sprintf('\n  ')));
        if SMOKE
            warning('stamp_campaign:homonymes_smoke', '[SMOKE] %s', msg);
        else
            error('stamp_campaign:homonymes', '%s', msg);
        end
    end
end

% --- empreinte de TOUT le code du perimetre, prise MAINTENANT ------------
% Ce que git ne peut pas etablir apres coup : qu'aucune modification locale n'a
% ete faite puis annulee entre le run et l'etat actuel du depot. L'information
% n'existe que si on la prend au moment de l'execution. C'est ici qu'on la prend.
E = empreinte_code(ROOT);
meta.code_manifeste      = E.manifeste;
meta.code_manifeste_sha  = E.digest;
meta.code_manifeste_n    = E.n_fichiers;
meta.code_manifeste_date = E.horodatage;
if ~isempty(E.incomplet)
    msg = sprintf(['Empreinte incomplete : %d fichier(s) du perimetre ' ...
                   'illisible(s) :\n  %s'], numel(E.incomplet), ...
                  strjoin(E.incomplet, sprintf('\n  ')));
    if SMOKE
        warning('stamp_campaign:empreinte_smoke', '[SMOKE] %s', msg);
    else
        error('stamp_campaign:empreinte', ...
            ['%s\nUn digest calcule sur une liste incomplete affirmerait plus ' ...
             'que ce qui a ete mesure.'], msg);
    end
end

% --- environnement --------------------------------------------------------
meta.matlab_release = version('-release');           % ex. '2024a'
meta.matlab_version = version;                       % ex. '24.1.0.2537033 (R2024a)'
meta.matlab_numver  = regexp(meta.matlab_version, '^\d+(\.\d+)+', 'match', 'once');
tb = ver;
keep = {'MATLAB','Optimization Toolbox','Model Predictive Control Toolbox', ...
        'Deep Learning Toolbox','Statistics and Machine Learning Toolbox'};
meta.toolboxes = struct();
noms_tb = {tb.Name};
for i = 1:numel(tb)
    if any(strcmp(tb(i).Name, keep))
        meta.toolboxes.(matlab.lang.makeValidName(tb(i).Name)) = ...
            [tb(i).Version ' ' tb(i).Release];
    end
end
meta.toolboxes_manquantes = keep(~ismember(keep, noms_tb));
meta.computer = computer;
meta.hostname = getenv('COMPUTERNAME');
if isempty(meta.hostname), meta.hostname = getenv('HOSTNAME'); end

% --- protocole fourni par l'appelant -------------------------------------
REQUIS = {'Np','Nc','seed','T_sim','is_continuous_time', ...
          'ConstraintTolerance','MaxIterations','n_repetitions','statistic'};
manquants = REQUIS(~isfield(extra, REQUIS));
if ~isempty(manquants)
    error('stamp_campaign:incomplet', ...
        ['Champs de protocole manquants : %s\nLa regle 1 impose un protocole ' ...
         'complet. Aucun resultat ne doit etre sauve sans ces champs.'], ...
        strjoin(manquants, ', '));
end
f = fieldnames(extra);
for i = 1:numel(f), meta.(f{i}) = extra.(f{i}); end

% --- trace console (D1 : plus de multiplication de chaine) ---------------
tag_sale  = ''; if meta.code_dirty, tag_sale  = ' (CODE SALE)'; end
tag_smoke = ''; if SMOKE,           tag_smoke = ' [SMOKE]';     end
fprintf('[stamp]%s %s%s | %s | git %s | MATLAB %s | fiche %s\n', ...
    tag_smoke, meta.campaign_id, tag_sale, meta.run_datetime, ...
    court(meta.code_sha1), meta.matlab_release, court(meta.fiche_commit));
fprintf('[stamp] script %s | sha %s | empreinte perimetre %s (%d fichiers)\n', ...
    nom_court(meta.script_path_effective), court(meta.script_sha256), ...
    court(meta.code_manifeste_sha), meta.code_manifeste_n);
end


% =========================================================================
function [st, out] = gitcmd(root, args)
%GITCMD  git execute dans la racine du projet, quel que soit le dossier courant.
[st, out] = system(['git -C "' root '" ' args]);
end

function s = court(h)
if isempty(h), s = '(vide)'; else, s = h(1:min(8,numel(h))); end
end

function s = nom_court(p)
[~, b, e] = fileparts(p);
s = [b e];
if isempty(s), s = p; end
end

