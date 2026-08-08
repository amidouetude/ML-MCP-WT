function mdl = extract_gp_weights(mdl)
% EXTRACT_GP_WEIGHTS  Extract plain double parameters (kernel
% hyperparameters, active set, Alpha, Beta) from the trained GP
% residual model, so that sf_gp_residual_manual.m can compute the
% posterior mean with a hand-written Matern 5/2 kernel formula —
% NEVER calling predict() on the RegressionGP objects.
%
%   mdl = extract_gp_weights(mdl)
%
%   POSTERIOR MEAN FORMULA (constant basis function, as used here)
%     mean(x) = Beta + sum_i Alpha_i * k(x, x_i)
%   where k is the Matern 5/2 kernel:
%     k(x,x') = sigma_f^2 * (1 + sqrt(5)*r/l + 5*r^2/(3*l^2)) * exp(-sqrt(5)*r/l)
%     r = ||x - x'||_2
%   sigma_f, l read from gp.KernelInformation.KernelParameters
%   (MATLAB convention: KernelParameters = [l; sigma_f], i.e. length
%   scale first, signal std second — verified defensively below).
%
%   OUTPUT  mdl with added fields per output (o=omega, b=beta):
%     Xactive_o/b   [Nsub x 4]  active set (support points)
%     alpha_o/b     [Nsub x 1]  posterior weights
%     beta0_o/b     scalar      constant basis function coefficient
%     sigma_f_o/b, l_o/b        Matern 5/2 hyperparameters

for out = 1:2
    if out == 1
        gp = mdl.gp_o; tag = 'o';
    else
        gp = mdl.gp_b; tag = 'b';
    end

    Xactive = gp.ActiveSetVectors;         % [Nsub x 4], original (normalised-by-us) scale
    alpha   = gp.Alpha;                    % [Nsub x 1]
    beta0   = gp.Beta;                     % scalar, constant basis function

    kparams = gp.KernelInformation.KernelParameters;
    % MATLAB convention for matern52: KernelParameters = [length_scale; sigma_f]
    l       = kparams(1);
    sigma_f = kparams(2);

    mdl.(['Xactive_' tag]) = Xactive;
    mdl.(['alpha_' tag])   = alpha;
    mdl.(['beta0_' tag])   = beta0;
    mdl.(['sigma_f_' tag]) = sigma_f;
    mdl.(['l_' tag])       = l;
end

% ── Sanity check: manual posterior mean must match predict() ────────────────
x_test  = mdl.xmu + mdl.xsig .* randn(1,4);
xn_test = (x_test - mdl.xmu) ./ mdl.xsig;

pred_o_predict = predict(mdl.gp_o, xn_test);
pred_b_predict = predict(mdl.gp_b, xn_test);

pred_o_manual = gp_matern52_mean(xn_test, mdl.Xactive_o, mdl.alpha_o, ...
    mdl.beta0_o, mdl.sigma_f_o, mdl.l_o);
pred_b_manual = gp_matern52_mean(xn_test, mdl.Xactive_b, mdl.alpha_b, ...
    mdl.beta0_b, mdl.sigma_f_b, mdl.l_b);

diff_o = abs(pred_o_predict - pred_o_manual);
diff_b = abs(pred_b_predict - pred_b_manual);
fprintf('  Manual GP posterior mean vs predict(): diff_omega=%.2e  diff_beta=%.2e\n', ...
    diff_o, diff_b);
if max(diff_o, diff_b) > 1e-6
    warning(['Manual GP posterior mean does not match predict() within tolerance -- ' ...
             'check KernelParameters ordering / BasisFunction assumptions.']);
else
    fprintf('  Manual GP posterior mean VERIFIED correct.\n');
end

end


function m = gp_matern52_mean(x, Xactive, alpha, beta0, sigma_f, l)
% Posterior mean at query point x [1x4], given active set Xactive
% [Nx4], weights alpha [Nx1], constant basis beta0, Matern52
% hyperparameters sigma_f, l.
diffs = Xactive - x;                    % [N x 4], broadcast
r = sqrt(sum(diffs.^2, 2));             % [N x 1]
sq5 = sqrt(5);
k = sigma_f^2 .* (1 + sq5*r/l + 5*r.^2/(3*l^2)) .* exp(-sq5*r/l);  % [N x 1]
m = beta0 + sum(alpha .* k);
end
