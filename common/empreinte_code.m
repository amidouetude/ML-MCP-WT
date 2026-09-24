function E = empreinte_code(root)
%EMPREINTE_CODE  Empreinte de TOUT le code du perimetre, prise AU MOMENT DU RUN.
%
%   E = empreinte_code(root)
%
%   E.manifeste   cellule Nx2 : {chemin_relatif, sha256}
%   E.digest      SHA-256 du manifeste lui-meme — un seul nombre qui resume
%                 l'etat exact de tout le code du perimetre
%   E.n_fichiers  nombre de fichiers empreintes
%   E.horodatage  quand l'empreinte a ete prise
%
%   CE QUE CECI REPARE, ET QUE GIT NE PEUT PAS REPARER — 23/09/2026
%
%   Git etablit qu'un script existait dans un commit anterieur a un resultat,
%   que le fichier actuel est identique a ce commit, et qu'aucun commit ulterieur
%   ne l'a modifie. Git n'etablit PAS qu'aucune modification locale n'a ete faite
%   puis annulee entre le run et l'etat actuel. Cette possibilite ne peut pas
%   etre demontree impossible a partir du depot seul : l'information n'y est pas.
%
%   Elle ne peut etre etablie que d'une facon : enregistrer l'empreinte du code
%   AU MOMENT DE L'EXECUTION. C'est ce que fait cette fonction, et c'est pourquoi
%   les campagnes futures n'auront pas la reserve documentaire qui pese sur
%   tab:isolated_benchmark — non parce que ce tableau serait douteux, mais parce
%   que la preuve qui lui manque ne pouvait pas etre produite apres coup.
%
%   Le digest porte sur TOUT le perimetre, pas seulement sur le script d'entree.
%   Une campagne depend de ses dependances autant que de son point d'entree : un
%   sf_*.m modifie change le resultat sans toucher au script appele.
%
%   Le manifeste complet est destine a etre sauve AVEC les resultats. Un audit
%   ulterieur peut alors le rejouer fichier par fichier et dire exactement
%   lequel a change, au lieu de constater qu'un digest global differe.

E = struct('manifeste', {{}}, 'digest', 'INDISPONIBLE', 'n_fichiers', 0, ...
           'horodatage', datestr(now, 'yyyy-mm-dd HH:MM:SS'), 'incomplet', {{}});

[~, ext_code, dossiers] = perimetre_code();

fichiers = {};

% --- code des dossiers surveilles, recursivement --------------------------
for i = 1:numel(dossiers)
    base = fullfile(root, strrep(dossiers{i}, '/', filesep));
    if ~isfolder(base), continue; end
    for j = 1:numel(ext_code)
        d = dir(fullfile(base, '**', ['*' ext_code{j}]));
        for k = 1:numel(d)
            if d(k).isdir, continue; end
            p = fullfile(d(k).folder, d(k).name);
            % exclure ce que les campagnes ecrivent, ou qu'il se trouve
            if contains(p, [filesep 'results' filesep]), continue; end
            fichiers{end+1} = p; %#ok<AGROW>
        end
    end
end

% --- code de la RACINE, non recursif (cf. perimetre_code) -----------------
for j = 1:numel(ext_code)
    d = dir(fullfile(root, ['*' ext_code{j}]));
    for k = 1:numel(d)
        if d(k).isdir, continue; end
        fichiers{end+1} = fullfile(root, d(k).name); %#ok<AGROW>
    end
end

fichiers = unique(fichiers);

% --- empreintes, triees par chemin relatif pour etre reproductibles -------
n = numel(fichiers);
rel = cell(n, 1);
for i = 1:n
    r = fichiers{i};
    if startsWith(r, root), r = r(numel(root)+2:end); end
    rel{i} = strrep(r, filesep, '/');       % separateur normalise : le digest
end                                          % doit etre identique sous Windows
[rel, ordre] = sort(rel);                     % et sous Linux
fichiers = fichiers(ordre);

man = cell(n, 2);
incomplet = {};
for i = 1:n
    h = sha256_fichier(fichiers{i});
    man{i,1} = rel{i};
    man{i,2} = h;
    if strcmp(h, 'INDISPONIBLE')
        incomplet{end+1} = rel{i}; %#ok<AGROW>
    end
end

E.manifeste  = man;
E.n_fichiers = n;
E.incomplet  = incomplet;

% --- digest du manifeste --------------------------------------------------
% La convention de calcul vit dans digest_manifeste, et nulle part ailleurs :
% verifier_lot_campagne doit pouvoir le RECALCULER a la verification pour
% detecter un manifeste retouche apres coup. Deux calculs separes compareraient
% deux conventions, pas deux etats.
E.digest = digest_manifeste(man);
end
