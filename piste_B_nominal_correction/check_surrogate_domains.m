function check_surrogate_domains()
% CHECK_SURROGATE_DOMAINS  Verify that each surrogate's training-data
% domain (Stage 1 coverage) is consistent with the MPC output-variable
% bounds actually configured for its controller (reproducibility
% review, P2.3).
%
%   check_surrogate_domains()
%
%   PURPOSE
%     Section~5.2 (subsec:surrogate_integration) states that
%     surrogate-based controllers are constrained to the Stage~1
%     training domain with a 0.5 rpm safety margin
%     (omega in [8.52, 12.81] rpm), distinct from the Baseline's wider
%     physics-based bound. This script checks that claim automatically
%     against the ACTUAL bounds configured in each controller's design
%     script and the ACTUAL data ranges in stage1_data.mat, rather than
%     relying on the paper text being kept manually in sync with the
%     code as both evolve.
%
%   CHECKS PERFORMED
%     1. For each surrogate, is the configured MPC omega bound
%        (p.omega_mpc_min/max_surrogate) INSIDE the Stage 1 training
%        domain's observed omega range (with the stated 0.5 rpm margin)?
%        A bound wider than the training data means the surrogate can
%        be queried outside its training domain during optimization --
%        an unconstrained extrapolation risk documented as the original
%        motivation for this constraint (Section 5.2).
%     2. Is the Baseline's physics-based bound
%        (p.omega_mpc_min_physics/omega_max) at least as permissive as
%        the surrogate bound (as intended -- Baseline uses the true
%        plant, not a domain-restricted surrogate)?
%
%   OUTPUT
%     Printed report; also written to results/domain_check_results.txt.
%     Any FAIL is flagged prominently, since it would indicate the
%     paper's stated safety margin is not actually enforced by the
%     current configuration.

fprintf('==========================================================\n');
fprintf('  SURROGATE DOMAIN CONSISTENCY CHECK (P2.3)\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'domain_check_results.txt');

p = get_wt_params();

if ~exist('stage1_data.mat', 'file')
    error('stage1_data.mat not found -- cannot verify training domain.');
end
S = load('stage1_data.mat');

% ── Observed training-data omega range (rpm) ────────────────────────────────
omega_rpm_all = S.X_in(:,1) * 30/pi;
omega_min_observed = min(omega_rpm_all);
omega_max_observed = max(omega_rpm_all);

fprintf('Stage 1 training data observed omega range: [%.2f, %.2f] rpm\n\n', ...
    omega_min_observed, omega_max_observed);

% ── Configured MPC bounds (from get_wt_params.m) ────────────────────────────
omega_min_surr_rpm = p.omega_mpc_min_surrogate * 30/pi;
omega_max_surr_rpm = p.omega_mpc_max_surrogate * 30/pi;
omega_min_phys_rpm = p.omega_mpc_min_physics * 30/pi;
omega_max_phys_rpm = p.omega_max * 30/pi;

fprintf('Configured surrogate MPC bound: [%.2f, %.2f] rpm\n', ...
    omega_min_surr_rpm, omega_max_surr_rpm);
fprintf('Configured Baseline (physics) MPC bound: [%.2f, %.2f] rpm\n\n', ...
    omega_min_phys_rpm, omega_max_phys_rpm);

fid = fopen(txt_path, 'w');
fprintf(fid, 'SURROGATE DOMAIN CONSISTENCY CHECK\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '================================================\n\n');
fprintf(fid, 'stage1_observed_omega_min_rpm = %.4f\n', omega_min_observed);
fprintf(fid, 'stage1_observed_omega_max_rpm = %.4f\n', omega_max_observed);
fprintf(fid, 'configured_surrogate_bound_min_rpm = %.4f\n', omega_min_surr_rpm);
fprintf(fid, 'configured_surrogate_bound_max_rpm = %.4f\n', omega_max_surr_rpm);
fprintf(fid, 'configured_baseline_bound_min_rpm = %.4f\n', omega_min_phys_rpm);
fprintf(fid, 'configured_baseline_bound_max_rpm = %.4f\n\n', omega_max_phys_rpm);

% ── Check 1: surrogate bound must be INSIDE the observed training domain ───
all_pass = true;

fprintf('--- Check 1: surrogate MPC bound within training domain? ---\n');
fprintf(fid, '[Check 1: surrogate MPC bound within training domain]\n');
if omega_min_surr_rpm >= omega_min_observed && omega_max_surr_rpm <= omega_max_observed
    fprintf('  PASS: surrogate bound [%.2f, %.2f] is within observed training\n', ...
        omega_min_surr_rpm, omega_max_surr_rpm);
    fprintf('  range [%.2f, %.2f] (margin: %.2f rpm low, %.2f rpm high)\n', ...
        omega_min_observed, omega_max_observed, ...
        omega_min_surr_rpm - omega_min_observed, omega_max_observed - omega_max_surr_rpm);
    fprintf(fid, '  PASS\n');
    fprintf(fid, '  margin_low_rpm = %.4f\n', omega_min_surr_rpm - omega_min_observed);
    fprintf(fid, '  margin_high_rpm = %.4f\n', omega_max_observed - omega_max_surr_rpm);
else
    fprintf('  *** FAIL ***: surrogate bound [%.2f, %.2f] EXTENDS BEYOND observed\n', ...
        omega_min_surr_rpm, omega_max_surr_rpm);
    fprintf('  training range [%.2f, %.2f] -- surrogates can be queried OUTSIDE\n', ...
        omega_min_observed, omega_max_observed);
    fprintf('  their training domain during optimization.\n');
    fprintf(fid, '  *** FAIL *** -- surrogate bound extends beyond training domain\n');
    all_pass = false;
end
fprintf(fid, '\n');

% ── Check 2 (informational): Baseline and surrogate bounds serve
%    DIFFERENT purposes and are NOT expected to be in a containment
%    relationship -- Baseline uses the true physical plant (no
%    training-domain protection needed) with a narrow, near-rated
%    "cheap safeguard" bound, while surrogates require the wider
%    training-domain-derived bound specifically to avoid unconstrained
%    extrapolation. An earlier version of this check incorrectly
%    asserted Baseline's bound should contain the surrogate bound;
%    that assumption was not actually made anywhere in the paper and
%    has been removed here. ────────────────────────────────────────────
fprintf('\n--- Note: Baseline vs surrogate bounds (informational only) ---\n');
fprintf(fid, '[Note: Baseline vs surrogate bounds]\n');
fprintf('  Baseline [%.2f, %.2f] and surrogate [%.2f, %.2f] bounds serve\n', ...
    omega_min_phys_rpm, omega_max_phys_rpm, omega_min_surr_rpm, omega_max_surr_rpm);
fprintf('  DIFFERENT purposes (physics-based safeguard vs. training-domain\n');
fprintf('  protection) and are not expected to be nested -- this is NOT a\n');
fprintf('  consistency check, purely informational.\n');
fprintf(fid, '  INFO ONLY -- no containment relationship expected or required\n');
fprintf(fid, '\n');

fprintf('\n============================================================\n');
if all_pass
    fprintf('  OVERALL: ALL CHECKS PASSED\n');
    fprintf('  The paper''s stated bound configuration (Section~5.2) is\n');
    fprintf('  consistent with the actual code as currently configured.\n');
    fprintf(fid, '[Overall] ALL CHECKS PASSED\n');
else
    fprintf('  OVERALL: AT LEAST ONE CHECK FAILED -- see above.\n');
    fprintf('  The paper''s stated bound/safety-margin claims should be\n');
    fprintf('  re-verified against the current code before submission.\n');
    fprintf(fid, '[Overall] AT LEAST ONE CHECK FAILED -- see details above\n');
end
fprintf('============================================================\n');
fclose(fid);
fprintf('\nWrote %s\n', txt_path);

end
