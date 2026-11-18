function G = e5_convert_gp(gp_r, gp_f)
%E5_CONVERT_GP  GP struct of e5_model (C6) from the two fitted RegressionGP objects of the state
%components omega_r and omega_f (framework_decisions.C6_sparse_GP, E5 l.45; amendment_3.D5_C6).
%
%   G = e5_convert_gp(gp_r, gp_f)
%
%   G.Xa      m x 4 active set (shared by the two GPs, D5)
%   G.ell     2 x 4 length scales, row o from KernelInformation.KernelParameters(1:4) of GP o
%   G.alpha   m x 2, column o = sigma_f(o)^2 x Alpha of GP o (the kernel amplitude, D5, so that
%             gp_out of e5_model gives the predictive mean of predict(): sum_i alpha_i
%             exp(-0.5 sum_j ((s_j - Xa_ij)/ell_j)^2), no basis term)
%   Refuses (error) if a GP does not use the ARD squared exponential kernel, BasisFunction none, the
%   FIC predict method, unstandardised inputs (PredictorLocation empty), or if the two active sets
%   differ.

gps = {gp_r, gp_f};
for o = 1:2
    g = gps{o};
    if ~isa(g, 'RegressionGP') || ~strcmpi(g.KernelFunction, 'ARDSquaredExponential') || ...
            ~strcmpi(g.BasisFunction, 'None') || ~strcmpi(g.PredictMethod, 'FIC') || ~isempty(g.PredictorLocation)
        error('e5_convert_gp:model', 'GP %d is not an unstandardised FIC GP with ARD squared exponential kernel and no basis.', o);
    end
end
G.Xa = double(gp_r.ActiveSetVectors);
if ~isequal(G.Xa, double(gp_f.ActiveSetVectors))
    error('e5_convert_gp:activeSet', 'The two GPs do not share the same active set (D5).');
end
n_in = size(G.Xa, 2);
G.ell = zeros(2, n_in);
G.alpha = zeros(size(G.Xa, 1), 2);
for o = 1:2
    theta = double(gps{o}.KernelInformation.KernelParameters(:));
    if numel(theta) ~= n_in + 1
        error('e5_convert_gp:kernel', 'GP %d has %d kernel parameters, expected %d.', o, numel(theta), n_in + 1);
    end
    G.ell(o, :) = theta(1:n_in)';
    G.alpha(:, o) = theta(end)^2*double(gps{o}.Alpha(:));
end
end
