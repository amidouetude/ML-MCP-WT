function A = audit_version_code(root, paires)
%AUDIT_VERSION_CODE  Que peut-on ETABLIR, apres coup, sur le code d'un resultat ?
%
%   A = audit_version_code(root, paires)
%   paires : cellule Nx2, {chemin_script_relatif, chemin_resultat_relatif}
%
%   ===================================================================
%   STATUT DE CET OUTIL — a lire avant de citer sa sortie
%   ===================================================================
%
%   C'est un outil D'EXPLORATION AVANT REGULARISATION. Il n'est PAS une preuve
%   historique. Il repond a une question etroite : « le depot, tel qu'il est
%   aujourd'hui, permet-il de dire quelque chose du code qui a produit ce
%   resultat ? » — et le plus souvent la reponse honnete est « pas grand-chose ».
%
%   Son verdict le plus favorable, ETABLI, porte une reserve documentaire
%   PERMANENTE qui ne peut pas etre levee apres coup : git montre qu'un script
%   existait dans un commit anterieur au resultat, que le fichier actuel est
%   identique a ce commit, et qu'aucun commit ulterieur ne l'a modifie. Git ne
%   montre PAS qu'aucune modification locale n'a ete faite puis annulee entre le
%   run et aujourd'hui. Cette possibilite ne peut pas etre demontree impossible
%   a partir du depot seul : l'information n'y est pas.
%
%   Elle ne peut etre etablie que d'une seule facon — enregistrer l'empreinte du
%   code AU MOMENT DU RUN. C'est le role de empreinte_code, appelee par
%   stamp_campaign. Les campagnes a partir du 23/09/2026 n'auront donc pas cette
%   reserve. Les precedentes l'auront toujours, et aucun outil n'y changera rien.
%
%   Cet outil doit lui-meme etre COMMITE avant d'etre employe comme instrument
%   officiel du dispositif : un audit conduit par un script non versionne ne vaut
%   pas mieux que ce qu'il audite.
%
%   ===================================================================
%   LES QUATRE VERDICTS
%   ===================================================================
%
%   ETABLI
%       script suivi ; copie de travail identique a HEAD ; dernier commit le
%       touchant STRICTEMENT anterieur au resultat ; aucun homonyme dans le
%       depot. Sous la reserve documentaire ci-dessus.
%
%   EXCLU
%       la version presente sur le disque n'est certainement PAS celle qui a
%       tourne : le fichier a ete modifie APRES le resultat. C'est le seul
%       verdict NEGATIF, et le seul que les dates permettent de fonder — une
%       date posterieure refute, une date anterieure ne prouve rien.
%
%   PLAUSIBLE
%       les faits sont compatibles avec la version presente, sans l'etablir. Cas
%       typique : le script a ete commite quelques heures APRES le run (on lance,
%       puis on commite). Vraisemblable, non demontre. Voie de resolution :
%       confronter le protocole inscrit dans l'en-tete de l'artefact aux
%       parametres du script commite — cela peut EXCLURE, jamais prouver.
%
%   INDETERMINABLE
%       rien ne peut etre dit. Script non suivi ; ou suivi mais modifie sans
%       commit ; ou plusieurs homonymes dans le depot. Dans ce dernier cas
%       l'outil REFUSE de choisir : il n'a pas le droit de trancher sur la
%       proximite du chemin ni sur la ressemblance du contenu.

if nargin < 2, error('audit_version_code:usage', 'Fournir root et paires.'); end

A = struct('script', {}, 'resultat', {}, 'verdict', {}, 'categorie', {}, ...
           'commit', {}, 'date_commit', {}, 'date_resultat', {}, ...
           'date_script', {}, 'egal_head', {}, 'homonymes', {});

fprintf(['\n=== AUDIT DE VERSION — outil d''exploration, non preuve ' ...
         'historique ===\n']);
fprintf('depot : %s\n', root);
fprintf('\n%-40s %-9s %-19s %-19s %s\n', ...
        'SCRIPT', 'commit', 'commite le', 'resultat le', 'VERDICT');
fprintf('%s\n', repmat('-', 1, 130));

for i = 1:size(paires, 1)
    s = paires{i,1};
    r = paires{i,2};

    a = struct('script', s, 'resultat', r, 'verdict', '', 'categorie', '', ...
               'commit', '', 'date_commit', '', 'date_resultat', '', ...
               'date_script', '', 'egal_head', false, 'homonymes', {{}});

    % ---- dates disque ---------------------------------------------------
    fr = fullfile(root, strrep(r, '/', filesep));
    fs = fullfile(root, strrep(s, '/', filesep));
    dr_num = NaN; ds_num = NaN;
    if isfile(fr)
        d = dir(fr); dr_num = d.datenum;
        a.date_resultat = datestr(dr_num, 'yyyy-mm-dd HH:MM:SS');
    end
    if isfile(fs)
        d = dir(fs); ds_num = d.datenum;
        a.date_script = datestr(ds_num, 'yyyy-mm-dd HH:MM:SS');
    end

    % ---- homonymes : bloquant avant toute autre consideration -----------
    [~, base, ext] = fileparts(s);
    cand = homonymes(root, [base ext]);
    a.homonymes = cand;

    suivi = ~isempty(g(root, ['ls-files -- "' s '"']));
    if suivi
        a.commit      = g(root, ['log -1 --format=%h -- "' s '"']);
        a.date_commit = g(root, ['log -1 --format=%ad ' ...
                                 '"--date=format:%Y-%m-%d %H:%M:%S" -- "' s '"']);
        a.egal_head   = isempty(g(root, ['diff --name-only HEAD -- "' s '"']));
    end

    % ---- verdict, du plus fort au plus faible ---------------------------
    if numel(cand) > 1
        a.categorie = 'INDETERMINABLE';
        a.verdict = sprintf('INDETERMINABLE - %d homonymes, refus de choisir', ...
                            numel(cand));
    elseif ~isnan(ds_num) && ~isnan(dr_num) && ds_num > dr_num
        % le seul verdict que les dates fondent : elles refutent.
        a.categorie = 'EXCLU';
        a.verdict = 'EXCLU - fichier modifie APRES le resultat';
    elseif ~suivi
        a.categorie = 'INDETERMINABLE';
        a.verdict = 'INDETERMINABLE - script non suivi par git';
    elseif ~a.egal_head
        a.categorie = 'INDETERMINABLE';
        a.verdict = 'INDETERMINABLE - suivi mais modifie sans commit';
    elseif isempty(a.date_resultat)
        a.categorie = 'INDETERMINABLE';
        a.verdict = 'INDETERMINABLE - resultat absent du disque';
    elseif datenum(a.date_commit, 'yyyy-mm-dd HH:MM:SS') < dr_num
        % STRICTEMENT anterieur, a la seconde. Une comparaison a la journee
        % declarait « etabli » un commit fait APRES le run le meme jour : la
        % granularite grossiere fabriquait de fausses chaines (3 sur 4).
        a.categorie = 'ETABLI';
        a.verdict = ['ETABLI : ' a.commit ' (sous reserve documentaire)'];
    else
        a.categorie = 'PLAUSIBLE';
        a.verdict = 'PLAUSIBLE - commit posterieur au run, non etabli';
    end

    nom = s;
    if numel(nom) > 39, nom = ['...' nom(end-35:end)]; end
    dr = a.date_resultat; if isempty(dr), dr = 'absent'; end
    dc = a.date_commit;   if isempty(dc), dc = '-'; end
    cm = a.commit;        if isempty(cm), cm = '-'; end
    fprintf('%-40s %-9s %-19s %-19s %s\n', nom, cm, dc, dr, a.verdict);
    if numel(cand) > 1
        for k = 1:numel(cand)
            fprintf('%-40s    homonyme : %s\n', '', cand{k});
        end
    end

    A(end+1) = a; %#ok<AGROW>
end

cats = {A.categorie};
fprintf('%s\n', repmat('-', 1, 130));
fprintf('  ETABLI %d  |  PLAUSIBLE %d  |  EXCLU %d  |  INDETERMINABLE %d   (sur %d)\n', ...
    sum(strcmp(cats,'ETABLI')), sum(strcmp(cats,'PLAUSIBLE')), ...
    sum(strcmp(cats,'EXCLU')), sum(strcmp(cats,'INDETERMINABLE')), numel(A));
fprintf(['\n  Rappel : ETABLI porte une reserve documentaire permanente — le\n' ...
         '  depot ne peut pas exclure une modification locale faite puis\n' ...
         '  annulee. Seule une empreinte prise AU MOMENT DU RUN le peut.\n']);

% l'outil s'accuse lui-meme s'il n'est pas versionne
moi = 'common/audit_version_code.m';
if isempty(g(root, ['ls-files -- "' moi '"']))
    fprintf(['\n  AVERTISSEMENT : %s n''est pas suivi par git. Cet audit est\n' ...
             '  exploratoire et ne peut pas etre cite comme instrument du ' ...
             'dispositif.\n'], moi);
end
end


% =========================================================================
function out = g(root, args)
[~, o] = system(['git -C "' root '" ' args]);
out = strtrim(o);
end

function cand = homonymes(root, nom)
%HOMONYMES  Tous les fichiers SUIVIS du depot portant exactement ce nom de base.
cand = {};
o = g(root, ['ls-files -- "*' nom '"']);
if isempty(o), return; end
parts = strsplit(strrep(o, char(13), ''), char(10));
for i = 1:numel(parts)
    p = strtrim(parts{i});
    if isempty(p), continue; end
    [~, b, e] = fileparts(p);
    if strcmp([b e], nom), cand{end+1} = p; end %#ok<AGROW>
end
end
