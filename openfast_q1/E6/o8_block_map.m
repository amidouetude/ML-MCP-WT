function [blk, iz2u] = o8_block_map(Np, Nc)
%O8_BLOCK_MAP  Move blocking of O8 (spec_E6_solver_O8 unknowns.blocking).
%
%   [blk, iz2u] = o8_block_map(Np, Nc)
%
%   blk(i) = min(i, Nc), the block of prediction step i (i = 1..Np): block lengths
%            m = [1, ..., 1, Np - Nc + 1], i.e. [1 1 1 1 26] for Np = 30, Nc = 5.
%   iz2u   Np x Nc matrix with u = iz2u*uz (mapping of getDecisions.m l.28-30, MV ScaleFactor 1);
%          row i is E_i of gradient.formula.

if ~(isscalar(Np) && isscalar(Nc) && Np >= 1 && Nc >= 1 && Nc <= Np && Np == round(Np) && Nc == round(Nc))
    error('o8_block_map:size', 'Np and Nc must be integers with 1 <= Nc <= Np.');
end
blk = min(1:Np, Nc);
iz2u = zeros(Np, Nc);
iz2u(sub2ind([Np, Nc], 1:Np, blk)) = 1;
end
