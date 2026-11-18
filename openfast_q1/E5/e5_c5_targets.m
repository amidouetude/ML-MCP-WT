function [Y, keep, n_bound] = e5_c5_targets(runs, rows, nrm, p)
%E5_C5_TARGETS  Residual target of C5 (framework_decisions.C5_residual, E5 l.44) with the physical
%part in the NMPC mode (amendment_3.D7_C5_physical_part).
%
%   [Y, keep, n_bound] = e5_c5_targets(runs, rows, nrm, p)
%
%   rows     e5_rows of kind 'current'; nrm  e5_normalisation
%   p        rom_params(cp_table_file) with p.cp_mode = 'nmpc' (refused otherwise)
%   For row (r, k): [x1, info] = rom_step(x_k, u_k, d_k, 'i', p) (model v2, wind variant (i),
%   arms.C5, E5 l.58); residual = DX(k, :)' - (x1 - x_k); Y(row, :) = residual'./nrm.sdx' (scaled
%   by the standard deviation only, no centring, D2_scaling).
%   n_bound(row) = info.n_domain_lambda + info.n_domain_beta (bounded evaluations of the NMPC mode);
%   keep(row) = n_bound == 0 and the residual is finite: a row with a bounded evaluation has no
%   defined residual and is excluded from the C5 training, with its count (D7).

if ~isstruct(p) || ~isfield(p, 'cp_mode') || ~(ischar(p.cp_mode) || isstring(p.cp_mode)) || ~strcmp(p.cp_mode, 'nmpc')
    error('e5_c5_targets:cpMode', 'C5 requires p.cp_mode = ''nmpc'' (amendment_3.D7_C5_physical_part).');
end
n_rows = size(rows, 1);
Y = zeros(n_rows, 2);
keep = false(n_rows, 1);
n_bound = zeros(n_rows, 1);
for i_row = 1:n_rows
    run_k = runs(rows(i_row, 1));
    k = rows(i_row, 2);
    x_k = run_k.X(k, 1:2)';
    [x1, info] = rom_step(x_k, run_k.X(k, 3), run_k.X(k, 4), 'i', p);
    residual = run_k.DX(k, :)' - (x1 - x_k);
    n_bound(i_row) = info.n_domain_lambda + info.n_domain_beta;
    keep(i_row) = n_bound(i_row) == 0 && all(isfinite(residual));
    Y(i_row, :) = (residual./nrm.sdx)';
end
end
