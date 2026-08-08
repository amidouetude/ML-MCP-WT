function p = get_wt_params()
% GET_WT_PARAMS  NREL 5-MW reference wind turbine parameters
%
%   p = get_wt_params()
%
%   Returns a struct with all physical parameters of the NREL 5-MW turbine.
%   This function is a thin wrapper that extracts the turbine sub-struct
%   from stage0_config(), ensuring a single source of truth for all
%   parameters across Stage 0 through Stage 3.
%
%   FIELDS RETURNED
%     Rotor geometry  : R, B, rho, A_rotor
%     Drivetrain      : J, Br, N_gear
%     Pitch actuator  : tau_beta, beta_min, beta_max, dbeta_max
%     Operating limits: omega_r, omega_min, omega_max, P_rated,
%                       V_rated, V_cutin, V_cutout
%     Derived         : Tg_rated
%     Cp domain       : lambda_min, lambda_max, beta_cp_min, beta_cp_max
%
%   NOTE ON PITCH LIMITS
%     beta_min = 0 deg  (NOT -5 deg).
%     The Cp polynomial (Jonkman 2009) is calibrated over beta in [0, 25] deg.
%     Using beta < 0 deg produces Cp > Betz limit, which is non-physical.
%
%   REFERENCE
%     Jonkman, J. et al. (2009). Definition of a 5-MW Reference Wind Turbine
%     for Offshore System Development. NREL/TP-500-38060.
%
%   SEE ALSO
%     stage0_config, cp_lambda_beta, wt_step

cfg = stage0_config();
p   = cfg.turbine;

end
