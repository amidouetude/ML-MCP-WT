function [Cp, dCp_dl, dCp_db] = cp_lambda_beta(lambda, beta)
% CP_LAMBDA_BETA  Power coefficient for the NREL 5-MW reference wind turbine
%
%   Cp = cp_lambda_beta(lambda, beta)
%   [Cp, dCp_dl, dCp_db] = cp_lambda_beta(lambda, beta)
%
%   INPUTS
%     lambda   tip-speed ratio  lambda = R * omega_r / V  [-]
%              valid calibration domain : [2, 13]
%     beta     collective pitch angle [deg]
%              valid calibration domain : [0, 25]
%              (scalar or array, must be same size as lambda)
%
%   OUTPUTS
%     Cp       power coefficient [-],  clamped to [0, Betz_limit]
%     dCp_dl   partial derivative dCp/dlambda  (only if nargout >= 2)
%     dCp_db   partial derivative dCp/dbeta    (only if nargout >= 3)
%
%   POLYNOMIAL MODEL
%     Standard 5-MW polynomial from Jonkman et al. (2009), NREL/TP-500-38060
%     Coefficients: c = [0.5176, 116, 0.4, 5, 21, 0.0068]
%
%   IMPORTANT — CALIBRATION DOMAIN
%     The polynomial was fitted over beta in [0, 25] deg and lambda in [2, 13].
%     Evaluating outside this range produces non-physical Cp values
%     (e.g., Cp > Betz limit = 16/27 ≈ 0.5926).
%     Inputs are clamped to the calibration domain before evaluation.
%     Cp output is further clamped to [0, Betz_limit].
%
%   PHYSICAL CONSTANTS
%     Betz limit : Cp_max_theoretical = 16/27 = 0.5926
%     Typical NREL 5-MW peak : Cp_max ≈ 0.482 at lambda ≈ 7.5, beta = 0 deg
%
%   REFERENCE
%     Jonkman, J. et al. (2009). Definition of a 5-MW Reference Wind Turbine
%     for Offshore System Development. NREL/TP-500-38060.

% ── Physical constant ─────────────────────────────────────────────────────────
BETZ_LIMIT = 16/27;    % = 0.5926  theoretical maximum Cp

% ── Calibration domain clamp ─────────────────────────────────────────────────
%    Applied BEFORE polynomial evaluation to prevent non-physical outputs.
%    Domain: lambda in [2, 13],  beta in [0, 25] deg
beta   = max(0.0, min(25.0, beta));
lambda = max(2.0,  min(13.0, lambda));

% ── Intermediate variable lambda_i ───────────────────────────────────────────
%    lambda_i absorbs both lambda and beta dependence
li_inv = 1 ./ (lambda + 0.08*beta) - 0.035 ./ (beta.^3 + 1);
li     = 1 ./ (li_inv + 1e-9);          % 1e-9 guard against division by zero

% ── Cp polynomial (Jonkman 2009) ──────────────────────────────────────────────
c1 = 0.5176;  c2 = 116;  c3 = 0.4;
c4 = 5;       c5 = 21;   c6 = 0.0068;

Cp = c1 .* (c2./li - c3*beta - c4) .* exp(-c5./li) + c6*lambda;

% ── Physical output clamp ─────────────────────────────────────────────────────
%    Enforce 0 <= Cp <= Betz limit regardless of polynomial extrapolation
Cp = max(0, min(BETZ_LIMIT, Cp));

% ── Analytical gradients (computed only when requested) ──────────────────────
if nargout > 1
    % Guard for gradient computation (same clamped values)
    eps_grad = 1e-12;

    % d(lambda_i)/d(lambda)
    dli_dl = -(1 ./ (lambda + 0.08*beta)).^2 ./ (li_inv.^2 + eps_grad);

    % d(lambda_i)/d(beta)
    dli_db = ( 0.08 ./ (lambda + 0.08*beta).^2 ...
             + 0.105*beta.^2 ./ (beta.^3 + 1).^2 ) ./ (li_inv.^2 + eps_grad);

    % dF/d(lambda_i)  where F = c1*(c2/li - c3*beta - c4)*exp(-c5/li)
    dF_dli = c1 .* (-c2./li.^2 + (c2./li - c3*beta - c4) .* c5./li.^2) ...
             .* exp(-c5./li);

    dCp_dl = dF_dli .* dli_dl + c6;
    dCp_db = dF_dli .* dli_db - c1*c3 .* exp(-c5./li);

    % Zero gradients where Cp hit the bounds (clamp kills gradient)
    at_lower = (Cp <= 0);
    at_upper = (Cp >= BETZ_LIMIT);
    dCp_dl(at_lower | at_upper) = 0;
    dCp_db(at_lower | at_upper) = 0;
end

end
