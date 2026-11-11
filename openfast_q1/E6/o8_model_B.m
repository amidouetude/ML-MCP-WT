function model = o8_model_B(p)
%O8_MODEL_B  Prediction model of arm B for O8: rom_step in the NMPC mode, Jacobians by forward
%differences with the rule of nlmpc.
%
%   model = o8_model_B(p)
%
%   p       rom_params(cp_table_file) with p.cp_mode = 'nmpc' (spec_E6_solver_O8
%           prediction.cp_fallback; spec_E2 amendment 8 model.cp_interpolant.out_of_domain);
%           any other mode is refused
%   model.name   'B';  model.nz   2 (z = x = [omega_r; omega_f])
%   model.init   init_fam of B: z_0 = x measured (prediction.recursion)
%   model.step   f_fam: z1 = rom_step(z, u, d, 'i', p), Ts = p.Ts (wind variant (i), model v2);
%                aux_row = [1, info.n_domain_lambda, info.n_domain_beta]
%   model.jac    [A, Bmv, aux_row] = jac(z, u, d, z1), z1 = f_fam(z, u, d) already computed:
%                forward differences of gradient.jacobians_per_arm.B_and_C5 option (a), copied
%                from computeJacobianState.m l.19-43 (R2024a): dv = 1e-6, step dv*max(|v|, 1)
%                (abs, then values below 1 set to 1), perturbation added and then subtracted
%                in place, (f - f0)/step; nz evaluations for A and one for Bmv
%   model.trace  [z1, info] = trace(z, u, d): rom_step with its info structure (tests only)

if ~isfield(p, 'cp_mode') || ~(ischar(p.cp_mode) || isstring(p.cp_mode)) || ~strcmp(p.cp_mode, 'nmpc')
    error('o8_model_B:cpMode', 'Arm B of O8 requires p.cp_mode = ''nmpc'' (prediction.cp_fallback).');
end
model.name = 'B';
model.nz = 2;
model.init = @(x) x(:);
model.step = @(z, u, d) step_B(z, u, d, p);
model.jac = @(z, u, d, z1) jac_B(z, u, d, z1, p);
model.trace = @(z, u, d) rom_step(z, u, d, 'i', p);
end

function [z1, aux] = step_B(z, u, d, p)
[z1, step_info] = rom_step(z, u, d, 'i', p);
aux = [1, step_info.n_domain_lambda, step_info.n_domain_beta];
end

function [a_jac, b_jac, aux] = jac_B(z, u, d, z1, p)
dv = 1e-6;                                      % computeJacobianState.m l.19
nz = numel(z);
x0 = z(:);
a_jac = zeros(nz, nz);
aux = zeros(1, 3);
xa = abs(x0);                                   % l.21-22
xa(xa < 1) = 1;
for jstate = 1:nz                               % l.23-30
    dx = dv*xa(jstate);
    x0(jstate) = x0(jstate) + dx;
    [f_pert, aux_pert] = step_B(x0, u, d, p);
    x0(jstate) = x0(jstate) - dx;
    a_jac(:, jstate) = (f_pert - z1)/dx;
    aux = aux + aux_pert;
end
ua = abs(u);                                    % l.33-34 (MV only, nmv = 1)
ua(ua < 1) = 1;
du = dv*ua;                                     % l.37-38
u_pert = u + du;
[f_pert, aux_pert] = step_B(x0, u_pert, d, p);
b_jac = (f_pert - z1)/du;                       % l.41
aux = aux + aux_pert;
end
