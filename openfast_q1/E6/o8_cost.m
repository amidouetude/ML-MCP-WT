function [J, grad, pr] = o8_cost(uz, z0, d, lastmv, model, cfg, want_grad)
%O8_COST  O8 cost J(uz) and its gradient dJ/duz by forward sensitivities.
%
%   [J, grad, pr] = o8_cost(uz, z0, d, lastmv, model, cfg, want_grad)
%
%   uz         Nc x 1 blocked moves (unknowns.moves)
%   z0, d      initial state and held disturbance (prediction)
%   lastmv     last applied MV (cost.increment_steps)
%   model      struct: step(z, u, d) -> [z1, aux_row]; jac(z, u, d, z1) -> [A, Bmv, aux_row]
%   cfg        o8_settings()
%   want_grad  true: the gradient is computed (gradient.formula); false: grad = []
%
%   J     cost.form on the single-shooting prediction (o8_cost_form)
%   grad  gradient.formula: S_0 = 0; S_i = A_i S_(i-1) + Bmv_i E_i (A_i, Bmv_i at (z_(i-1), u_i));
%         dJ/duz = 2 sum_i S_i' C' Wy^2 (C z_i - r) + 2 wu^2 sum_i E_i' (u_i - ut)
%                  + 2 wdu^2 D' (D uz - e_1 lastmv), C = [I_2, 0]
%   pr    struct: Z (nz x Np+1), u_seq, n_model_eval, n_clamp_lambda, n_clamp_beta, n_jac_eval

uz = uz(:);
[blk, ~] = o8_block_map(cfg.Np, cfg.Nc);
u_seq = uz(blk);                                                 % unknowns.blocking
[Z, aux] = o8_predict(model, z0, u_seq, d);                      % prediction.recursion
J = o8_cost_form(Z(1:2, 2:end), u_seq, lastmv, cfg);             % cost.form
grad = [];
n_jac = 0;
if want_grad
    nz = size(Z, 1);
    S = zeros(nz, cfg.Nc);                                       % S_0 = 0
    grad = zeros(cfg.Nc, 1);
    wy2 = cfg.wy(:).^2;
    for istep = 1:cfg.Np
        [a_jac, b_jac, aux_jac] = model.jac(Z(:, istep), u_seq(istep), d, Z(:, istep + 1));
        aux = aux + aux_jac;
        n_jac = n_jac + 1;
        e_row = zeros(1, cfg.Nc);
        e_row(blk(istep)) = 1;                                   % E_i, row i of iz2u
        S = a_jac*S + b_jac*e_row;                               % S_i
        grad = grad + 2*S(1:2, :).'*(wy2.*(Z(1:2, istep + 1) - cfg.y_ref(:)));
        grad = grad + 2*cfg.wu^2*e_row.'*(u_seq(istep) - cfg.ut);  % zero with wu = 0
    end
    d_mat = eye(cfg.Nc) - diag(ones(cfg.Nc - 1, 1), -1);         % D of gradient.formula
    e_first = [1; zeros(cfg.Nc - 1, 1)];                         % e_1
    grad = grad + 2*cfg.wdu^2*(d_mat.'*(d_mat*uz - e_first*lastmv));
end
pr = struct('Z', Z, 'u_seq', u_seq, 'n_model_eval', aux(1), 'n_clamp_lambda', aux(2), ...
            'n_clamp_beta', aux(3), 'n_jac_eval', n_jac);
end
