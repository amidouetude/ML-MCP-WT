function xnext = sf_gp(x, u, V, mdl, omega_ref, kappa, Q, Q2, R)
% SF_GP  State function for GP-MPC
%
%   xnext = sf_gp(x, u, V, mdl, omega_ref, kappa, Q, Q2, R)
%
%   nlmpc calls: sf_gp(x, u, p1, p2, p3, p4, p5, p6, p7)
%     p1 = V          wind speed [m/s]
%     p2 = mdl        trained GP model struct from stage2_train_gp
%     p3 = omega_ref  rated speed reference [rad/s]  (used by cost_gp only)
%     p4 = kappa      uncertainty penalty weight      (used by cost_gp only)
%     p5 = Q          omega tracking weight           (used by cost_gp only) [ADDED]
%     p6 = Q2         beta regulation weight          (used by cost_gp only) [ADDED]
%     p7 = R          pitch rate weight               (used by cost_gp only) [ADDED]
%
%   NumberOfParameters = 7 [UPDATED — reproducibility review, P0.1]
%     Was 4 before Q/Q2/R were added as explicit parameters to
%     cost_gp.m (removing its previously hardcoded weights). Since
%     nlmpc requires StateFcn and CustomCostFcn to share the same
%     NumberOfParameters, this file's signature grew to match, even
%     though Q/Q2/R (like omega_ref/kappa before them) are entirely
%     unused here — only V and mdl are used by the state function
%     itself.
%
%   CANONICAL LOCATION: common/ ONLY. Do not create a copy of this
%   file in piste_B_nominal_correction/ or elsewhere -- a duplicate
%   there previously caused a silent path-shadowing bug (an outdated
%   copy was picked up instead of this one); see docs/experiment_log.md.

feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;

omega_next = predict(mdl.gp_o, featn);
beta_next  = predict(mdl.gp_b, featn);

xnext = [omega_next; beta_next];
end
