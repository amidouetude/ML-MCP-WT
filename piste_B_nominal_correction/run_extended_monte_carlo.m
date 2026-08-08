function results = run_extended_monte_carlo()
% RUN_EXTENDED_MONTE_CARLO  Multi-wind-speed, multi-seed Monte Carlo
% closed-loop evaluation of all 7 controllers (Baseline + 6 manual-
% bypass surrogates), now affordable because the predict() bypass
% (Section~operational_feasibility) reduced per-step cost from
% 1-2000x higher to within a few ms of Baseline for all architectures.
%
%   results = run_extended_monte_carlo()
%
%   PROTOCOL
%     Wind speeds : V = [12, 14, 16] m/s
%     Seeds       : 5 per wind speed (2025:2029), vs. 3 in the original
%                   single-speed Monte Carlo (Section 6.5 of the paper)
%     Duration    : 60s per run (matches the Section 6.4 protocol)
%     Controllers : Baseline, MLP-residual, GP (N_sub=50), SW-MLP,
%                   PINN-v2, TCN, LSTM -- all via verified manual
%                   forward pass (no predict() calls)
%
%   OUTPUT
%     results  struct array: one entry per (controller, V_mean, seed)
%              combination, with fields: controller, V_mean, seed,
%              rmse_omega_rpm, pitch_activity_deg, mean_cpu_ms,
%              n_overruns
%     Also saved to stage3_extended_monte_carlo.mat, and a summary
%     table (mean +/- std per controller x wind speed) printed and
%     saved to extended_monte_carlo_summary.mat

fprintf('==========================================================\n');
fprintf('  EXTENDED MONTE CARLO: 3 wind speeds x 5 seeds x 7 controllers\n');
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

T_SIM   = 60;
Ts      = cfg.mpc.Ts;
N_steps = round(T_SIM / Ts);
V_means = [12, 14, 16];
seeds   = 2025:2029;   % 5 seeds

% ── Load all models (same as generate_closedloop_detail_figures.m) ─────────
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

mdl_res_manual = extract_residual_weights(mdl_res);
fprintf('\n');

% ── Build controllers (built once, reused across all seeds/speeds) ────────
Np1 = cfg.mpc.Np;  Nc1 = cfg.mpc.Nc;      % V1 settings
Np2 = cfg.mpc2.Np; Nc2 = cfg.mpc2.Nc;      % V2 settings

nlobj_baseline = build_ctrl('sf_baseline', 2, p, cfg, Np1, Nc1, Ts, true);
nlobj_res      = build_ctrl('sf_residual_manual', 4, p, cfg, Np1, Nc1, Ts, false);
nlobj_gp       = build_ctrl('sf_gp_residual_manual', 4, p, cfg, Np1, Nc1, Ts, false);
nlobj_swmlp    = build_ctrl('sf_swmlp_manual', 2, p, cfg, Np2, Nc2, Ts, false);
nlobj_pinn     = build_ctrl('sf_pinn_manual',  2, p, cfg, Np2, Nc2, Ts, false);
nlobj_tcn      = build_ctrl('sf_tcn_manual',   2, p, cfg, Np2, Nc2, Ts, false);
nlobj_lstm     = build_ctrl('sf_lstm_manual',  3, p, cfg, Np1, Nc1, Ts, false);

controllers = struct( ...
    'name',  {'Baseline', 'MLP-residual', 'GP', 'SW-MLP', 'PINN-v2', 'TCN', 'LSTM'}, ...
    'nlobj', {nlobj_baseline, nlobj_res, nlobj_gp, nlobj_swmlp, nlobj_pinn, nlobj_tcn, nlobj_lstm}, ...
    'kind',  {'baseline', 'residual', 'gp', 'swmlp', 'pinn', 'tcn', 'lstm'});

seq_len = mdl_swmlp.seq_len;

% ── Run the full sweep ───────────────────────────────────────────────────────
results = struct('controller', {}, 'V_mean', {}, 'seed', {}, ...
    'rmse_omega_rpm', {}, 'pitch_activity_deg', {}, 'mean_cpu_ms', {}, 'n_overruns', {});

run_count = 0;
total_runs = numel(controllers) * numel(V_means) * numel(seeds);

for c = 1:numel(controllers)
    tc = controllers(c);
    for vi = 1:numel(V_means)
        V_mean = V_means(vi);
        for si = 1:numel(seeds)
            seed = seeds(si);
            run_count = run_count + 1;

            V_wind = kaimal_wind(V_mean, T_SIM, Ts, seed);

            x  = [p.omega_r * 0.97; 3.5];
            mv = x(2);
            omega_hist = zeros(N_steps,1);
            beta_hist  = zeros(N_steps,1);
            cpu_hist   = zeros(N_steps,1);
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
                [mv, options, ~] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
                cpu_hist(k) = toc(t0) * 1000;
                mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));

                if ismember(tc.kind, {'swmlp','tcn'})
                    seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
                end

                x = wt_step(x, mv(1), Vk, p, Ts);
                omega_hist(k) = x(1) * 30/pi;
                beta_hist(k)  = x(2);
            end

            r.controller = tc.name;
            r.V_mean     = V_mean;
            r.seed       = seed;
            r.rmse_omega_rpm     = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
            r.pitch_activity_deg = sum(abs(diff(beta_hist)));
            r.mean_cpu_ms        = mean(cpu_hist);
            r.n_overruns         = sum(cpu_hist > 100);
            results(end+1) = r; %#ok<AGROW>

            fprintf('[%3d/%3d] %-14s V=%2dm/s seed=%d  RMSE=%.4frpm  PA=%.1fdeg  CPU=%.1fms  overruns=%d\n', ...
                run_count, total_runs, tc.name, V_mean, seed, ...
                r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cpu_ms, r.n_overruns);
        end
    end
end

save('stage3_extended_monte_carlo.mat', 'results', 'V_means', 'seeds', 'T_SIM');

% ── Summary table: mean +/- std per controller x wind speed ────────────────
fprintf('\n============================================================\n');
fprintf('  SUMMARY — Extended Monte Carlo (mean +/- std over %d seeds)\n', numel(seeds));
fprintf('============================================================\n');
ctrl_names = {controllers.name};
summary = struct('controller', {}, 'V_mean', {}, 'rmse_mean', {}, 'rmse_std', {}, ...
    'cv_pct', {}, 'mean_cpu_ms', {});

for c = 1:numel(ctrl_names)
    for vi = 1:numel(V_means)
        mask = strcmp({results.controller}, ctrl_names{c}) & [results.V_mean] == V_means(vi);
        rmse_vals = [results(mask).rmse_omega_rpm];
        cpu_vals  = [results(mask).mean_cpu_ms];
        s.controller = ctrl_names{c};
        s.V_mean = V_means(vi);
        s.rmse_mean = mean(rmse_vals);
        s.rmse_std  = std(rmse_vals);
        s.cv_pct    = 100 * s.rmse_std / s.rmse_mean;
        s.mean_cpu_ms = mean(cpu_vals);
        summary(end+1) = s; %#ok<AGROW>
        fprintf('%-14s V=%2dm/s  RMSE=%.4f+/-%.4f rpm (CV=%.1f%%)  CPU=%.1fms\n', ...
            s.controller, s.V_mean, s.rmse_mean, s.rmse_std, s.cv_pct, s.mean_cpu_ms);
    end
end

save('extended_monte_carlo_summary.mat', 'summary');

% ── Comparison line vs. the ORIGINAL Monte Carlo (Baseline+LLNFM, 3 seeds, V=14) ──
fprintf('\n------------------------------------------------------------\n');
fprintf('  Reference: ORIGINAL Monte Carlo (paper Section 6.5, 3 seeds, V=14m/s)\n');
fprintf('    Baseline: 1.127 +/- 0.163 rpm (CV=14.5%%)\n');
fprintf('    LLNFM:    2.465 +/- 0.024 rpm (CV=1.0%%)\n');
mask_base14 = strcmp({summary.controller},'Baseline') & [summary.V_mean]==14;
fprintf('  This extended run (5 seeds, V=14m/s):\n');
fprintf('    Baseline: %.4f +/- %.4f rpm (CV=%.1f%%)\n', ...
    summary(mask_base14).rmse_mean, summary(mask_base14).rmse_std, summary(mask_base14).cv_pct);
fprintf('------------------------------------------------------------\n');

% ── Figures ───────────────────────────────────────────────────────────────
fig_dir = fullfile(pwd, 'figures');
if ~isfolder(fig_dir), mkdir(fig_dir); end
FMT = '-dpng'; RES = '-r150';

colors = [0.30 0.30 0.30; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.00 0.45 0.74; ...
          0.49 0.18 0.56; 0.93 0.69 0.13; 0.64 0.08 0.18];   % per-controller (unused for wind-speed grouping below)

% Fixed, distinct color per wind speed (applied uniformly across ALL
% controller groups, so V=12/14/16 m/s are visually identical colors
% in every bar cluster and in the legend — FIX for the mismatched
% per-controller shading previously used here).
wind_speed_colors = [0.00 0.45 0.74;   % V=12 m/s — blue
                      0.85 0.33 0.10;   % V=14 m/s — orange
                      0.47 0.67 0.19];  % V=16 m/s — green

% ── Fig A: Grouped bar with error bars — RMSE vs wind speed, all controllers ──
fA = figure('Color','w','Position',[40 40 1200 520]);
rmse_mean_mat = zeros(numel(ctrl_names), numel(V_means));
rmse_std_mat  = zeros(numel(ctrl_names), numel(V_means));
for c = 1:numel(ctrl_names)
    for vi = 1:numel(V_means)
        idx = strcmp({summary.controller}, ctrl_names{c}) & [summary.V_mean] == V_means(vi);
        rmse_mean_mat(c,vi) = summary(idx).rmse_mean;
        rmse_std_mat(c,vi)  = summary(idx).rmse_std;
    end
end
b = bar(rmse_mean_mat, 'grouped'); hold on;
for vi = 1:numel(V_means)
    b(vi).FaceColor = 'flat';
    for c = 1:numel(ctrl_names)
        b(vi).CData(c,:) = wind_speed_colors(vi,:);
    end
    xpos = b(vi).XEndPoints;
    errorbar(xpos, rmse_mean_mat(:,vi), rmse_std_mat(:,vi), 'k.', 'LineWidth', 1);
end
set(gca, 'XTickLabel', ctrl_names, 'XTickLabelRotation', 20, 'FontSize', 10);
ylabel('RMSE (rpm), mean \pm std over 5 seeds', 'FontSize', 11);
title('Extended Monte Carlo — Closed-Loop RMSE Across Wind Speeds', ...
      'FontSize', 12, 'FontWeight', 'bold');
legend(arrayfun(@(v) sprintf('V=%dm/s', v), V_means, 'UniformOutput', false), ...
       'Location', 'northoutside', 'Orientation', 'horizontal', 'FontSize', 10);
grid on;
print(fA, fullfile(fig_dir, 'FigA_MonteCarlo_RMSE_by_WindSpeed'), FMT, RES);
fprintf('Saved FigA_MonteCarlo_RMSE_by_WindSpeed.png\n');

% ── Fig B: Coefficient of variation (repeatability) across wind speeds ──────
fB = figure('Color','w','Position',[40 40 1100 480]);
cv_mat = zeros(numel(ctrl_names), numel(V_means));
for c = 1:numel(ctrl_names)
    for vi = 1:numel(V_means)
        idx = strcmp({summary.controller}, ctrl_names{c}) & [summary.V_mean] == V_means(vi);
        cv_mat(c,vi) = summary(idx).cv_pct;
    end
end
b2 = bar(cv_mat, 'grouped');
for vi = 1:numel(V_means)
    b2(vi).FaceColor = 'flat';
    for c = 1:numel(ctrl_names), b2(vi).CData(c,:) = wind_speed_colors(vi,:); end
end
set(gca, 'XTickLabel', ctrl_names, 'XTickLabelRotation', 20, 'FontSize', 10);
ylabel('Coefficient of variation (%)', 'FontSize', 11);
title('Seed-to-Seed Repeatability (lower = more repeatable)', ...
      'FontSize', 12, 'FontWeight', 'bold');
legend(arrayfun(@(v) sprintf('V=%dm/s', v), V_means, 'UniformOutput', false), ...
       'Location', 'northoutside', 'Orientation', 'horizontal', 'FontSize', 10);
grid on;
print(fB, fullfile(fig_dir, 'FigB_MonteCarlo_Repeatability'), FMT, RES);
fprintf('Saved FigB_MonteCarlo_Repeatability.png\n');

% ── Fig C: CPU cost vs wind speed (should be flat -- sanity check) ──────────
fC = figure('Color','w','Position',[40 40 1100 480]);
cpu_mat = zeros(numel(ctrl_names), numel(V_means));
for c = 1:numel(ctrl_names)
    for vi = 1:numel(V_means)
        idx = strcmp({summary.controller}, ctrl_names{c}) & [summary.V_mean] == V_means(vi);
        cpu_mat(c,vi) = summary(idx).mean_cpu_ms;
    end
end
b3 = bar(cpu_mat, 'grouped');
for vi = 1:numel(V_means)
    b3(vi).FaceColor = 'flat';
    for c = 1:numel(ctrl_names), b3(vi).CData(c,:) = wind_speed_colors(vi,:); end
end
set(gca, 'XTickLabel', ctrl_names, 'XTickLabelRotation', 20, 'FontSize', 10, 'YScale','log');
ylabel('Mean CPU/step (ms, log scale)', 'FontSize', 11);
title('Computational Cost Across Wind Speeds (all manual-bypass)', ...
      'FontSize', 12, 'FontWeight', 'bold');
legend(arrayfun(@(v) sprintf('V=%dm/s', v), V_means, 'UniformOutput', false), ...
       'Location', 'northoutside', 'Orientation', 'horizontal', 'FontSize', 10);
yline(100, 'r:', 'T_s budget', 'FontSize', 9);
grid on;
print(fC, fullfile(fig_dir, 'FigC_MonteCarlo_CPU_by_WindSpeed'), FMT, RES);
fprintf('Saved FigC_MonteCarlo_CPU_by_WindSpeed.png\n');

% ── Fig D: Old vs New Monte Carlo comparison (Baseline & a reference surrogate) ──
fD = figure('Color','w','Position',[40 40 800 480]);
old_means = [1.127, 2.465];   % Baseline, LLNFM (paper Section 6.5, 3 seeds, V=14)
old_stds  = [0.163, 0.024];
idx_base14 = strcmp({summary.controller},'Baseline') & [summary.V_mean]==14;
% Compare against MLP-residual as the closest available analogue to the
% original LLNFM (both are small, single-pass surrogates); NOT the same
% architecture, so labelled distinctly rather than implying equivalence.
idx_res14  = strcmp({summary.controller},'MLP-residual') & [summary.V_mean]==14;
new_means = [summary(idx_base14).rmse_mean, summary(idx_res14).rmse_mean];
new_stds  = [summary(idx_base14).rmse_std,  summary(idx_res14).rmse_std];

x = [1 2]; wgap = 0.18;
hold on;
errorbar(x-wgap, old_means, old_stds, 'o', 'Color',[0.5 0.5 0.5], ...
    'MarkerFaceColor',[0.5 0.5 0.5], 'LineWidth',1.5, 'CapSize',8, 'DisplayName','Original MC (3 seeds)');
errorbar(x+wgap, new_means, new_stds, 's', 'Color',[0.85 0.33 0.10], ...
    'MarkerFaceColor',[0.85 0.33 0.10], 'LineWidth',1.5, 'CapSize',8, 'DisplayName','Extended MC (5 seeds)');
xlim([0.5 2.5]); set(gca,'XTick',[1 2],'XTickLabel',{'Baseline','MLP-residual (cf. LLNFM)'}, 'FontSize',10);
ylabel('RMSE (rpm), mean \pm std', 'FontSize', 11);
title('Original vs. Extended Monte Carlo (V=14 m/s)', 'FontSize', 12, 'FontWeight','bold');
legend('Location','best', 'FontSize', 10); grid on;
print(fD, fullfile(fig_dir, 'FigD_MonteCarlo_OldVsNew'), FMT, RES);
fprintf('Saved FigD_MonteCarlo_OldVsNew.png\n');

fprintf('\nAll figures saved to %s\n', fig_dir);

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
