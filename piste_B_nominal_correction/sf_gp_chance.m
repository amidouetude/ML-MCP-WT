function xnext = sf_gp_chance(x, u, V, mdl, cc)
% SF_GP_CHANCE  State function for the chance-constrained GP-MPC test.
%
%   xnext = sf_gp_chance(x, u, V, mdl, cc)
%
%   Thin delegating wrapper around the CANONICAL common/sf_gp.m -- does
%   NOT duplicate its physics (sf_gp.m's own header explicitly warns
%   that a duplicated copy previously caused a silent path-shadowing
%   bug; see docs/experiment_log.md). This wrapper exists only to give
%   the chance-constrained controller its own NumberOfParameters=3
%   signature (V, mdl, cc), matching ineqcon_gp_chance.m, without
%   touching sf_gp.m or its 7-parameter contract used by cost_gp.m.
%
%   cc (struct, unused here -- present only so StateFcn and
%   CustomIneqConFcn share the same NumberOfParameters, exactly the
%   convention sf_gp.m itself already uses for omega_ref/kappa/Q/Q2/R):
%     .z_alpha    quantile z_{1-alpha} of the standard normal
%     .omega_max  upper chance-constrained bound [rad/s]
%     .omega_min  lower chance-constrained bound [rad/s]

xnext = sf_gp(x, u, V, mdl, 0, 0, 0, 0, 0);  % omega_ref/kappa/Q/Q2/R unused by sf_gp.m itself
end
