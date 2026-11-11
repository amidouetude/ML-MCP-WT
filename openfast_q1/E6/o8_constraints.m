function [a_ineq, b_ineq] = o8_constraints(lastmv, cfg)
%O8_CONSTRAINTS  Linear inequalities a_ineq*uz <= b_ineq of O8 (spec_E6_solver_O8 constraints).
%
%   [a_ineq, b_ineq] = o8_constraints(lastmv, cfg)
%
%   For i = 1..Np, in the row order of getUBounds.m l.21-48 (R2024a), with u_0 = lastmv:
%     -(u_i - u_(i-1)) <= -RateMin,   (u_i - u_(i-1)) <= RateMax,   -u_i <= -Min,   u_i <= Max;
%   only rows with a finite bound kept (getUBounds.m l.22-25, l.50); MV ScaleFactor 1 and MV ECR 0
%   (no slack column); mapped to uz by iz2u (getUBounds.m l.65). 4 Np = 120 rows for Np = 30
%   (constraints.rows option (a)). No bound vector, no nonlinear constraint (constraints.none_other).

Np = cfg.Np;
[~, iz2u] = o8_block_map(Np, cfg.Nc);
a_u = zeros(4*Np, Np);
b_ineq = zeros(4*Np, 1);
bound_value = zeros(4*Np, 1);
for istep = 1:Np
    r0 = 4*(istep - 1);
    a_u(r0 + 1, istep) = -1;                    % -(u_i - u_(i-1)) <= -RateMin
    a_u(r0 + 2, istep) =  1;                    %  (u_i - u_(i-1)) <=  RateMax
    a_u(r0 + 3, istep) = -1;                    % -u_i <= -Min
    a_u(r0 + 4, istep) =  1;                    %  u_i <=  Max
    bound_value(r0 + (1:4)) = [cfg.rate_min; cfg.rate_max; cfg.u_min; cfg.u_max];
    b_ineq(r0 + 1) = -cfg.rate_min;
    b_ineq(r0 + 2) =  cfg.rate_max;
    b_ineq(r0 + 3) = -cfg.u_min;
    b_ineq(r0 + 4) =  cfg.u_max;
    if istep == 1                               % getUBounds.m l.40-42: u_0 = lastMV
        b_ineq(r0 + 1) = b_ineq(r0 + 1) - lastmv;
        b_ineq(r0 + 2) = b_ineq(r0 + 2) + lastmv;
    else                                        % getUBounds.m l.43-45
        a_u(r0 + 1, istep - 1) =  1;
        a_u(r0 + 2, istep - 1) = -1;
    end
end
keep = isfinite(bound_value);
a_ineq = a_u(keep, :)*iz2u;
b_ineq = b_ineq(keep);
end
