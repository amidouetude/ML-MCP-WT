function [dirty, detail, modifies, non_suivis, eol_divergents] = ...
                                        etat_proprete_code(root, pathspecs)
%ETAT_PROPRETE_CODE  Le code du perimetre est-il entierement versionne ?
%
%   [dirty, detail, modifies, non_suivis] = etat_proprete_code(root, pathspecs)
%
%   pathspecs est facultatif : par defaut, celui de perimetre_code().
%
%   UNE SEULE DEFINITION DE « PROPRE », PARTAGEE PAR TOUS LES CONTROLES.
%
%   Cette fonction existe a cause du defaut D9 du 23/09/2026. Le controle de
%   propreté était écrit DEUX FOIS — une fois dans stamp_campaign (au
%   démarrage), une fois dans run_bypass (à la reprise). Les deux employaient
%   --untracked-files=no, et les deux étaient donc aveugles au même endroit.
%   Un contrôle dupliqué est un contrôle dont on ne corrige jamais que la
%   moitié : la règle vit ici, et nulle part ailleurs.
%
%   CE QUI REND LE PERIMETRE SALE
%     1. un fichier SUIVI par git et modifié ;
%     2. un fichier de CODE jamais commité (extensions de perimetre_code) ;
%     3. un fichier de CODE dont les octets du DISQUE diffèrent des octets de
%        l'INDEX par les fins de ligne (défaut D10, 25/09/2026).
%
%   POURQUOI LA TROISIEME — elle n'est pas redondante avec la premiere
%
%   Ce qui est MESURE sur ce depot le 25/09/2026, et non deduit :
%
%     core.autocrlf = true en config LOCALE, aucun .gitattributes.
%     Sur les 129 fichiers suivis du perimetre, `git ls-files --eol` donnait
%       i/lf   w/lf     100    ecrits en LF, JAMAIS re-checkoutes
%       i/lf   w/crlf     3    deja divergents
%       i/-text w/-text  22    binaires
%       i/none w/none     4
%     et pour CHACUN des cinq divergents du depot, `git status` ne le
%     signalait PAS — verifie un par un.
%     Pourtant, sur common/digest_manifeste_reference.py :
%       sha256 du disque (CRLF) e3c91f01edbb3c7a8061f7de5f0ceb75192a3585c39c9489fc347ccdf6e247ca
%       sha256 de l'index (LF)  da3e6120082d367d1022346aadd4749c94b5eb2bee567118b1fc09a33e735984
%
%   La proprete au sens de git et la reproductibilite de l'empreinte se
%   separent donc. sha256_fichier lit les octets du DISQUE ; le digest
%   enregistre identifie alors une COPIE DE TRAVAIL et non le contenu du
%   depot, et un tiers qui reclone ne le reproduit pas — or c'est exactement
%   le maillon que l'empreinte doit fournir. Les 100 fichiers « i/lf w/lf »
%   auraient bascule en CRLF au premier clone frais sous Windows.
%
%   JE NE PRETENDS PAS EXPLIQUER LE SILENCE DE GIT. Avec le .gitattributes
%   installe le 25/09 et le fichier reconverti en CRLF au niveau OCTET, le
%   meme `git status` le signale « M ». Le silence initial venait donc
%   vraisemblablement du cache stat de l'index et non d'une normalisation,
%   mais je ne l'ai pas etabli. Ce qui est etabli est le fait : git s'est tu
%   sur cinq fichiers dont l'empreinte disque ne valait pas celle de l'index.
%   Le controle ci-dessous ne repose donc PAS sur `git status`, qui peut se
%   taire pour des raisons de cache, mais sur `git ls-files --eol`, qui lit
%   les deux cotes directement. Un seul appel. Tout ecart entre i/ et w/, et
%   tout w/mixed, est bloquant ; les binaires (-text) et les vides (none)
%   sont hors sujet.
%
%   Ce controle a ete verifie POSITIVEMENT, pas seulement vu a zero :
%   common/digest_manifeste_reference.py reconverti en CRLF octet par octet
%   (sha e3c91f01..., soit exactement l'ancienne version) est ressorti
%   « !! index=lf disque=crlf », puis restaure a l'identique.
%
%   CE QUI NE LE REND PAS SALE
%     tout artefact produit par une campagne — .mat, .txt, .csv, .slxc, figures —
%     où qu'il soit écrit, y compris dans un results/ imbriqué au milieu du
%     code. Le critère est la NATURE du fichier, pas son dossier.

if nargin < 2 || isempty(pathspecs)
    pathspecs = perimetre_code();
end
[~, ext_code] = perimetre_code();

% chaque pathspec est cite separement : ':(glob)*.m' contient des parentheses,
% que le shell interpreterait.
spec = strjoin(cellfun(@(p) ['"' p '"'], pathspecs, 'UniformOutput', false), ' ');

[st1, mod_txt]  = system(['git -C "' root '" status --porcelain ' ...
                          '--untracked-files=no -- ' spec]);
[st2, tout_txt] = system(['git -C "' root '" status --porcelain ' ...
                          '--untracked-files=all -- ' spec]);
[st3, eol_txt]  = system(['git -C "' root '" ls-files --eol -- ' spec]);

if st1 ~= 0 || st2 ~= 0 || st3 ~= 0
    % « Je n'ai pas pu verifier » n'est pas « c'est propre ». Le seul
    % comportement acceptable est de le dire, pas de repondre false.
    error('etat_proprete_code:git_muet', ...
        ['git n''a pas repondu dans %s (codes %d, %d et %d).\n' ...
         'L''etat du code est INCONNU. Aucune campagne ne se lance ainsi.'], ...
        root, st1, st2, st3);
end

modifies   = lignes_non_vides(mod_txt);
non_suivis = {};
brutes = lignes_non_vides(tout_txt);
for k = 1:numel(brutes)
    l = brutes{k};
    if ~startsWith(l, '??'), continue; end
    chemin = strtrim(l(3:end));
    [~, ~, e] = fileparts(chemin);
    if any(strcmpi(e, ext_code))
        non_suivis{end+1} = ['?? ' chemin '   <-- CODE NON VERSIONNE']; %#ok<AGROW>
    end
end

% --- 3. fins de ligne : disque contre index -----------------------------
% Un seul appel git. Format d'une ligne :
%   i/lf<TAB>w/crlf<TAB>attr/<TAB>chemin
% On ne juge que les fichiers de CODE : un .csv ou un .md divergent ne change
% aucune empreinte enregistree par empreinte_code.
% Le chemin est separe par une TABULATION : on ne l'extrait pas a coups de
% \s+, sinon un attribut a espaces (attr/text eol=lf) le ferait deraper.
eol_divergents = {};
eol_lignes = lignes_non_vides(eol_txt);
for k = 1:numel(eol_lignes)
    champs = strsplit(eol_lignes{k}, char(9));
    if numel(champs) < 2, continue; end
    chemin = strtrim(champs{end});
    t = regexp(strtrim(champs{1}), '^i/(\S+)\s+w/(\S+)', 'tokens', 'once');
    if isempty(t)
        % variante : i/ et w/ dans deux champs tabules distincts
        a = regexp(strtrim(champs{1}), '^i/(\S+)$', 'tokens', 'once');
        b = regexp(strtrim(champs{2}), '^w/(\S+)$', 'tokens', 'once');
        if isempty(a) || isempty(b), continue; end
        t = {a{1}, b{1}};
    end
    idx = t{1}; disque = t{2};
    [~, ~, e] = fileparts(chemin);
    if ~any(strcmpi(e, ext_code)), continue; end
    if any(strcmp(idx, {'-text', 'none'})), continue; end   % binaire, ou vide
    if strcmp(idx, disque) && ~strcmp(disque, 'mixed'), continue; end
    eol_divergents{end+1} = sprintf( ...
        '!! %s   <-- index=%s disque=%s : EMPREINTE NON REPRODUCTIBLE', ...
        chemin, idx, disque); %#ok<AGROW>
end

toutes = [modifies, non_suivis, eol_divergents];
dirty  = ~isempty(toutes);
detail = strjoin(toutes, sprintf('\n'));
end


% =========================================================================
function c = lignes_non_vides(txt)
c = {};
if isempty(txt), return; end
parts = strsplit(strrep(char(txt), char(13), ''), char(10));
for i = 1:numel(parts)
    if ~isempty(strtrim(parts{i})), c{end+1} = strtrim(parts{i}); end %#ok<AGROW>
end
end
