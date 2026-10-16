function [dx, info] = rom_rhs(x, beta_deg, V_hub, variant, p)
%ROM_RHS  Continuous-time right-hand side of the E2 reduced-order physics model.
%
%   [dx, info] = rom_rhs(x, beta_deg, V_hub, variant, p)
%
%   x         [omega_r; omega_f]: rotor speed (rad/s, LSS) and filtered generator speed
%             (rad/s, HSS)                                              spec l.25-30
%   beta_deg  collective pitch command (deg), no actuator state         spec l.32-35
%   V_hub     hub-height longitudinal wind, OpenFAST channel Wind1VelX (m/s)   spec l.37
%   variant   'i'  : V_rotor = Wind1VelX                                spec l.37
%             'ii' : V_rotor = Wind1VelX*cos(5 deg)                     spec l.37
%   p         parameters from rom_params.m, with the Cp interpolant loaded
%
%   dx(1) = (Q_aero - N*Q_g)/J                                          spec l.39
%   dx(2) = CornerFreq*(N*omega_r - omega_f)                            spec l.30 (DISCON.F90 l.58)
%   Q_aero = 0.5*rho*A*R*V^2*Cp(lambda,beta)/lambda, lambda = omega_r*R/V   spec l.40
%
%   Outside the table domain the interpolant returns NaN (no extrapolation, no clipping,
%   spec l.67): the NaN propagates to dx and info.domain is set. If V < 0.1 m/s the
%   numerical guard of spec l.68 replaces V by 0.1 m/s and info.guard is set.
%   info: lambda, Cp, Q_aero (N m, LSS), Q_g (N m, HSS), region, sat, domain, guard.

if isempty(p.Cp)
    error('rom_rhs:noCp', 'The Cp interpolant is not loaded (call rom_params with the table file).');
end
omega_r = x(1);
omega_f = x(2);

switch variant                                    % spec l.37
    case 'i'
        V = V_hub;
    case 'ii'
        V = V_hub*cosd(p.tilt_deg);
    otherwise
        error('rom_rhs:variant', 'Unknown wind variant ''%s'' (expected ''i'' or ''ii'').', variant);
end
guard = V < p.V_guard;                            % spec l.68
if guard
    V = p.V_guard;
end

lambda = omega_r*p.R/V;                           % spec l.40
Cp     = p.Cp(lambda, beta_deg);                  % spec l.66-67 (makima, NaN outside)
domain = isnan(Cp);
Q_aero = 0.5*p.rho*p.A*p.R*V^2*Cp/lambda;         % spec l.40

[Q_g, region, sat] = rom_torque_law(omega_f, beta_deg, p);   % spec l.41-50

dx = [(Q_aero - p.N*Q_g)/p.J;                     % spec l.39
      p.CornerFreq*(p.N*omega_r - omega_f)];      % spec l.30

info = struct('lambda', lambda, 'Cp', Cp, 'Q_aero', Q_aero, 'Q_g', Q_g, ...
              'region', region, 'sat', sat, 'domain', domain, 'guard', guard);
end
