function x_next = wt_step(x, u, V, p, dt)
% WT_STEP  One Euler integration step of the 2-state wind turbine model
%
%   x_next = wt_step(x, u, V, p, dt)
%
%   Simulates one discrete time step of the NREL 5-MW wind turbine using
%   Euler forward integration. This function serves as the PLANT (ground
%   truth) in closed-loop simulations. It is NEVER replaced by a surrogate.
%
%   STATE VECTOR
%     x(1) = omega_r   rotor angular speed [rad/s]
%     x(2) = beta      collective pitch angle [deg]
%
%   INPUT
%     u    = beta_cmd   pitch angle command [deg]
%
%   DISTURBANCE
%     V    = V_wind     hub-height wind speed [m/s]
%
%   PARAMETERS
%     p    = get_wt_params()   turbine parameter struct
%     dt   = sample time [s]
%
%   MODEL ASSUMPTIONS — REGION II/III GENERATOR TORQUE SWITCHING
%     Region II  (omega < omega_rated) : Tg = K_opt * omega^2
%       Tracks the optimal tip-speed ratio torque curve, allowing the
%       generator torque to decrease with rotor speed. This creates a
%       torque margin (Ta_max - Tg > 0) across the full sub-rated speed
%       range, preventing the irrecoverable low-speed trap that occurs
%       with a constant Tg model (see Stage 3 diagnostic: at omega_min,
%       Ta_max(omega) < Tg_rated for ALL pitch angles when Tg is constant).
%     Region III (omega >= omega_rated): Tg = Tg_rated (constant)
%       Standard above-rated operation; pitch regulates speed.
%     Transition is a hard switch at omega_rated. K_opt is calibrated so
%     that Tg(omega_rated) from BOTH laws are consistent within ~2%
%     (verified: ratio = 1.0215, using Cp at the actual Jonkman operating
%     point lambda_rated = R*omega_rated/V_rated = 7.00, not the
%     theoretical Cp_max point lambda_opt = 8.11, which would give a much
%     larger 30% discontinuity).
%
%     - 1-mass rotor model (no drivetrain flexibility)
%     - 1st-order pitch actuator: dbeta/dt = (u - beta) / tau_beta
%     - Pitch rate limited to +/- dbeta_max [deg/s]
%
%   EQUATIONS
%     Aerodynamic torque : Ta = 0.5 * rho * A * Cp * V^3 / omega_r
%     Generator torque   : Tg = K_opt*omega^2          (Region II)
%                           Tg = Tg_rated               (Region III)
%     Rotor dynamics      : J * domega/dt = Ta - N_gear*Tg - Br*omega_r
%     Pitch actuator      : tau_beta * dbeta/dt = u - beta
%
%   REFERENCE
%     Jonkman, J. et al. (2009). NREL/TP-500-38060.
%     Bianchi, F.D. et al. (2006). Wind Turbine Control Systems.
%     Pao, L.Y. & Johnson, K.E. (2009). A tutorial on the dynamics and
%       control of wind turbines and wind farms. ACC.
%
%   SEE ALSO
%     cp_lambda_beta, get_wt_params, stage0_config

% ── Input guards ──────────────────────────────────────────────────────────────
omega = max(p.omega_min, x(1));        % prevent division by zero in Ta
beta  = max(p.beta_cp_min, ...
            min(p.beta_cp_max, x(2))); % keep within Cp calibration domain
V     = max(0.5, V);                   % minimum wind speed guard [m/s]

% ── Tip-speed ratio ───────────────────────────────────────────────────────────
lambda = p.R * omega / V;
% cp_lambda_beta clamps lambda internally; no need to clamp here

% ── Aerodynamic power coefficient ─────────────────────────────────────────────
Cp = cp_lambda_beta(lambda, beta);     % clamped to [0, Betz_limit] internally

% ── Aerodynamic torque [N.m] ──────────────────────────────────────────────────
%    Ta = P_aero / omega = (0.5 * rho * A * Cp * V^3) / omega
Ta = 0.5 * p.rho * p.A_rotor * Cp * V^3 / omega;

% ── Generator torque on low-speed shaft [N.m] — Region II/III switching ──────
if omega < p.omega_r
    % Region II: quadratic torque law tracks optimal TSR curve.
    % K_opt*omega^2 is the LOW-SPEED-SHAFT (rotor-side) torque directly,
    % since K_opt is derived from rotor aerodynamics (Ta = 0.5*rho*A*Cp*R^3
    % *omega^2/lambda^3). It must NOT be multiplied by N_gear again — unlike
    % Tg_rated, which is defined GENERATOR-side (HSS) in get_wt_params.m
    % and therefore requires the N_gear factor to convert to LSS.
    Tg_lss = p.K_opt * omega^2;
else
    % Region III: constant rated torque, converted from generator-side
    % (HSS) to rotor-side (LSS) via the gearbox ratio.
    Tg_lss = p.N_gear * p.Tg_rated;
end

% ── Rotor angular acceleration [rad/s^2] ──────────────────────────────────────
domega_dt = (Ta - Tg_lss - p.Br * omega) / p.J;

% ── Pitch actuator: 1st-order ODE [deg/s] ────────────────────────────────────
%    dbeta/dt = (u - beta) / tau_beta,  saturated at +/- dbeta_max
dbeta_dt = (u - beta) / p.tau_beta;
dbeta_dt = max(-p.dbeta_max, min(p.dbeta_max, dbeta_dt));

% ── Euler forward integration ─────────────────────────────────────────────────
x_next = [omega + domega_dt * dt;
          beta  + dbeta_dt  * dt];

% ── State limits ──────────────────────────────────────────────────────────────
x_next(1) = max(p.omega_min, min(p.omega_max,    x_next(1)));
x_next(2) = max(p.beta_cp_min, min(p.beta_cp_max, x_next(2)));

end