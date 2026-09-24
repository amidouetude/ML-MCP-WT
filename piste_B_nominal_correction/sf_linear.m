function xnext = sf_linear(x, u, V, mdl)
%SF_LINEAR  Modele ARX lineaire : x(k+1) = theta'' * [omega; beta; V; u; 1].
%  theta est [5 x 2], regresseurs dans l'ordre [omega, beta, V, u, 1],
%  conformement a common/stage2_train_baselines.m.
phi = [x(1); x(2); V; u(1); 1];
xnext = (mdl.theta.' * phi);
xnext = xnext(:);
end
