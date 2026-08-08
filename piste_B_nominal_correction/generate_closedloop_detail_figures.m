function generate_closedloop_detail_figures()
% GENERATE_CLOSEDLOOP_DETAIL_FIGURES  Full time-series closed-loop
% figures for the predict()-bypass series, in the same style as the
% original project's Stage 3 figures (Fig1_S3_SpeedTracking,
% Fig2_S3_PowerOutput, Fig3_S3_PitchControl, Fig5_S3_MetricsSummary).
%
%   generate_closedloop_detail_figures()
%
%   SCOPE — MANUAL-BYPASS CONTROLLERS ONLY
%     Only the verified manual (no predict()) versions of each
%     surrogate are re-simulated here, alongside Baseline. The
%     predict()-based versions are NOT re-run: they are already
%     confirmed catastrophically slow/unusable (see
%     docs/experiment_log.md) and re-running them for plotting alone
%     would take hours (LSTM predict() alone: ~318s/step).
%
%   ARCHITECTURES INCLUDED
%     Baseline, MLP-residual (manual), GP-residual (manual, N_sub=50),
%     SW-MLP (manual), PINN-v2 (manual), TCN (manual), LSTM (manual)
%
%   OUTPUT (saved to figures/)
%     Fig1_V3_SpeedTracking.png   omega(t), all controllers overlaid
%     Fig2_V3_PitchControl.png    beta(t), all controllers overlaid
%     Fig3_V3_PowerOutput.png     P(t) = 0.5*rho*A*Cp*V^3, all controllers
%     Fig5_V3_MetricsSummary.png  bar panel: RMSE, mean CPU, pitch activity
%
%   PREREQUISITES
%     All model files/mats from the predict()-bypass series must be
%     present: stage2_residual_model.mat, stage2_gp_residual_model.mat
%     (N_sub=50 version), stage2_models_v2.mat (SW-MLP, PINN-v2, TCN),
%     stage2_models.mat (LSTM), plus all extract_*.m /
%     manual_forward_generic.m / tcn_forward_manual.m /
%     lstm_forward_manual.m helper functions on path.

fprintf('==========================================================\n');
fprintf('  Generating detailed closed-loop time-series figures\n');
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

T_SIM = 60; V_MEAN = 14; WIND_SEED = 2025;
N_steps = round(T_SIM / cfg.mpc.Ts);
V_wind  = kaimal_wind(V_MEAN, T_SIM, cfg.mpc.Ts, WIND_SEED);
t_vec   = (0:N_steps-1) * cfg.mpc.Ts;

% ── Load all required models ────────────────────────────────────────────────
fprintf('Loading models...\n');
S_res = load('stage2_residual_model.mat');       mdl_res = S_res.mdl;
S_gp  = load('stage2_gp_residual_model.mat');    mdl_gp  = S_gp.mdl;
mdl_gp_manual = extract_gp_weights(mdl_gp);

V2 = load('stage2_models_v2.mat');
mdl_swmlp   = V2.mdl_swmlp;
mdl_pinn_v2 = V2.mdl_pinn_v2;
mdl_tcn     = V2.mdl_tcn;
mdl_swmlp_manual = extract_dlnetwork_generic(mdl_swmlp,  'net');
mdl_pinn_manual  = extract_dlnetwork_generic(mdl_pinn_v2,'net');
mdl_tcn_manual   = extract_tcn_weights(mdl_tcn);

V1 = load('stage2_models.mat');
mdl_lstm = V1.mdl_lstm;
mdl_lstm_manual = extract_lstm_weights(mdl_lstm);

mdl_res_manual = extract_residual_weights(mdl_res);   % NOTE: sf_residual_manual.m
% expects fields W1/b1/W2/b2/W3/b3 (from extract_residual_weights.m),
% NOT manual_W/manual_b/manual_act (from extract_dlnetwork_generic.m) --
% using the matching extractor here, not the generic one, to avoid a
% field-name mismatch at simulation time.

fprintf('\n');

% ── Build controllers ────────────────────────────────────────────────────────
Np1 = cfg.mpc.Np;  Nc1 = cfg.mpc.Nc;  Ts = cfg.mpc.Ts;     % V1 settings (residual, LSTM)
Np2 = cfg.mpc2.Np; Nc2 = cfg.mpc2.Nc;                       % V2 settings (SW-MLP, PINN-v2, TCN)

nlobj_baseline = build_ctrl('sf_baseline', 2, p, cfg, Np1, Nc1, Ts, true);
nlobj_res      = build_ctrl('sf_residual_manual', 4, p, cfg, Np1, Nc1, Ts, false);
nlobj_gp       = build_ctrl('sf_gp_residual_manual', 4, p, cfg, Np1, Nc1, Ts, false);
nlobj_swmlp    = build_ctrl('sf_swmlp_manual', 2, p, cfg, Np2, Nc2, Ts, false);
nlobj_pinn     = build_ctrl('sf_pinn_manual',  2, p, cfg, Np2, Nc2, Ts, false);
nlobj_tcn      = build_ctrl('sf_tcn_manual',   2, p, cfg, Np2, Nc2, Ts, false);
nlobj_lstm     = build_ctrl('sf_lstm_manual',  3, p, cfg, Np1, Nc1, Ts, false);

controllers = struct( ...
    'name',  {'Baseline', 'MLP-residual', 'GP-residual', 'SW-MLP', 'PINN-v2', 'TCN', 'LSTM'}, ...
    'nlobj', {nlobj_baseline, nlobj_res, nlobj_gp, nlobj_swmlp, nlobj_pinn, nlobj_tcn, nlobj_lstm}, ...
    'kind',  {'baseline', 'residual', 'gp', 'swmlp', 'pinn', 'tcn', 'lstm'});

colors = struct( ...
    'Baseline',     [0.30 0.30 0.30], ...
    'MLP_residual', [0.85 0.33 0.10], ...
    'GP_residual',  [0.47 0.67 0.19], ...
    'SW_MLP',       [0.00 0.45 0.74], ...
    'PINN_v2',      [0.49 0.18 0.56], ...
    'TCN',          [0.93 0.69 0.13], ...
    'LSTM',         [0.64 0.08 0.18]);
color_keys = {'Baseline','MLP_residual','GP_residual','SW_MLP','PINN_v2','TCN','LSTM'};

seq_len = mdl_swmlp.seq_len;   % assume shared seq_len across sequence-based surrogates

% ── Run all controllers, recording full time histories ─────────────────────
traj = struct();
for c = 1:numel(controllers)
    tc = controllers(c);
    fprintf('--- Simulating %s ---\n', tc.name);

    x  = [p.omega_r * 0.97; 3.5];   % FIX: matches stage3_run_simulation.m's
    % original initial condition (slight under-speed, non-zero pitch).
    % Starting exactly at [omega_r; 0] (as this script previously did)
    % put the very first nlmpcmove call at the omega_max boundary with
    % zero pitch margin, which was found to make the problem infeasible
    % from step 1 for several controllers (ExitFlag<0, 600/600) --
    % confirmed by direct comparison against this file.
    mv = x(2);   % FIX: matches original's u_prev = x(2) convention,
    % not an arbitrary mv=0 start
    omega_hist = zeros(N_steps,1);
    beta_hist  = zeros(N_steps,1);
    power_hist = zeros(N_steps,1);
    cpu_hist   = zeros(N_steps,1);
    mv_hist       = zeros(N_steps,1);   % DIAGNOSTIC: actual pitch command issued
    exitflag_hist = zeros(N_steps,1);   % DIAGNOSTIC: solver ExitFlag each step
    options = nlmpcmoveopt;

    seq_buf = repmat([x(1), x(2), V_wind(1), mv], seq_len, 1);

    for k = 1:N_steps
        Vk = V_wind(k);
        switch tc.kind
            case 'baseline'
                options.Parameters = {Vk, p};
            case 'residual'
                options.Parameters = {Vk, mdl_res_manual, p, Ts};
            case 'gp'
                options.Parameters = {Vk, mdl_gp_manual, p, Ts};
            case 'swmlp'
                mdl_swmlp_manual.seq_buf = seq_buf;
                options.Parameters = {Vk, mdl_swmlp_manual};
            case 'pinn'
                options.Parameters = {Vk, mdl_pinn_manual};
            case 'tcn'
                mdl_tcn_manual.seq_buf = seq_buf;
                options.Parameters = {Vk, mdl_tcn_manual};
            case 'lstm'
                options.Parameters = {Vk, mdl_lstm_manual, seq_buf};
        end

        t0 = tic;
        [mv, options, info] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_hist(k) = toc(t0) * 1000;

        % FIX: clamp to physical pitch limits, matching
        % stage3_run_simulation.m's u_opt = max(beta_min, min(beta_max, u_opt))
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));

        mv_hist(k) = mv(1);
        if isfield(info, 'ExitFlag')
            exitflag_hist(k) = info.ExitFlag;
        end

        if ismember(tc.kind, {'swmlp','tcn'})
            seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
        end

        x = wt_step(x, mv(1), Vk, p, Ts);
        omega_hist(k) = x(1) * 30/pi;
        beta_hist(k)  = x(2);

        lambda = p.R * x(1) / Vk;
        Cp_k   = cp_lambda_beta(lambda, x(2));
        power_hist(k) = 0.5 * p.rho * p.A_rotor * Cp_k * Vk^3 / 1e6;   % MW

        if mod(k, 200) == 0
            fprintf('  step %d/%d\n', k, N_steps);
        end
    end

    key = strrep(tc.name, '-', '_');
    traj.(key).omega = omega_hist;
    traj.(key).beta  = beta_hist;
    traj.(key).power = power_hist;
    traj.(key).cpu   = cpu_hist;
    traj.(key).mv    = mv_hist;
    traj.(key).exitflag = exitflag_hist;
    traj.(key).rmse  = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    traj.(key).pitch_activity = sum(abs(diff(beta_hist)));
    traj.(key).mean_cpu = mean(cpu_hist);

    fprintf('  RMSE=%.4f rpm  mean_cpu=%.1fms  pitch_activity=%.1fdeg\n', ...
        traj.(key).rmse, traj.(key).mean_cpu, traj.(key).pitch_activity);
    fprintf(['  DIAGNOSTIC: mv range=[%.3f, %.3f] deg, std=%.4f  |  ' ...
             'ExitFlag: >0(converged)=%d  0(maxiter)=%d  <0(infeasible)=%d\n\n'], ...
        min(mv_hist), max(mv_hist), std(mv_hist), ...
        sum(exitflag_hist > 0), sum(exitflag_hist == 0), sum(exitflag_hist < 0));
end

fig_dir = fullfile(pwd, 'figures');
if ~isfolder(fig_dir), mkdir(fig_dir); end
FMT = '-dpng'; RES = '-r150';

% ── Fig 1: Speed tracking ────────────────────────────────────────────────────
f1 = figure('Color','w','Position',[40 40 1100 500]);
hold on;
for i = 1:numel(color_keys)
    k = color_keys{i};
    plot(t_vec, traj.(k).omega, 'Color', colors.(k), 'LineWidth', 1.3, ...
         'DisplayName', strrep(k,'_','-'));
end
yline(p.omega_r*30/pi, 'k--', 'Rated speed', 'LabelHorizontalAlignment','left', 'FontSize',9);
xlabel('Time (s)'); ylabel('Rotor speed \omega (rpm)');
title('Closed-Loop Rotor Speed Tracking — All Manual-Bypass Controllers', 'FontWeight','bold');
legend('Location','eastoutside','FontSize',9); grid on;
print(f1, fullfile(fig_dir,'Fig1_V3_SpeedTracking'), FMT, RES);
fprintf('Saved Fig1_V3_SpeedTracking.png\n');

% ── Fig 2: Pitch control ─────────────────────────────────────────────────────
f2 = figure('Color','w','Position',[40 40 1100 500]);
hold on;
for i = 1:numel(color_keys)
    k = color_keys{i};
    plot(t_vec, traj.(k).beta, 'Color', colors.(k), 'LineWidth', 1.3, ...
         'DisplayName', strrep(k,'_','-'));
end
xlabel('Time (s)'); ylabel('Pitch angle \beta (deg)');
title('Closed-Loop Pitch Control — All Manual-Bypass Controllers', 'FontWeight','bold');
legend('Location','eastoutside','FontSize',9); grid on;
print(f2, fullfile(fig_dir,'Fig2_V3_PitchControl'), FMT, RES);
fprintf('Saved Fig2_V3_PitchControl.png\n');

% ── Fig 3: Power output ──────────────────────────────────────────────────────
f3 = figure('Color','w','Position',[40 40 1100 500]);
hold on;
for i = 1:numel(color_keys)
    k = color_keys{i};
    plot(t_vec, traj.(k).power, 'Color', colors.(k), 'LineWidth', 1.3, ...
         'DisplayName', strrep(k,'_','-'));
end
xlabel('Time (s)'); ylabel('Power output (MW)');
title('Closed-Loop Power Output — All Manual-Bypass Controllers', 'FontWeight','bold');
legend('Location','eastoutside','FontSize',9); grid on;
print(f3, fullfile(fig_dir,'Fig3_V3_PowerOutput'), FMT, RES);
fprintf('Saved Fig3_V3_PowerOutput.png\n');

% ── Fig 5: Metrics summary panel ─────────────────────────────────────────────
f5 = figure('Color','w','Position',[40 40 1300 460]);
names_plot = cellfun(@(k) strrep(k,'_','-'), color_keys, 'UniformOutput', false);
rmse_vals  = cellfun(@(k) traj.(k).rmse, color_keys);
cpu_vals   = cellfun(@(k) traj.(k).mean_cpu, color_keys);
pa_vals    = cellfun(@(k) traj.(k).pitch_activity, color_keys);

subplot(1,3,1)
b = bar(rmse_vals, 'FaceColor','flat');
for i=1:numel(color_keys), b.CData(i,:) = colors.(color_keys{i}); end
set(gca,'XTickLabel',names_plot,'XTickLabelRotation',30,'FontSize',8);
ylabel('RMSE (rpm)'); title('Tracking Error'); grid on;

subplot(1,3,2)
b2 = bar(cpu_vals, 'FaceColor','flat');
for i=1:numel(color_keys), b2.CData(i,:) = colors.(color_keys{i}); end
set(gca,'XTickLabel',names_plot,'XTickLabelRotation',30,'FontSize',8,'YScale','log');
ylabel('Mean CPU/step (ms, log)'); title('Computational Cost'); grid on;
yline(100,'r:','T_s budget','FontSize',7);

subplot(1,3,3)
b3 = bar(pa_vals, 'FaceColor','flat');
for i=1:numel(color_keys), b3.CData(i,:) = colors.(color_keys{i}); end
set(gca,'XTickLabel',names_plot,'XTickLabelRotation',30,'FontSize',8);
ylabel('Cumulative pitch activity (deg)'); title('Actuator Duty Cycle'); grid on;

sgtitle('Manual-Bypass Controllers — Metrics Summary', 'FontWeight','bold');
print(f5, fullfile(fig_dir,'Fig5_V3_MetricsSummary'), FMT, RES);
fprintf('Saved Fig5_V3_MetricsSummary.png\n');

save('stage3_v3_trajectories.mat', 'traj', 't_vec');
fprintf('\nAll figures saved to %s\n', fig_dir);
fprintf('Raw trajectories saved to stage3_v3_trajectories.mat\n');

end

function nlobj = build_ctrl(stateFcnName, nParams, p, cfg, Np, Nc, Ts, isBaseline)
nlobj = nlmpc(2, 2, 1);
nlobj.Model.StateFcn = stateFcnName;
nlobj.Model.NumberOfParameters = nParams;
nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
if isBaseline
    nlobj.OV(1).Min = p.omega_mpc_min_physics; nlobj.OV(1).Max = p.omega_max;
else
    nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
end
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
nlobj.Optimization.SolverOptions.MaxIterations = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance = 1e-4;
end
