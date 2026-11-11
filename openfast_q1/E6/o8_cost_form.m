function J = o8_cost_form(y_pred, u_seq, lastmv, cfg)
%O8_COST_FORM  Cost of spec_E6_solver_O8 cost.form on a given output and MV sequence.
%
%   J = o8_cost_form(y_pred, u_seq, lastmv, cfg)
%
%   y_pred  2 x Np outputs y_i at times k+1..k+Np (cost.output_steps)
%   u_seq   Np x 1 MVs u_i at times k..k+Np-1 (cost.mv_steps)
%   lastmv  last applied MV (deg), u_0 of the first increment (cost.increment_steps)
%   cfg     o8_settings()
%
%   J = sum_i sum_j (wy_j (y_ij - r_j))^2 + sum_i (wu (u_i - ut))^2 + sum_i (wdu du_i)^2,
%   du_1 = u_1 - lastmv, du_i = u_i - u_(i-1); no ScaleFactor and no slack term.
%   This is the single implementation of cost.form, used by o8_cost and by the tests.

u_seq = u_seq(:);
if size(y_pred, 1) ~= 2 || size(y_pred, 2) ~= numel(u_seq)
    error('o8_cost_form:size', 'y_pred must be 2 x Np and u_seq Np x 1.');
end
y_err = cfg.wy(:).*(y_pred - cfg.y_ref(:));                     % cost.form, output term
du = diff([lastmv; u_seq]);                                      % cost.increment_steps
J = sum(y_err(:).^2) + sum((cfg.wu*(u_seq - cfg.ut)).^2) + sum((cfg.wdu*du).^2);
end
