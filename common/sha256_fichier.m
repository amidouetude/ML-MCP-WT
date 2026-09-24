function h = sha256_fichier(pth)
%SHA256_FICHIER  Empreinte SHA-256 d'un fichier, en minuscules. Definition unique.
%
%   Trois fichiers du dispositif calculaient cette empreinte chacun de son cote,
%   et le defaut D7 — dec2hex sans largeur imposee, qui tronque tout octet
%   inferieur a 16 — n'avait ete corrige que dans l'un d'eux. Un calcul duplique
%   est un calcul dont on ne corrige jamais que la moitie : il vit ici.
%
%   Renvoie 'INDISPONIBLE' si le fichier est illisible. L'appelant doit traiter
%   ce cas : une empreinte indisponible n'est pas une empreinte.

h = 'INDISPONIBLE';
if ~isfile(pth), return; end
try
    d = java.security.MessageDigest.getInstance('SHA-256');
    fid = fopen(pth, 'r');
    if fid < 0, return; end
    b = fread(fid, Inf, '*uint8');
    fclose(fid);
    hb = typecast(d.digest(b), 'uint8');
    % dec2hex(hb, 2) : la largeur 2 est OBLIGATOIRE (defaut D7). Sans elle,
    % l'octet 0x09 sort « 9 » et non « 09 », et toute l'empreinte se decale.
    h = lower(reshape(dec2hex(hb, 2)', 1, []));
catch
    h = 'INDISPONIBLE';
end
end
