function [x1, info] = rom_step(x0, beta_deg, V_hub, variant, p, Ts)
%ROM_STEP  Discrete-time E2 model: one sample of length Ts, RK4 with p.n_sub sub-steps.
%
%   [x1, info] = rom_step(x0, beta_deg, V_hub, variant, p)        % Ts = p.Ts (0.05 s)
%   [x1, info] = rom_step(x0, beta_deg, V_hub, variant, p, Ts)
%
%   Discrete-time form supplied to nlmpc (IsContinuousTime = false)   spec l.69
%   RK4, 4 sub-steps per Ts                                            spec l.70
%   double precision throughout                                        spec l.71
%   Inputs (beta_deg, V_hub) are held constant over the sample (zero-order hold).
%
%   info.regions  torque-law region at each of the 4*n_sub right-hand-side evaluations
%   info.n_domain number of evaluations outside the Cp table domain (spec l.66)
%   info.n_guard  number of evaluations with the numerical guard active (spec l.67)
%   info.n_sat    number of evaluations with VS_MaxTq saturation active

if nargin < 6
    Ts = p.Ts;
end
h = Ts/p.n_sub;
x = x0(:);
n = 4*p.n_sub;
regions = zeros(1, n);
n_domain = 0;  n_guard = 0;  n_sat = 0;
e = 0;
for s = 1:p.n_sub
    [k1, i1] = rom_rhs(x,            beta_deg, V_hub, variant, p);
    [k2, i2] = rom_rhs(x + 0.5*h*k1, beta_deg, V_hub, variant, p);
    [k3, i3] = rom_rhs(x + 0.5*h*k2, beta_deg, V_hub, variant, p);
    [k4, i4] = rom_rhs(x + h*k3,     beta_deg, V_hub, variant, p);
    x = x + (h/6)*(k1 + 2*k2 + 2*k3 + k4);
    for I = [i1 i2 i3 i4]
        e = e + 1;
        regions(e) = I.region;
        n_domain = n_domain + I.domain;
        n_guard  = n_guard  + I.guard;
        n_sat    = n_sat    + I.sat;
    end
end
x1 = x;
info = struct('regions', regions, 'n_domain', n_domain, 'n_guard', n_guard, 'n_sat', n_sat);
end
