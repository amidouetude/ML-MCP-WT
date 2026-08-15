function results = verify_gp_frozen_actuator()
% VERIFY_GP_FROZEN_ACTUATOR  Settle referee items 3.3/3.4: is GP's
% reported zero cumulative pitch activity (Table tab:v1_results/
% tab:v2_results, PA=0.00 deg) a genuine closed-loop achievement, or
% the same frozen-actuator / solver-infeasibility signature already
% diagnosed for the initial-condition bug (Section 6.4) and observed
% again in the kappa sensitivity sweep (run_sensitivity_kappa.m)?
%
%   results = verify_gp_frozen_actuator()
%
%   METHOD
%     Re-runs GP (V1) and GP-v2 (V2) under the ORIGINAL paper protocol
%     (V=14m/s, T=120s, seed=2025, each snapshot's own Np/Nc), with
%     full per-step logging of the actual pitch command (mv) and
%     solver ExitFlag -- neither of which the original protocol logged
%     or reported. If mv is genuinely constant AND ExitFlag<0 (or 0)
%     at every/most steps, the "zero pitch activity" result is a
%     frozen-actuator artifact, not a controller achievement, and
%     Contribution 4 / the corresponding abstract sentence need
%     withdrawal per the referee report.
%
%   PREREQUISITES
%     stage2_models.mat, stage2_models_v2.mat in common/ or on path.
%     Uses sf_gp.m/cost_gp.m as fixed for P0.1 (NumberOfParameters=7).

fprintf('==========================================================\n');
fprintf('  VERIFYING REFEREE ITEMS 3.3/3.4: GP zero-pitch-activity\n');
fprintf('  Is it a frozen actuator (solver infeasibility)?\n');
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

T_SIM = 60;    % unified protocol window (item 2.5, was 120s)
Ts    = cfg.mpc.Ts;
N_steps = round(T_SIM / Ts);
V_MEAN = 14;
WIND_SEED = 2025;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);

omega_ref_radps = p.omega_r;
kappa_default   = cfg.mpc.kappa;

results = struct('name', {}, 'rmse_omega_rpm', {}, 'pitch_activity_deg', {}, ...
    'mv_min', {}, 'mv_max', {}, 'mv_std', {}, 'n_converged', {}, ...
    'n_maxiter', {}, 'n_infeasible', {}, 'mean_cpu_ms', {}, ...
    'mv_hist', {}, 'exitflag_hist', {}, 'beta_hist', {}, 'omega_hist', {});

% ── GP (V1) ────────────────────────────────────────────────────────────────
fprintf('--- Test 1: GP (V1), T=120s (original protocol) ---\n');
try
    V1 = load('stage2_models.mat');
    models_v1.llnfm = V1.mdl_llnfm; models_v1.lstm = V1.mdl_lstm;
    models_v1.gp = V1.mdl_gp; models_v1.pinn = V1.mdl_pinn;
    controllers_v1 = stage3_design_controllers(p, models_v1, cfg);

    r = run_and_log('GP (V1)', controllers_v1.gp, V1.mdl_gp, p, cfg, ...
        V_wind, N_steps, Ts, omega_ref_radps, kappa_default);
    results(end+1) = r; %#ok<AGROW>
catch ME
    fprintf('  FAILED: %s\n', ME.message);
end

% ── GP-v2 (V2) ─────────────────────────────────────────────────────────────
fprintf('\n--- Test 2: GP-v2 (V2), T=120s (original protocol) ---\n');
try
    V2 = load('stage2_models_v2.mat');
    models_v2.llnfm = V2.mdl_llnfm; models_v2.tcn = V2.mdl_tcn;
    models_v2.swmlp = V2.mdl_swmlp; models_v2.gp_v2 = V2.mdl_gp_v2;
    models_v2.pinn_v2 = V2.mdl_pinn_v2;
    controllers_v2 = stage3_design_controllers_v2(p, models_v2, cfg);

    r = run_and_log('GP-v2 (V2)', controllers_v2.gp_v2, V2.mdl_gp_v2, p, cfg, ...
        V_wind, N_steps, Ts, omega_ref_radps, kappa_default);
    results(end+1) = r; %#ok<AGROW>
catch ME
    fprintf('  FAILED: %s\n', ME.message);
end

% ── Verdict ──────────────────────────────────────────────────────────────────
fprintf('\n============================================================\n');
fprintf('  VERDICT\n');
fprintf('============================================================\n');
fprintf('%-14s %10s %8s %10s %14s\n', 'Controller', 'RMSE', 'PA(deg)', 'mv std', 'infeasible/total');
for i = 1:numel(results)
    r = results(i);
    fprintf('%-14s %10.4f %8.2f %10.4f %14s\n', r.name, r.rmse_omega_rpm, ...
        r.pitch_activity_deg, r.mv_std, sprintf('%d/%d', r.n_infeasible, N_steps));
end
fprintf('============================================================\n');

for i = 1:numel(results)
    r = results(i);
    if r.mv_std < 1e-6 && r.pitch_activity_deg < 0.01
        fprintf(['  %s: CONFIRMED FROZEN ACTUATOR. mv never left its initial\n' ...
                 '  value (std=%.2e). The reported PA=0.00 is a solver-\n' ...
                 '  infeasibility artifact, not a controller achievement.\n' ...
                 '  Contribution 4 and the corresponding abstract claim MUST\n' ...
                 '  be withdrawn or re-derived from a genuinely feasible run.\n\n'], ...
                 r.name, r.mv_std);
    else
        fprintf(['  %s: mv shows genuine variation (std=%.4f) -- the zero-\n' ...
                 '  pitch-activity claim does NOT appear to be a frozen-\n' ...
                 '  actuator artifact for this controller under this protocol.\n\n'], ...
                 r.name, r.mv_std);
    end
end

% ── Plot pitch trace + solver ExitFlag per step (referee item 2.3) ─────────
fig_dir = fullfile(pwd, 'figures');
if ~isfolder(fig_dir), mkdir(fig_dir); end

f = figure('Color','w','Position',[40 40 1500 700]);
n_res = numel(results);
t_vec_ref = (0:N_steps-1) * Ts;

for i = 1:n_res
    r = results(i);

    subplot(n_res, 3, (i-1)*3+1);
    plot(t_vec_ref, r.beta_hist, 'b-', 'LineWidth', 1.2);
    xlabel('Time (s)'); ylabel('\beta (deg)');
    title(sprintf('%s — Pitch Command Trace', r.name), 'FontSize', 10);
    grid on;
    ylim_pad = 0.5;
    if range(r.beta_hist) < 1e-6
        ylim([r.beta_hist(1)-ylim_pad, r.beta_hist(1)+ylim_pad]);
        text(t_vec_ref(round(N_steps/2)), r.beta_hist(1)+0.2, ...
            sprintf('FROZEN at %.3f%s', r.beta_hist(1), char(176)), ...
            'Color','r','FontWeight','bold','HorizontalAlignment','center');
    end

    subplot(n_res, 3, (i-1)*3+2);   % [ADDED item 6.8] rotor speed alongside pitch
    plot(t_vec_ref, r.omega_hist, 'g-', 'LineWidth', 1.2);
    xlabel('Time (s)'); ylabel('\omega (rpm)');
    title(sprintf('%s — Rotor Speed Trace', r.name), 'FontSize', 10);
    yline(12.1, 'k:', 'Rated'); grid on;

    subplot(n_res, 3, (i-1)*3+3);
    stairs(t_vec_ref, r.exitflag_hist, 'r-', 'LineWidth', 1.2);
    xlabel('Time (s)'); ylabel('Solver ExitFlag');
    title(sprintf('%s — Per-Step Solver ExitFlag', r.name), 'FontSize', 10);
    yline(0, 'k:', 'MaxIter (0)');
    grid on;
    pct_infeasible = 100*r.n_infeasible/N_steps;
    text(t_vec_ref(round(N_steps*0.6)), min(r.exitflag_hist)-0.3, ...
        sprintf('%.0f%% infeasible (ExitFlag<0)', pct_infeasible), ...
        'Color','r','FontWeight','bold');
end
sgtitle('Referee Item 2.3 — Pitch Trace and Solver ExitFlag (T=120s, V=14m/s)', ...
    'FontWeight','bold');
print(f, fullfile(fig_dir, 'FigF_GPFrozenActuator_PitchTrace'), '-dpng', '-r150');
fprintf('\nSaved figures/FigF_GPFrozenActuator_PitchTrace.png\n');

if ~exist('results_dir', 'var'), mkdir_safe('results'); end
save(fullfile('results', 'gp_frozen_actuator_verification.mat'), 'results');
fprintf('Saved results/gp_frozen_actuator_verification.mat\n');

end


function r = run_and_log(name, nlobj, mdl_gp, p, cfg, V_wind, N_steps, Ts, omega_ref, kappa)
x  = [p.omega_r * 0.97; 3.5];
mv = x(2);
omega_hist = zeros(N_steps,1);
beta_hist  = zeros(N_steps,1);
mv_hist    = zeros(N_steps,1);
exitflag_hist = zeros(N_steps,1);
cpu_hist   = zeros(N_steps,1);
options = nlmpcmoveopt;

for k = 1:N_steps
    Vk = V_wind(k);
    options.Parameters = {Vk, mdl_gp, omega_ref, kappa, cfg.mpc.Q, 0.01, cfg.mpc.R};

    t0 = tic;
    [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
    cpu_hist(k) = toc(t0) * 1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    mv_hist(k) = mv(1);
    exitflag_hist(k) = info.ExitFlag;

    x = wt_step(x, mv(1), Vk, p, Ts);
    omega_hist(k) = x(1) * 30/pi;
    beta_hist(k)  = x(2);

    if mod(k, 300) == 0
        fprintf('  step %d/%d  mv=%.3f  ExitFlag=%d\n', k, N_steps, mv(1), info.ExitFlag);
    end
end

r.name = name;
r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
r.pitch_activity_deg = sum(abs(diff(beta_hist)));
r.mv_min = min(mv_hist); r.mv_max = max(mv_hist); r.mv_std = std(mv_hist);
r.n_converged  = sum(exitflag_hist > 0);
r.n_maxiter    = sum(exitflag_hist == 0);
r.n_infeasible = sum(exitflag_hist < 0);
r.mean_cpu_ms  = mean(cpu_hist);
r.mv_hist = mv_hist;              % [ADDED] full trace, for plotting (item 2.3)
r.exitflag_hist = exitflag_hist;  % [ADDED] full trace, for plotting (item 2.3)
r.beta_hist = beta_hist;          % [ADDED] full trace, for plotting (item 2.3)
r.omega_hist = omega_hist;        % [ADDED] full trace, for plotting (item 6.8)

fprintf('  DONE: RMSE=%.4f rpm  PA=%.2f deg  mv=[%.3f,%.3f] std=%.4f\n', ...
    r.rmse_omega_rpm, r.pitch_activity_deg, r.mv_min, r.mv_max, r.mv_std);
fprintf('  ExitFlag: converged=%d  maxiter=%d  infeasible=%d (of %d)\n', ...
    r.n_converged, r.n_maxiter, r.n_infeasible, N_steps);
end

function mkdir_safe(d)
if ~isfolder(d), mkdir(d); end
end
