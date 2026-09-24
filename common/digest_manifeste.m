function h = digest_manifeste(man)
%DIGEST_MANIFESTE  Le digest d'un manifeste de code. Definition unique.
%
%   h = digest_manifeste(man)   man : cellule Nx2 {chemin_relatif, sha256}
%
%   POURQUOI CETTE FONCTION EXISTE SEPAREMENT
%
%   empreinte_code la calcule au moment du run ; verifier_lot_campagne doit la
%   RECALCULER a la verification, pour controler qu'un manifeste n'a pas ete
%   retouche apres coup sans que son digest suive. Si les deux cotes calculaient
%   le digest chacun a sa facon, le controle ne prouverait rien : il comparerait
%   deux conventions, pas deux etats.
%
%   La convention est donc figee ici, et elle est la seule :
%     . les entrees sont triees par chemin relatif
%     . les separateurs sont des barres obliques, pour que le digest soit
%       identique sous Windows et sous Linux
%     . une ligne vaut « <sha>  <chemin> », deux espaces, comme sha256sum
%     . les lignes sont jointes par des sauts de ligne simples, sans final
%
%   Renvoie 'INDISPONIBLE' si le manifeste est vide ou contient une empreinte
%   indisponible : un digest calcule sur une liste incomplete affirmerait plus
%   que ce qui a ete mesure.

h = 'INDISPONIBLE';
if isempty(man) || size(man, 2) ~= 2, return; end

n = size(man, 1);
for i = 1:n
    if isempty(man{i,2}) || strcmp(man{i,2}, 'INDISPONIBLE'), return; end
end

chemins = strrep(man(:,1), '\', '/');
[chemins, ordre] = sort(chemins);
shas = man(ordre, 2);

lignes = cell(n, 1);
for i = 1:n
    lignes{i} = sprintf('%s  %s', shas{i}, chemins{i});
end
txt = strjoin(lignes, char(10));

try
    d = java.security.MessageDigest.getInstance('SHA-256');
    hb = typecast(d.digest(uint8(txt)), 'uint8');
    h = lower(reshape(dec2hex(hb, 2)', 1, []));
catch
    h = 'INDISPONIBLE';
end
end
