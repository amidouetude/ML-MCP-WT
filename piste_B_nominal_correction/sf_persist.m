function xnext = sf_persist(x, u, V, mdl) %#ok<INUSD>
%SF_PERSIST  Modele de persistance : x(k+1) = x(k).
%  Aucune dependance en u : le gain du canal de commande est exactement 0.
%  Signature alignee sur les autres sf_* du projet (x, u, V, mdl).
xnext = x(:);
end
