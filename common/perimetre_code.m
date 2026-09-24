function [pathspecs, ext_code, dossiers] = perimetre_code()
%PERIMETRE_CODE  Le code dont la version doit etre etablie. Definition unique.
%
%   [pathspecs, ext_code, dossiers] = perimetre_code()
%
%   pathspecs  a passer a git, dossiers surveilles + fichiers de code de la RACINE
%   ext_code   les extensions qui comptent comme du code
%   dossiers   les dossiers seuls, pour affichage
%
%   Le perimetre surveille par la regle 1. Il vit ici et nulle part ailleurs :
%   stamp_campaign l'emploie au demarrage, run_bypass a la reprise, et la
%   reprise compare CE perimetre a celui inscrit dans le .mat.
%
%   LA RACINE EST INCLUSE — decision du 23/09/2026
%
%   La premiere version ne surveillait que des dossiers. Or run_all.m,
%   run_stage1.m a run_stage6.m et run_sensitivity_maxiter.m vivent a la RACINE
%   du depot et produisent des resultats. Ils etaient donc hors controle. Ils se
%   trouvaient tous suivis et non modifies au moment du constat, donc rien
%   n'etait masque — mais une modification y aurait ete invisible.
%
%   La racine n'est PAS surveillee indistinctement : le pathspec ':(glob)*.m'
%   ne descend pas dans les sous-dossiers (c'est l'effet de la magie « glob » :
%   * n'y traverse pas les separateurs) et ne saisit que les extensions de code.
%   Les .mat, .slxc et .txt de la racine restent donc dehors, conformement au
%   principe : le critere est la NATURE du fichier, pas son dossier.
%
%   Verifie sur ce depot le 23/09/2026 : ':(glob)*.m' rend les 8 scripts de la
%   racine et rien d'autre ; le meme motif sans la magie glob en rendait 95,
%   tout l'arbre.
%
%   CE QUI RESTE DEHORS, et pourquoi
%     results/, */results/   artefacts produits par les campagnes
%     figures/               sorties graphiques
%     paper/, Msc_Thesis/    redaction
%     docs/                  notes de travail — SAUF docs/campagnes (les fiches)
%     Claude outputs/        notes de travail
%
%   Ajouter un dossier ici est une decision de protocole : elle bloque les
%   campagnes jusqu'a ce que tout code non commite qui s'y trouve soit versionne.
%   C'est l'effet recherche.

dossiers = { 'common', ...
             'piste_B_nominal_correction', ...
             'piste_A_rom_autoencoder', ...
             'benchmarks', ...
             'docs/campagnes' };

ext_code = {'.m', '.mlx', '.py', '.yaml', '.yml'};

pathspecs = dossiers;
for i = 1:numel(ext_code)
    pathspecs{end+1} = [':(glob)*' ext_code{i}];   %#ok<AGROW> % racine seulement
end
end
