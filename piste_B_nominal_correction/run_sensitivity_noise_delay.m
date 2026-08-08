function results = run_sensitivity_noise_delay()
% RUN_SENSITIVITY_NOISE_DELAY  Measurement noise and communication delay
% robustness check (reproducibility review, P1.3), write
% results/sensitivity_noise_delay_results.txt.
%
%   results = run_sensitivity_noise_delay()
%
%   METHOD
%     Runs the Baseline controller in closed loop under 4 conditions,
%     identical wind realization and controller in every case:
%       (1) Nominal        — no noise, no delay (current paper protocol)
%       (2) Noise only      — Gaussian measurement noise added to the
%                              state fed into nlmpcmove (NOT to the true
%                              simulated plant state), representing
%                              sensor noise on omega/beta measurement
%       (3) Delay only       — one-step (Ts=0.1s) actuator/communication
%                              delay: the pitch command applied to the
%                              true plant at step k is the command
%                              COMPUTED at step k-1, not step k
%       (4) Noise + delay    — both effects combined
%
%   NOISE MAGNITUDE (chosen as plausible sensor-level values, not
%   tuned to any particular outcome)
%     sigma_omega = 0.01 rad/s  (~0.1 rpm, small relative to the
%                  turbulence-dominated ~1 rpm RMSE reported elsewhere)
%     sigma_beta  = 0.1 deg
%
%   INTERPRETATION
%     If RMSE degrades only mildly (see printed relative degradation)
%     under noise and/or delay, this supports the practical robustness
%     of the reported closed-loop results to these common real-world
%     imperfections. A large degradation would indicate the controller
%     is comparatively fragile to sensor noise or actuation delay and
%     would need explicit qualification.

fprintf('==========================================================\n');
fprintf('  SENSITIVITY CHECK: measurement noise + comm. delay (P1.3)\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'sensitivity_noise_delay_results.txt');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

T_SIM   = 60;
Ts      = cfg.mpc.Ts;
N_steps = round(T_SIM / Ts);
V_MEAN  = 14;
WIND_SEED = 2025;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);

sigma_omega = 0.01;   % rad/s
sigma_beta  = 0.1;    % deg

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

conditions = struct( ...
    'name',  {'Nominal', 'Noise only', 'Delay only', 'Noise + Delay'}, ...
    'noise', {false, true, false, true}, ...
    'delay', {false, false, true, true});

results = struct('name', {}, 'rmse_omega_rpm', {}, 'pitch_activity_deg', {});

rng(2025);   % fixed seed for the noise sequence, reused identically
             % across the 4 conditions where noise is enabled, for a
             % fair comparison (delay-only and nominal do not consume
             % random draws, so this does not affect their determinism)

for c = 1:numel(conditions)
    cnd = conditions(c);
    fprintf('--- Running Baseline: %s ---\n', cnd.name);

    x_true = [p.omega_r * 0.97; 3.5];
    mv = x_true(2);
    mv_prev_computed = mv;   % for one-step delay
    omega_hist = zeros(N_steps,1);
    beta_hist  = zeros(N_steps,1);
    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);

        % ── Measurement fed to the controller (possibly noisy) ─────────────
        if cnd.noise
            x_meas = x_true + [sigma_omega * randn(); sigma_beta * randn()];
            x_meas(1) = max(p.omega_min, min(p.omega_max, x_meas(1)));
            x_meas(2) = max(p.beta_cp_min, min(p.beta_cp_max, x_meas(2)));
        else
            x_meas = x_true;
        end

        options.Parameters = {Vk, p};
        [mv_new, options, ~] = nlmpcmove(nlobj, x_meas, mv, [p.omega_r,0], [], options);
        mv_new = max(p.beta_cp_min, min(p.beta_cp_max, mv_new));

        % ── Apply either the freshly computed command, or the PREVIOUS
        %    step's command (one-step actuator/communication delay) ───────
        if cnd.delay
            mv_to_apply = mv_prev_computed;
            mv_prev_computed = mv_new;
        else
            mv_to_apply = mv_new;
        end
        mv = mv_new;   % controller's own internal MV memory always advances

        x_true = wt_step(x_true, mv_to_apply(1), Vk, p, Ts);
        omega_hist(k) = x_true(1) * 30/pi;
        beta_hist(k)  = x_true(2);
    end

    r.name = cnd.name;
    r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    r.pitch_activity_deg = sum(abs(diff(beta_hist)));
    results(end+1) = r; %#ok<AGROW>

    fprintf('  RMSE=%.4f rpm  pitch_activity=%.1f deg\n\n', ...
        r.rmse_omega_rpm, r.pitch_activity_deg);
end

fprintf('============================================================\n');
fprintf('  SUMMARY (Nominal = reference)\n');
fprintf('============================================================\n');
fprintf('%-16s %12s %10s %16s\n', 'Condition', 'RMSE(rpm)', 'PA(deg)', 'RMSE degrad.(%)');
rmse_nom = results(1).rmse_omega_rpm;
for i = 1:numel(results)
    degrad = 100*(results(i).rmse_omega_rpm - rmse_nom)/rmse_nom;
    fprintf('%-16s %12.4f %10.1f %16.1f\n', results(i).name, ...
        results(i).rmse_omega_rpm, results(i).pitch_activity_deg, degrad);
end
fprintf('============================================================\n');

worst_degrad = max(100*([results(2:end).rmse_omega_rpm] - rmse_nom)/rmse_nom);
if worst_degrad < 10
    fprintf(['  INTERPRETATION: worst-case RMSE degradation under noise/delay\n' ...
             '  is under 10%% -- the reported closed-loop results appear\n' ...
             '  reasonably robust to these common real-world imperfections\n' ...
             '  at the tested magnitudes (sigma_omega=%.3f rad/s, sigma_beta=\n' ...
             '  %.2f deg, 1-step=%.1fs actuation delay).\n'], sigma_omega, sigma_beta, Ts);
else
    fprintf(['  INTERPRETATION: worst-case RMSE degradation exceeds 10%% -- this\n' ...
             '  should be explicitly qualified as a limitation; consider testing\n' ...
             '  additional noise/delay magnitudes or a disturbance observer.\n']);
end

% ── Write results/sensitivity_noise_delay_results.txt ───────────────────────
fid = fopen(txt_path, 'w');
fprintf(fid, 'SENSITIVITY CHECK — Measurement Noise + Communication Delay (P1.3)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(Baseline controller, V=14 m/s, T=60s, seed=2025)\n');
fprintf(fid, 'sigma_omega = %.4f rad/s, sigma_beta = %.2f deg, delay = 1 step (%.1fs)\n', ...
    sigma_omega, sigma_beta, Ts);
fprintf(fid, '================================================\n\n');
for i = 1:numel(results)
    degrad = 100*(results(i).rmse_omega_rpm - rmse_nom)/rmse_nom;
    fprintf(fid, '[%s]\n', results(i).name);
    fprintf(fid, '  rmse_omega_rpm = %.4f\n', results(i).rmse_omega_rpm);
    fprintf(fid, '  pitch_activity_deg = %.1f\n', results(i).pitch_activity_deg);
    fprintf(fid, '  rmse_degradation_pct_vs_nominal = %.1f\n\n', degrad);
end
fprintf(fid, '[Note]\n');
fprintf(fid, ['  Noise is applied only to the MEASUREMENT fed to nlmpcmove, not\n' ...
              '  to the true simulated plant state -- this isolates sensor-noise\n' ...
              '  sensitivity from any plant-model-mismatch question. Delay is\n' ...
              '  modeled as applying the PREVIOUS step''s computed command to the\n' ...
              '  true plant, a standard one-step actuator/communication delay\n' ...
              '  approximation, not a full transport-delay model.\n']);
fclose(fid);
fprintf('\nWrote %s\n', txt_path);

end
