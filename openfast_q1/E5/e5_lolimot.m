function fit = e5_lolimot(F, Y, F_sel, Y_sel, sched, opts)
%E5_LOLIMOT  LOLIMOT training of the C4 local linear neuro-fuzzy model (framework_decisions.C4_LLNFM
%and optimiser, E5 l.35, l.61; amendment 1; amendment_3.D6_C4), own code of the E5 framework
%(framework_decisions.framework, E5 l.26). No random element.
%
%   fit = e5_lolimot(F, Y, F_sel, Y_sel, sched, opts)
%
%   F, Y          training rows: F N x 4L normalised regressors (e5_features, layout 'window' with
%                 L >= 1, lag 0 first), Y N x 2 normalised targets (D2_scaling), double
%   F_sel, Y_sel  rows of the selection subset, same layout (one-step normalised MSE, D6)
%   sched         'du' (scheduling [d_k, u_k], sidx = [4 3]) or 'xud' ([x_k, u_k, d_k], sidx =
%                 [1 2 3 4]), the current sample of the regressor (E5 l.61)
%   opts          struct, every field optional: m_max (default 32, E5 l.35), k_sigma (default 1/3,
%                 amendment 1), verbose (default false: one line per iteration when true)
%
%   Source: O. Nelles, Nonlinear System Identification, 2nd ed., Springer, 2020 (amendment 1),
%   Sect. 13.3.1.1, p. 422-423, steps 1-5, with eq. (13.20)-(13.22) (local weighted least squares)
%   and (13.35)-(13.38):
%   1. one local model on the hyperrectangle [min, max] of the scheduling variables of the training
%      rows (reading C1 of P3), validity 1, parameters by weighted least squares;
%   2. local loss I_i = sum_n Phi_i(n) e(n)^2, e(n)^2 the squared error of the global model summed
%      over the two normalised outputs (framework_decisions.loss, equal weights); the worst local
%      model l = first argmax of I_i;
%   3. for each scheduling dimension j in the order of sidx: the hyperrectangle of l split into two
%      halves at its midpoint along j; the lower half keeps index l, the upper half takes index
%      M + 1; centres c = (lo + hi)/2 and sig = k_sigma (hi - lo) (eq. (13.35), (13.37)); all
%      validity functions recomputed (normalisation); the parameters of the two new local models
%      estimated by local weighted least squares, those of the other models unchanged (local
%      estimation, p. 423); loss of the overall model = sum over the training rows of the squared
%      errors of both outputs;
%   4. the split of lowest loss kept (first dimension in the order of sidx on a tie); M = M + 1;
%   5. repeat until M = m_max. The models of every size M = 1 .. m_max are recorded (Sect.
%      13.3.1.4) and the size retained is the first argmin of the one-step normalised MSE on the
%      selection subset (D6).
%   Weighted least squares: theta_i = argmin sum_n Phi_i(n) |Y(n, :) - [1, F(n, :)] theta|^2, both
%   outputs together (one factorisation), computed as (sqrt(Phi_i) .* X) \ (sqrt(Phi_i) .* Y)
%   (QR, the solution of (13.22) without forming X' Q X); a rank-deficiency warning of mldivide is
%   not displayed and is counted in fit.n_warn.
%   Every model output used here (losses, split choice, selection) is computed by
%   e5_lolimot_predict, one call of e5_llm_core per row, the function of the manual model
%   (supervisor review of 18/11/2026); the validity functions used as weights come from the same
%   calls.
%
%   fit.models{M}  struct of the model of size M (fields m, sidx, c, sig, Th of e5_llm_core, and
%                  lo, hi m x ns, the hyperrectangles), M = 1 .. m_max
%   fit.train_loss(M)  sum of squared normalised errors on the training rows; fit.train_mse(M) =
%                  train_loss(M)/(2N); fit.sel_mse(M) one-step normalised MSE on the selection rows
%   fit.m_best     first argmin of sel_mse; fit.iter  struct array per split (M = 2 .. m_max):
%                  m, worst, local_loss (M-1 x 1), cand_loss (1 x ns), dim (position in sidx)
%   fit.sched, fit.sidx, fit.L, fit.k_sigma, fit.m_max, fit.n_train, fit.n_sel, fit.n_warn,
%   fit.time_train, fit.time_select (s, tic/toc)

if nargin < 6 || isempty(opts)
    opts = struct();
end
m_max = get_opt(opts, 'm_max', 32);
k_sigma = get_opt(opts, 'k_sigma', 1/3);
verbose = get_opt(opts, 'verbose', false);
switch sched
    case 'du'
        sidx = [4 3];
    case 'xud'
        sidx = [1 2 3 4];
    otherwise
        error('e5_lolimot:sched', 'sched must be ''du'' or ''xud''.');
end
check_rows(F, Y, 'training');
check_rows(F_sel, Y_sel, 'selection');
n_reg = size(F, 2);
if mod(n_reg, 4) ~= 0 || size(F_sel, 2) ~= n_reg
    error('e5_lolimot:size', 'F and F_sel must have the same number of columns, a multiple of 4.');
end
if ~(isscalar(m_max) && m_max >= 1 && m_max == round(m_max)) || ~(isscalar(k_sigma) && k_sigma > 0)
    error('e5_lolimot:opts', 'm_max must be a positive integer and k_sigma positive.');
end
n_train = size(F, 1);
n_par = n_reg + 1;
ns = numel(sidx);
t_train = tic;
X1 = [ones(n_train, 1), F];
Ft = F';
lo = min(F(:, sidx), [], 1);
hi = max(F(:, sidx), [], 1);
if any(hi <= lo)
    error('e5_lolimot:range', 'A scheduling variable is constant on the training rows.');
end
warn_ids = {'MATLAB:rankDeficientMatrix', 'MATLAB:nearlySingularMatrix', 'MATLAB:singularMatrix'};
warn_saved = warning;
restore_warn = onCleanup(@() warning(warn_saved));
for q = 1:numel(warn_ids)
    warning('off', warn_ids{q});
end
n_warn = 0;
% ---------------------------------------------------------------- step 1: one local model
Lm = struct('m', 1, 'sidx', sidx, 'c', (lo + hi)/2, 'sig', k_sigma*(hi - lo), 'Th', zeros(2, n_par), ...
            'lo', lo, 'hi', hi);
[~, Phi] = e5_lolimot_predict(Lm, Ft);
[theta, n_w] = wls(X1, Y, Phi(1, :)', warn_ids);
n_warn = n_warn + n_w;
Lm.Th(1:2, :) = theta';
[Y_hat, Phi] = e5_lolimot_predict(Lm, Ft);
fit.models = cell(1, m_max);
fit.models{1} = Lm;
fit.train_loss = zeros(1, m_max);
fit.train_loss(1) = sum((Y - Y_hat').^2, 'all');
fit.iter = struct('m', {}, 'worst', {}, 'local_loss', {}, 'cand_loss', {}, 'dim', {});
if verbose
    fprintf('e5_lolimot %s L = %d: M = 1, training MSE %.6e, %.1f s\n', sched, n_reg/4, fit.train_loss(1)/(2*n_train), toc(t_train));
end
% ---------------------------------------------------------------- steps 2-5
for m_new = 2:m_max
    err2 = sum((Y - Y_hat').^2, 2);
    local_loss = Phi*err2;                         % eq. (13.38)
    [~, l_worst] = max(local_loss);
    cand_loss = inf(1, ns);
    best = [];
    for j = 1:ns
        cand = split_model(Lm, l_worst, j, k_sigma);
        [~, Phi_c] = e5_lolimot_predict(cand, Ft);
        [th_l, n_w1] = wls(X1, Y, Phi_c(l_worst, :)', warn_ids);
        [th_m, n_w2] = wls(X1, Y, Phi_c(m_new, :)', warn_ids);
        n_warn = n_warn + n_w1 + n_w2;
        cand.Th(2*l_worst - 1:2*l_worst, :) = th_l';
        cand.Th(2*m_new - 1:2*m_new, :) = th_m';
        [Y_c, Phi_c] = e5_lolimot_predict(cand, Ft);
        cand_loss(j) = sum((Y - Y_c').^2, 'all');
        if isempty(best) || cand_loss(j) < best.loss
            best = struct('loss', cand_loss(j), 'model', cand, 'Y_hat', Y_c, 'Phi', Phi_c, 'dim', j);
        end
    end
    Lm = best.model;
    Y_hat = best.Y_hat;
    Phi = best.Phi;
    fit.models{m_new} = Lm;
    fit.train_loss(m_new) = best.loss;
    fit.iter(end+1) = struct('m', m_new, 'worst', l_worst, 'local_loss', local_loss, 'cand_loss', cand_loss, 'dim', best.dim);
    if verbose
        fprintf('e5_lolimot %s L = %d: M = %d, split of %d along %d, training MSE %.6e, %.1f s\n', sched, n_reg/4, ...
                m_new, l_worst, sidx(best.dim), best.loss/(2*n_train), toc(t_train));
    end
end
fit.time_train = toc(t_train);
% ---------------------------------------------------------------- size by the selection subset (D6)
t_select = tic;
Ft_sel = F_sel';
fit.sel_mse = zeros(1, m_max);
for m_size = 1:m_max
    Y_sel_hat = e5_lolimot_predict(fit.models{m_size}, Ft_sel);
    fit.sel_mse(m_size) = sum((Y_sel - Y_sel_hat').^2, 'all')/(2*size(F_sel, 1));
end
[~, fit.m_best] = min(fit.sel_mse);
fit.time_select = toc(t_select);
fit.train_mse = fit.train_loss/(2*n_train);
fit.sched = sched;
fit.sidx = sidx;
fit.L = n_reg/4;
fit.k_sigma = k_sigma;
fit.m_max = m_max;
fit.n_train = n_train;
fit.n_sel = size(F_sel, 1);
fit.n_warn = n_warn;
if verbose
    fprintf('e5_lolimot %s L = %d: M retained %d (selection MSE %.6e), training %.1f s, selection %.1f s, WLS warnings %d\n', ...
            sched, fit.L, fit.m_best, fit.sel_mse(fit.m_best), fit.time_train, fit.time_select, n_warn);
end
delete(restore_warn);
end

% ================================================================ local functions
function v = get_opt(opts, name, default)
if isfield(opts, name)
    v = opts.(name);
else
    v = default;
end
end

function check_rows(F, Y, label)
if ~isa(F, 'double') || ~isa(Y, 'double') || ~isreal(F) || ~isreal(Y) || size(Y, 2) ~= 2 || ...
        size(F, 1) ~= size(Y, 1) || size(F, 1) < 1 || ~all(isfinite(F(:))) || ~all(isfinite(Y(:)))
    error('e5_lolimot:rows', 'The %s rows must be finite real double, F N x 4L and Y N x 2.', label);
end
end

function cand = split_model(Lm, l_split, j, k_sigma)
% halves of the hyperrectangle of model l_split along scheduling dimension j: lower half at index
% l_split, upper half appended at index m + 1; the other models unchanged; the parameters of the two
% new models set to zero until they are estimated (the validity functions do not depend on them)
m_new = Lm.m + 1;
mid = (Lm.lo(l_split, j) + Lm.hi(l_split, j))/2;
cand = Lm;
cand.m = m_new;
cand.lo(m_new, :) = Lm.lo(l_split, :);
cand.hi(m_new, :) = Lm.hi(l_split, :);
cand.hi(l_split, j) = mid;
cand.lo(m_new, j) = mid;
for i_new = [l_split, m_new]
    cand.c(i_new, :) = (cand.lo(i_new, :) + cand.hi(i_new, :))/2;
    cand.sig(i_new, :) = k_sigma*(cand.hi(i_new, :) - cand.lo(i_new, :));
end
cand.Th(2*l_split - 1:2*l_split, :) = 0;
cand.Th(2*m_new - 1:2*m_new, :) = 0;
end

function [theta, n_w] = wls(X1, Y, w, warn_ids)
% local weighted least squares, eq. (13.22), by QR of the weighted regression matrix
sw = sqrt(w);
lastwarn('');
theta = (sw.*X1)\(sw.*Y);
[~, warn_id] = lastwarn;
n_w = double(any(strcmp(warn_id, warn_ids)));
end
