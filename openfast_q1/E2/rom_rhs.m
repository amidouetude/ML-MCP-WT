function [dx, info] = rom_rhs(x, beta_deg, V_hub, variant, p)
%ROM_RHS  Continuous-time right-hand side of the E2 reduced-order physics model.
%
%   [dx, info] = rom_rhs(x, beta_deg, V_hub, variant, p)
%
%   x         [omega_r; omega_f]: rotor speed (rad/s, LSS) and filtered generator speed
%             (rad/s, HSS)                                              spec l.25-30
%   beta_deg  collective pitch command (deg), no actuator state         spec l.32-35
%   V_hub     wind speed V (m/s): rotor-effective wind RtVAvgxh of AeroDyn, model v2
%             (spec_E2 amendment 7); model v1 used the hub-height wind Wind1VelX (historical)
%   variant   'i'  : V_rotor = V_hub (model v2)                         spec l.37
%             'ii' : V_rotor = V_hub*cos(5 deg), historical (model v1)  spec l.37
%   p         parameters from rom_params.m, with the Cp interpolant loaded; optional field
%             p.cp_mode selects the Cp table domain mode (spec_E2 amendment 8,
%             model.cp_interpolant.out_of_domain): absent or 'validation' (default, the path
%             below unchanged), 'nmpc'; any other value is an error
%
%   dx(1) = (Q_aero - N*Q_g)/J                                          spec l.39
%   dx(2) = CornerFreq*(N*omega_r - omega_f)                            spec l.30 (DISCON.F90 l.58)
%   Q_aero = 0.5*rho*A*R*V^2*Cp(lambda,beta)/lambda, lambda = omega_r*R/V   spec l.40
%
%   Validation mode: outside the table domain the interpolant returns NaN (no extrapolation,
%   no clipping, spec l.67): the NaN propagates to dx and info.domain is set.
%   NMPC mode (amendment 8): before p.Cp, lambda is bounded to p.lambda_dom and beta_deg to
%   p.beta_dom by comparisons (v < lo: lo; v > hi: hi); Cp is the interpolant at the bounded
%   point; the actual lambda stays in the division of Q_aero. info.domain_lambda and
%   info.domain_beta are (v < lo) || (v > hi) and info.domain is their logical or. A NaN
%   argument is not bounded and not flagged (every comparison with NaN is false): the
%   interpolant returns NaN, a non-finite value handled by the non_finite rule of
%   spec_E6_solver_O8 (supervisor decision D5 of 03/11/2026). The torque law uses the actual
%   beta_deg in both modes.
%   If V < 0.1 m/s the numerical guard of spec l.68 replaces V by 0.1 m/s and info.guard is set.
%   info: lambda, Cp, Q_aero (N m, LSS), Q_g (N m, HSS), region, sat, domain, guard;
%   in the NMPC mode also domain_lambda and domain_beta.

if isempty(p.Cp)
    error('rom_rhs:noCp', 'The Cp interpolant is not loaded (call rom_params with the table file).');
end
cp_mode = 'validation';                           % amendment 8: default mode
if isfield(p, 'cp_mode')
    cp_mode = p.cp_mode;
end
if ~((ischar(cp_mode) && isrow(cp_mode)) || (isstring(cp_mode) && isscalar(cp_mode))) || ...
        ~any(strcmp(cp_mode, {'validation', 'nmpc'}))
    error('rom_rhs:cpMode', 'p.cp_mode must be ''validation'' or ''nmpc''.');
end
nmpc_mode = strcmp(cp_mode, 'nmpc');
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
if nmpc_mode                                      % amendment 8: NMPC mode
    lambda_b = lambda;                            % decision D5: bounded by comparisons,
    if lambda < p.lambda_dom(1)                   % so that a NaN is not bounded
        lambda_b = p.lambda_dom(1);
    elseif lambda > p.lambda_dom(2)
        lambda_b = p.lambda_dom(2);
    end
    beta_b = beta_deg;
    if beta_deg < p.beta_dom(1)
        beta_b = p.beta_dom(1);
    elseif beta_deg > p.beta_dom(2)
        beta_b = p.beta_dom(2);
    end
    domain_lambda = (lambda < p.lambda_dom(1)) || (lambda > p.lambda_dom(2));
    domain_beta   = (beta_deg < p.beta_dom(1)) || (beta_deg > p.beta_dom(2));
    Cp     = p.Cp(lambda_b, beta_b);
    domain = domain_lambda || domain_beta;
else
    Cp     = p.Cp(lambda, beta_deg);                  % spec l.66-67 (makima, NaN outside)
    domain = isnan(Cp);
end
Q_aero = 0.5*p.rho*p.A*p.R*V^2*Cp/lambda;         % spec l.40

[Q_g, region, sat] = rom_torque_law(omega_f, beta_deg, p);   % spec l.41-50

dx = [(Q_aero - p.N*Q_g)/p.J;                     % spec l.39
      p.CornerFreq*(p.N*omega_r - omega_f)];      % spec l.30

info = struct('lambda', lambda, 'Cp', Cp, 'Q_aero', Q_aero, 'Q_g', Q_g, ...
              'region', region, 'sat', sat, 'domain', domain, 'guard', guard);
if nmpc_mode                                      % amendment 8: separate counts
    info.domain_lambda = domain_lambda;
    info.domain_beta   = domain_beta;
end
end
