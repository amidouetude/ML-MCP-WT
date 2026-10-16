function x1 = rom_step_lean(x0, u)
%ROM_STEP_LEAN  Lean copy of the E2 discrete model for nlmpc (no diagnostic structures).
%
%   rom_step_lean('init', p)    store p (output of E2 rom_params with the Cp table) once
%   rom_step_lean('clear')      forget p
%   x1 = rom_step_lean(x0, u)   one sample Ts = p.Ts; x0 = [omega_r; omega_f] (rad/s),
%                               u = [beta_deg; V_hub] (MV first, then MD, as declared in nlmpc)
%
%   Same equations, same operation order and same RK4 as openfast_q1/E2/rom_step.m,
%   rom_rhs.m and rom_torque_law.m (commit b3a6e74), wind variant (i) only
%   (V_rotor = Wind1VelX, the measured disturbance of spec_F controller.wind_to_controller).
%   Bit-for-bit equality with rom_step is established by test_F0_lean_equivalence.m before any
%   closed-loop case (supervisor arbitration of 16/10/2026).
%   Used by: spec_F cases.F2_nmpc_physics.what ("lean wrapper of rom_step").

persistent P
if ischar(x0)
    switch x0
        case 'init'
            P = u;
        case 'clear'
            P = [];
        otherwise
            error('rom_step_lean:mode', 'Unknown mode ''%s''.', x0);
    end
    x1 = [];
    return
end
if isempty(P)
    error('rom_step_lean:init', 'Call rom_step_lean(''init'', p) first.');
end
beta_deg = u(1);
V_hub    = u(2);
h = P.Ts/P.n_sub;                                   % rom_step: h = Ts/p.n_sub
x = x0(:);
for s = 1:P.n_sub                                   % rom_step: RK4, n_sub sub-steps
    k1 = rhs(x,            beta_deg, V_hub, P);
    k2 = rhs(x + 0.5*h*k1, beta_deg, V_hub, P);
    k3 = rhs(x + 0.5*h*k2, beta_deg, V_hub, P);
    k4 = rhs(x + h*k3,     beta_deg, V_hub, P);
    x = x + (h/6)*(k1 + 2*k2 + 2*k3 + k4);
end
x1 = x;
end

% =============================================================================================
function dx = rhs(x, beta_deg, V_hub, p)
% copy of rom_rhs.m (variant 'i') and rom_torque_law.m, same operation order
omega_r = x(1);
omega_f = x(2);
V = V_hub;                                          % variant (i)
guard = V < p.V_guard;                              % numerical guard
if guard
    V = p.V_guard;
end
lambda = omega_r*p.R/V;
Cp     = p.Cp(lambda, beta_deg);
Q_aero = 0.5*p.rho*p.A*p.R*V^2*Cp/lambda;
if (omega_f >= p.VS_RtGnSp) || (beta_deg*pi/180 >= p.VS_Rgn3MP)
    Qg = p.VS_RtPwr/omega_f;
elseif omega_f <= p.VS_CtInSp
    Qg = 0;
elseif omega_f < p.VS_Rgn2Sp
    Qg = p.VS_Slope15*(omega_f - p.VS_CtInSp);
elseif omega_f < p.VS_TrGnSp
    Qg = p.VS_Rgn2K*omega_f*omega_f;
else
    Qg = p.VS_Slope25*(omega_f - p.VS_SySp);
end
Qg = min(Qg, p.VS_MaxTq);
dx = [(Q_aero - p.N*Qg)/p.J;
      p.CornerFreq*(p.N*omega_r - omega_f)];
end
