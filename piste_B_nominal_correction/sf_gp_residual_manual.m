function xnext = sf_gp_residual_manual(x, u, V, mdl, p, dt)
% SF_GP_RESIDUAL_MANUAL  Nominal + GP-correction state function, with
% the GP posterior mean computed via a HAND-WRITTEN Matern 5/2 kernel
% formula (see extract_gp_weights.m), NEVER calling predict() on the
% RegressionGP objects.
%
%   xnext = sf_gp_residual_manual(x, u, V, mdl, p, dt)
%
%   NumberOfParameters = 4  (V, mdl, p, dt)
%
%   PURPOSE — generalization test. test_residual_manual_closed_loop.m
%   showed that bypassing predict() resolves the SQP-cost catastrophe
%   for a small MLP. This function tests whether the SAME bypass works
%   for a Gaussian Process — a structurally different object type
%   (RegressionGP, not dlnetwork) — to confirm the finding is about
%   predict() in general, not specific to neural-network objects.

x_nominal = wt_step(x, u, V, p, dt);

feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;

corr_o_n = gp_matern52_mean_inline(featn, mdl.Xactive_o, mdl.alpha_o, ...
    mdl.beta0_o, mdl.sigma_f_o, mdl.l_o);
corr_b_n = gp_matern52_mean_inline(featn, mdl.Xactive_b, mdl.alpha_b, ...
    mdl.beta0_b, mdl.sigma_f_b, mdl.l_b);

correction = [corr_o_n, corr_b_n] .* mdl.ysig + mdl.ymu;

xnext = x_nominal + correction(:);

end


function m = gp_matern52_mean_inline(x, Xactive, alpha, beta0, sigma_f, l)
diffs = Xactive - x;
r = sqrt(sum(diffs.^2, 2));
sq5 = sqrt(5);
k = sigma_f^2 .* (1 + sq5*r/l + 5*r.^2/(3*l^2)) .* exp(-sq5*r/l);
m = beta0 + sum(alpha .* k);
end
