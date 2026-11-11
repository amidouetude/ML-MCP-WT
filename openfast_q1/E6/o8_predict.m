function [Z, aux] = o8_predict(model, z0, u_seq, d)
%O8_PREDICT  Single-shooting prediction of O8 (spec_E6_solver_O8 prediction.recursion).
%
%   [Z, aux] = o8_predict(model, z0, u_seq, d)
%
%   model   struct with model.step(z, u, d) -> [z1, aux_row] (f_fam of the arm)
%   z0      initial state z_0 (from init_fam of the arm)
%   u_seq   Np x 1 MV sequence u_1..u_Np
%   d       measured disturbance d_k, held over the horizon (prediction.disturbance)
%   Z       nz x (Np+1), Z(:, 1) = z_0, Z(:, i+1) = f_fam(Z(:, i), u_i, d) (index_match_with_nlmpc)
%   aux     1 x 3 sum of the aux rows of model.step: [model evaluations, lambda-bounded
%           evaluations, beta-bounded evaluations]

u_seq = u_seq(:);
Np = numel(u_seq);
Z = zeros(numel(z0), Np + 1);
Z(:, 1) = z0(:);
aux = zeros(1, 3);
for istep = 1:Np
    [Z(:, istep + 1), aux_step] = model.step(Z(:, istep), u_seq(istep), d);
    aux = aux + aux_step;
end
end
