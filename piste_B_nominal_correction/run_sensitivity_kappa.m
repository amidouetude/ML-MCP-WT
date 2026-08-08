function results = run_sensitivity_kappa()
% RUN_SENSITIVITY_KAPPA  Sweep the GP-uncertainty cost weight kappa
% (Section 5.3, cost_gp.m) and report closed-loop RMSE/pitch
% activity/CPU sensitivity, write results/sensitivity_kappa_results.txt.
%
%   results = run_sensitivity_kappa()
%
%   WHY THIS USES THE ORIGINAL predict()-BASED GP-v2 (not the manual
%   bypass built for the diagnostic series)
%     Testing kappa sensitivity faithfully requires the ORIGINAL
%     uncertainty-penalized cost formulation (cost_gp.m calling
%     predict() for the GP predictive variance term), not the mean-only
%     manual bypass built in piste_B_nominal_correction/ (which never
%     needed variance, only the posterior mean, since it was not used
%     with an uncertainty-penalized cost). Building a manual GP
%     variance formula (requiring the kernel matrix's Cholesky factor,
%     not currently extracted anywhere in this project) was judged
%     higher-risk than accepting the known predict()-based slowdown for
%     a short, one-off sensitivity check -- consistent with this
%     project's practice of using verified, known-correct
%     implementations over new unverified ones when time allows.
%
%   PROTOCOL — SHORTENED horizon to keep total runtime manageable
%     T_SIM = 20s (vs. 60s used elsewhere in this project) per kappa
%     value; kappa in {0, 0.2, 0.5, 0.8, 1.0} (0.8 is the value used
%     throughout the rest of this paper). Expect several minutes total
%     runtime given predict()-based GP-v2's known per-step cost.
%
%   PREREQUISITES
%     stage2_models_v2.mat (contains mdl_gp_v2, the ORIGINAL N_sub=400
%     GP-v2 model) in the current folder or on path.

fprintf('==========================================================\n');
fprintf('  SENSITIVITY CHECK: GP-uncertainty cost weight kappa (P1.1)\n');
fprintf('  NOTE: uses predict()-based GP-v2 -- expect several minutes\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'sensitivity_kappa_results.txt');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

if ~isfile('stage2_models_v2.mat')
    error('stage2_models_v2.mat not found.');
end
V2 = load('stage2_models_v2.mat');
mdl_gp_v2 = V2.mdl_gp_v2;

T_SIM   = 20;   % shortened vs. the 60s used elsewhere, for tractable runtime
Ts      = cfg.mpc.Ts;
N_steps = round(T_SIM / Ts);
V_MEAN  = 14;
WIND_SEED = 2025;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);
omega_ref_radps = p.omega_r;

kappa_values = [0, 0.2, 0.5, 0.8, 1.0];

Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc;
nlobj = nlmpc(2, 2, 1);
nlobj.Model.StateFcn = 'sf_gp';
nlobj.Model.NumberOfParameters = 7;   % V, mdl, omega_ref, kappa, Q, Q2, R
                                        % [UPDATED -- P0.1 fix, cost_gp.m
                                        % no longer hardcodes Q/Q2/R]
nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.Optimization.CustomCostFcn = 'cost_gp';
nlobj.Optimization.ReplaceStandardCost = true;
nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
nlobj.Optimization.SolverOptions.MaxIterations = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance = 1e-4;

results = struct('kappa', {}, 'rmse_omega_rpm', {}, 'pitch_activity_deg', {}, 'mean_cpu_ms', {});

for ki = 1:numel(kappa_values)
    kappa = kappa_values(ki);
    fprintf('--- Running GP-v2, kappa=%.1f (%d/%d) ---\n', kappa, ki, numel(kappa_values));

    x  = [p.omega_r * 0.97; 3.5];
    mv = x(2);
    omega_hist = zeros(N_steps,1);
    beta_hist  = zeros(N_steps,1);
    mv_hist    = zeros(N_steps,1);   % DIAGNOSTIC
    exitflag_hist = zeros(N_steps,1); % DIAGNOSTIC
    cpu_hist   = zeros(N_steps,1);
    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);
        options.Parameters = {Vk, mdl_gp_v2, omega_ref_radps, kappa, cfg.mpc.Q, 0.01, cfg.mpc.R};
        % [UPDATED -- P0.1 fix: Q/Q2/R now passed explicitly, read from
        % cfg.mpc, instead of relying on cost_gp.m's former hardcoded
        % values -- these MUST match stage0_config.m for results to be
        % meaningful, and now do so by construction rather than by
        % manually-maintained duplication.

        t0 = tic;
        [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_hist(k) = toc(t0) * 1000;
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
        mv_hist(k) = mv(1);
        if isfield(info, 'ExitFlag'), exitflag_hist(k) = info.ExitFlag; end

        x = wt_step(x, mv(1), Vk, p, Ts);
        omega_hist(k) = x(1) * 30/pi;
        beta_hist(k)  = x(2);

        if mod(k, 50) == 0
            fprintf('    step %d/%d  cpu=%.0fms\n', k, N_steps, cpu_hist(k));
        end
    end

    fprintf('  DIAGNOSTIC: mv range=[%.3f, %.3f] deg, std=%.4f  |  ExitFlag: >0=%d  0=%d  <0=%d\n', ...
        min(mv_hist), max(mv_hist), std(mv_hist), ...
        sum(exitflag_hist>0), sum(exitflag_hist==0), sum(exitflag_hist<0));

    r.kappa = kappa;
    r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    r.pitch_activity_deg = sum(abs(diff(beta_hist)));
    r.mean_cpu_ms = mean(cpu_hist);
    results(end+1) = r; %#ok<AGROW>

    fprintf('  DONE: RMSE=%.4f rpm  PA=%.1f deg  mean_cpu=%.1fms\n\n', ...
        r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cpu_ms);
end

fprintf('============================================================\n');
fprintf('  SUMMARY\n');
fprintf('============================================================\n');
fprintf('%-8s %12s %10s %14s\n', 'kappa', 'RMSE(rpm)', 'PA(deg)', 'mean_cpu(ms)');
for i = 1:numel(results)
    fprintf('%-8.1f %12.4f %10.1f %14.1f\n', results(i).kappa, ...
        results(i).rmse_omega_rpm, results(i).pitch_activity_deg, results(i).mean_cpu_ms);
end
fprintf('============================================================\n');

rmse_range = max([results.rmse_omega_rpm]) - min([results.rmse_omega_rpm]);
rmse_at_08 = results([results.kappa]==0.8).rmse_omega_rpm;
fprintf('  RMSE range across kappa in [0,1]: %.4f rpm\n', rmse_range);
fprintf('  kappa=0.8 (value used throughout the paper): RMSE=%.4f rpm\n', rmse_at_08);
if rmse_range / rmse_at_08 < 0.10
    fprintf(['  INTERPRETATION: RMSE varies by less than 10%% of its kappa=0.8\n' ...
             '  value across the full [0,1] sweep -- the paper''s fixed\n' ...
             '  kappa=0.8 choice does not appear to be a fragile or\n' ...
             '  cherry-picked operating point over this %ds window.\n'], T_SIM);
else
    fprintf(['  INTERPRETATION: RMSE varies by more than 10%% across the kappa\n' ...
             '  sweep -- the sensitivity to kappa should be reported\n' ...
             '  explicitly rather than presenting kappa=0.8 as robust.\n']);
end
fprintf(['  NOTE: this sweep uses a shortened %ds window (vs 60s elsewhere)\n' ...
         '  for tractable runtime with predict()-based GP-v2 -- treat as\n' ...
         '  indicative, not a full replication of the paper''s main-text\n' ...
         '  GP-v2 protocol.\n'], T_SIM);

% ── Write results/sensitivity_kappa_results.txt ─────────────────────────────
fid = fopen(txt_path, 'w');
fprintf(fid, 'SENSITIVITY CHECK — GP-Uncertainty Cost Weight kappa (P1.1)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(GP-v2 controller, V=14 m/s, T=%ds [shortened], seed=2025)\n', T_SIM);
fprintf(fid, '================================================\n\n');
for i = 1:numel(results)
    fprintf(fid, '[kappa=%.1f]\n', results(i).kappa);
    fprintf(fid, '  rmse_omega_rpm = %.4f\n', results(i).rmse_omega_rpm);
    fprintf(fid, '  pitch_activity_deg = %.1f\n', results(i).pitch_activity_deg);
    fprintf(fid, '  mean_cpu_ms = %.1f\n\n', results(i).mean_cpu_ms);
end
fprintf(fid, '[Comparison]\n');
fprintf(fid, '  rmse_range_rpm = %.4f\n', rmse_range);
fprintf(fid, '  rmse_range_pct_of_kappa08 = %.1f\n', 100*rmse_range/rmse_at_08);
fprintf(fid, '\n[Note]\n');
fprintf(fid, ['  Shortened %ds window (vs 60s used elsewhere in this project)\n' ...
              '  for tractable runtime with the original predict()-based\n' ...
              '  GP-v2 (N_sub=400) uncertainty-penalized cost. Indicative,\n' ...
              '  not a full replication of the main-text protocol.\n'], T_SIM);
fclose(fid);
fprintf('\nWrote %s\n', txt_path);

end
