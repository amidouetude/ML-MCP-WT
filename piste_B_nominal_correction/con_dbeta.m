function cineq = con_dbeta(X, U, e, data, varargin) %#ok<INUSD>
%CON_DBETA  Remede A : contraint la variation de l'ETAT de pitch predit,
%  |beta(k+1) - beta(k)| <= dbmax, ce que la contrainte de vitesse sur la
%  commande manipulee ne garantit pas pour un modele appris.
persistent dbmax
if isempty(dbmax)
    pp = get_wt_params(); cc = stage0_config();
    dbmax = pp.dbeta_max * cc.mpc.Ts;
end
d = diff(X(:,2));
cineq = [d - dbmax; -d - dbmax];
end
