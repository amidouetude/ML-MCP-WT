function xnext = sf_gp_hybrid(x, u, V, mdl, oref, kappa, Q, Q2, R)
%SF_GP_HYBRID  Remede B, en version chirurgicale : canal omega du GP,
%  canal beta remplace par la dynamique physique de l'actionneur.
%  Isole le canal de pitch sans reentrainer quoi que ce soit.
%  mdl doit porter le champ dbmax (variation max de beta par pas).
g = sf_gp(x, u, V, mdl, oref, kappa, Q, Q2, R);
db = max(-mdl.dbmax, min(mdl.dbmax, u(1) - x(2)));
xnext = [g(1); x(2) + db];
end
