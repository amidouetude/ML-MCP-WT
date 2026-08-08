function results = run_sensitivity_rk4()
% RUN_SENSITIVITY_RK4  Euler-vs-RK4 plant integration sensitivity check
% (reproducibility review, P1.2), write results/sensitivity_rk4_results.txt.
%
%   results = run_sensitivity_rk4()
%
%   METHOD
%     Runs the Baseline controller in closed loop TWICE, identical wind
%     realization and controller, differing ONLY in which integration
%     scheme advances the simulated "true" plant each step: Euler
%     (wt_step.m, the scheme used everywhere else in this project) vs
%     classical RK4 (wt_step_rk4.m). The MPC's internal predictive
%     model is Euler-based (sf_baseline.m) in BOTH cases, unchanged --
%     this isolates the question of plant-integration sensitivity from
%     any predictor/plant mismatch question.
%
%   INTERPRETATION
%     If RK4 and Euler closed-loop RMSE agree closely (see printed
%     relative difference), this supports the claim that Euler's local
%     truncation error at dt=0.1s is negligible for this plant and does
%     not materially affect the paper's reported closed-loop results.
%     A large discrepancy would instead indicate the reported results
%     are sensitive to integration-scheme choice and would need
%     qualification.

fprintf('==========================================================\n');
fprintf('  SENSITIVITY CHECK: Euler vs RK4 plant integration (P1.2)\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'sensitivity_rk4_results.txt');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

T_SIM  = 60;
Ts     = cfg.mpc.Ts;
N_steps = round(T_SIM / Ts);
V_MEAN = 14;
WIND_SEED = 2025;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);

nlobj = nlmpc(2, 2, 1);
nlobj.Model.StateFcn = 'sf_baseline';
nlobj.Model.NumberOfParameters = 2;
nlobj.Ts = Ts; nlobj.PredictionHorizon = cfg.mpc.Np; nlobj.ControlHorizon = cfg.mpc.Nc;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
nlobj.OV(1).Min = p.omega_mpc_min_physics; nlobj.OV(1).Max = p.omega_max;
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
nlobj.Optimization.SolverOptions.MaxIterations = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance = 1e-4;

integrators = struct('name', {'Euler (baseline)', 'RK4 (substage-sat)', 'RK4 (single post-hoc sat)'}, ...
    'step_fcn', {@wt_step, @wt_step_rk4, @wt_step_rk4_nosat});

results = struct('name', {}, 'rmse_omega_rpm', {}, 'pitch_activity_deg', {}, 'omega_hist', {});

for i = 1:numel(integrators)
    ig = integrators(i);
    fprintf('--- Running Baseline with %s plant integration ---\n', ig.name);

    x  = [p.omega_r * 0.97; 3.5];
    mv = x(2);
    omega_hist = zeros(N_steps,1);
    beta_hist  = zeros(N_steps,1);
    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);
        options.Parameters = {Vk, p};
        [mv, options, ~] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));

        x = ig.step_fcn(x, mv(1), Vk, p, Ts);   % ONLY this line differs
        omega_hist(k) = x(1) * 30/pi;
        beta_hist(k)  = x(2);
    end

    r.name = ig.name;
    r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    r.pitch_activity_deg = sum(abs(diff(beta_hist)));
    r.omega_hist = omega_hist;
    results(end+1) = r; %#ok<AGROW>

    fprintf('  RMSE=%.4f rpm  pitch_activity=%.1f deg\n\n', ...
        r.rmse_omega_rpm, r.pitch_activity_deg);
end

fprintf('============================================================\n');
fprintf('  SUMMARY (Euler = reference)\n');
fprintf('============================================================\n');
fprintf('%-28s %12s %16s\n', 'Variant', 'RMSE(rpm)', 'Pitch Act.(deg)');
for i = 1:numel(results)
    fprintf('%-28s %12.4f %16.1f\n', results(i).name, ...
        results(i).rmse_omega_rpm, results(i).pitch_activity_deg);
end
fprintf('============================================================\n');

pa_euler = results(1).pitch_activity_deg;
pa_rk4_substage = results(2).pitch_activity_deg;
pa_rk4_nosat    = results(3).pitch_activity_deg;

pa_diff_substage_pct = 100*abs(pa_rk4_substage - pa_euler)/pa_euler;
pa_diff_nosat_pct    = 100*abs(pa_rk4_nosat    - pa_euler)/pa_euler;

fprintf('\n  Pitch activity vs Euler:\n');
fprintf('    RK4 (substage-sat):        %.1f%% difference\n', pa_diff_substage_pct);
fprintf('    RK4 (single post-hoc sat): %.1f%% difference\n', pa_diff_nosat_pct);
fprintf('\n');
if pa_diff_nosat_pct < pa_diff_substage_pct / 2
    fprintf(['  HYPOTHESIS CONFIRMED: removing per-substage pitch-rate\n' ...
             '  saturation (applying it once per full step instead, matching\n' ...
             '  Euler''s semantics) brings pitch activity much closer to\n' ...
             '  Euler''s. The substage saturation IS the primary cause of the\n' ...
             '  pitch-activity discrepancy found by run_sensitivity_rk4.m.\n']);
else
    fprintf(['  HYPOTHESIS NOT CONFIRMED: removing per-substage saturation did\n' ...
             '  not substantially close the gap -- some other RK4-specific\n' ...
             '  effect is responsible; further investigation needed before\n' ...
             '  attributing the discrepancy to saturation semantics alone.\n']);
end

rel_diff_pct = 100 * abs(results(2).rmse_omega_rpm - results(1).rmse_omega_rpm) / ...
               results(1).rmse_omega_rpm;
max_traj_diff = max(abs(results(1).omega_hist - results(2).omega_hist));

% ── Write results/sensitivity_rk4_results.txt ───────────────────────────────
fid = fopen(txt_path, 'w');
fprintf(fid, 'SENSITIVITY CHECK — Euler vs RK4 Plant Integration (P1.2)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(Baseline controller, V=14 m/s, T=60s, seed=2025)\n');
fprintf(fid, '================================================\n\n');
for i = 1:numel(results)
    fprintf(fid, '[%s]\n', results(i).name);
    fprintf(fid, '  rmse_omega_rpm = %.4f\n', results(i).rmse_omega_rpm);
    fprintf(fid, '  pitch_activity_deg = %.1f\n\n', results(i).pitch_activity_deg);
end
fprintf(fid, '[Comparison]\n');
fprintf(fid, '  relative_rmse_difference_pct (Euler vs RK4 substage-sat) = %.2f\n', rel_diff_pct);
fprintf(fid, '  max_pointwise_trajectory_diff_rpm = %.4f\n', max_traj_diff);
fprintf(fid, '  pitch_activity_diff_pct_substage_sat = %.1f\n', pa_diff_substage_pct);
fprintf(fid, '  pitch_activity_diff_pct_nosat_variant = %.1f\n', pa_diff_nosat_pct);
fprintf(fid, '\n[Root-cause test]\n');
fprintf(fid, ['  A third variant (wt_step_rk4_nosat.m) applies pitch-rate\n' ...
              '  saturation ONCE per full step (Euler semantics) instead of\n' ...
              '  4x per RK4 substage, to isolate whether substage saturation\n' ...
              '  causes the pitch-activity discrepancy found in the original\n' ...
              '  2-way comparison (372.5 -> 172.0 deg, -54%%).\n']);
fclose(fid);
fprintf('\nWrote %s\n', txt_path);

end
