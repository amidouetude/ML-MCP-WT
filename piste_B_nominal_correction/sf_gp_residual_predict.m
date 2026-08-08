function xnext = sf_gp_residual_predict(x, u, V, mdl, p, dt)
% SF_GP_RESIDUAL_PREDICT  Nominal + GP-correction state function using
% MATLAB's predict() on the RegressionGP objects (the "normal" way).
% Comparison baseline for sf_gp_residual_manual.m.
%
%   xnext = sf_gp_residual_predict(x, u, V, mdl, p, dt)
%   NumberOfParameters = 4  (V, mdl, p, dt)

x_nominal = wt_step(x, u, V, p, dt);

feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;

corr_o_n = predict(mdl.gp_o, featn);
corr_b_n = predict(mdl.gp_b, featn);

correction = [corr_o_n, corr_b_n] .* mdl.ysig + mdl.ymu;

xnext = x_nominal + correction(:);

end
