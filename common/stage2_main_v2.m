%% =========================================================================
%  STAGE 2 V2 — ML Model Training (V2 improvements)
%  Research: ML-Enhanced MPC for Wind Turbines (NREL 5-MW)
%
%  V2 MODELS (new or improved vs V1):
%    0a. Persistence    — x(k+1) = x(k)                  [unchanged from V1]
%    0b. Linear ARX     — least squares                   [unchanged from V1]
%    1.  LLNFM          — ANFIS                           [unchanged from V1]
%    2.  TCN            — Temporal Conv Network           [NEW in V2]
%    3.  SW-MLP         — Sliding Window MLP              [NEW in V2]
%    4.  GP-v2          — Matern52 + optimised HP         [IMPROVED in V2]
%    5.  PINN-v2        — softplus differentiable Cp      [IMPROVED in V2]
%
%  DATA
%    Reuses stage1_data.mat from V1 — same dataset, only models change.
%    This allows a clean comparison: V1 vs V2 improvements are attributable
%    solely to model architecture, not to data changes.
%
%  PRODUCES
%    Fig1_V2_TrainingLoss.png      convergence curves
%    Fig2_V2_PredictionAccuracy.png  scatter plots (all 7 models)
%    Fig3_V2_LearningCurves.png    RMSE vs N_train
%    Fig4_V2_ModelSummary.png      bar charts + V1 vs V2 comparison
%    stage2_models_v2.mat          all V2 models + V1 baselines
%
%  HOW TO RUN
%    1. Ensure stage1_data.mat (V1) is in working directory
%    2. Ensure stage2_models.mat (V1) is available for comparison
%    3. Run: stage2_main_v2
% =========================================================================
clear; clc; close all;

fprintf('==========================================\n');
fprintf('  STAGE 2 V2: ML Model Training\n');
fprintf('  NREL 5-MW | R2024a\n');
fprintf('==========================================\n\n');

%% ── Load Stage 1 data (reused from V1) ──────────────────────────────────────
if ~exist('stage1_data.mat','file')
    error('stage1_data.mat not found. Run stage1_generate_data first (V1).');
end
data = load('stage1_data.mat');
cfg  = stage0_config();

fprintf('Loaded stage1_data.mat (V1 dataset — reused for V2)\n');
fprintf('  %d samples | train=%d  val=%d  test=%d\n\n', ...
        data.info.N_total, numel(data.idx_train), ...
        numel(data.idx_val), numel(data.idx_test));

%% ── Load V1 models for comparison ───────────────────────────────────────────
v1_available = exist('stage2_models.mat','file');
if v1_available
    v1 = load('stage2_models.mat', ...
               'mdl_persist','mdl_linear','mdl_llnfm','mdl_gp','mdl_pinn');
    fprintf('Loaded stage2_models.mat (V1 reference)\n\n');
else
    warning('stage2_models.mat not found — V1 comparison will be skipped.');
end

%% ── STEP 0: Baselines (identical to V1 — reference anchor) ─────────────────
fprintf('--- Baselines (V1 reference, unchanged) ---\n');
[mdl_persist, mdl_linear] = stage2_train_baselines(data);

%% ── STEP 1: V1 LLNFM — reuse from V1 if available, else retrain ─────────────
if v1_available
    mdl_llnfm = v1.mdl_llnfm;
    fprintf('\n[LLNFM]  Reused from V1 (unchanged architecture)\n');
    fprintf('  RMSE test: omega=%.5f rad/s (%.4f rpm)  beta=%.4f deg\n', ...
            mdl_llnfm.rmse_te(1), mdl_llnfm.rmse_te(1)*30/pi, mdl_llnfm.rmse_te(2));
else
    fprintf('\n[1/5] LLNFM (retraining — V1 model not found)\n');
    mdl_llnfm = stage2_train_llnfm(data, cfg);
end

%% ── STEP 2: TCN — NEW in V2 ──────────────────────────────────────────────────
fprintf('\n[2/5] TCN (NEW — Temporal Convolutional Network)\n');
mdl_tcn = stage2_train_tcn(data, cfg);

%% ── STEP 3: SW-MLP — NEW in V2 ──────────────────────────────────────────────
fprintf('\n[3/5] SW-MLP (NEW — Sliding Window MLP)\n');
mdl_swmlp = stage2_train_swmlp(data, cfg);

%% ── STEP 4: GP-v2 — IMPROVED in V2 ──────────────────────────────────────────
fprintf('\n[4/5] GP-v2 (IMPROVED — Matern52 + HP optimisation)\n');
mdl_gp_v2 = stage2_train_gp_v2(data, cfg);

%% ── STEP 5: PINN-v2 — IMPROVED in V2 ────────────────────────────────────────
fprintf('\n[5/5] PINN-v2 (IMPROVED — differentiable Cp via softplus)\n');
mdl_pinn_v2 = stage2_train_pinn_v2(data, cfg);

%% ── Collect all V2 models ────────────────────────────────────────────────────
all_mdls  = {mdl_persist, mdl_linear, mdl_llnfm, mdl_tcn, mdl_swmlp, ...
             mdl_gp_v2, mdl_pinn_v2};
all_names = {'Persistence','Linear','LLNFM','TCN','SW-MLP','GP-v2','PINN-v2'};
C_all = {[0.7 0.7 0.7],[0.4 0.4 0.4],[0.5 0.5 0.5], ...
         [0.17 0.76 0.43],[0.12 0.56 0.85], ...
         [0.53 0.29 0.72],[0.96 0.38 0.18]};

rmse_o_v2 = cellfun(@(m) double(m.rmse_te(1))*30/pi, all_mdls);
rmse_b_v2 = cellfun(@(m) double(m.rmse_te(2)),        all_mdls);
t_tr_v2   = cellfun(@(m) double(m.train_time),        all_mdls);

% Relative improvement over Linear ARX
rmse_lin  = rmse_o_v2(2);
gain_v2   = (rmse_lin - rmse_o_v2) / rmse_lin * 100;

%% ── FIG 1: Training convergence ──────────────────────────────────────────────
fprintf('\nGenerating figures...\n');
FMT = cfg.export.fmt; RES = cfg.export.res;

f1 = figure('Color','w','Position',[40 40 1200 440]);

subplot(1,3,1)
if ~isempty(mdl_llnfm.err_omega) && ~all(isnan(mdl_llnfm.err_omega))
    semilogy(mdl_llnfm.err_omega,'-','Color',[0.5 0.5 0.5],'LineWidth',1.8,...
             'DisplayName','ANFIS omega');
    hold on
    semilogy(mdl_llnfm.err_beta,'--','Color',[0.5 0.5 0.5],'LineWidth',1.8,...
             'DisplayName','ANFIS beta');
end
xlabel('Epoch','FontSize',11); ylabel('RMSE (norm.)','FontSize',11);
title('LLNFM Convergence','FontSize',11,'FontWeight','bold');
legend('FontSize',9); grid on; set(gca,'FontSize',10);

subplot(1,3,2)
semilogy(mdl_pinn_v2.loss_history,   '-','Color',[0.96 0.38 0.18],'LineWidth',1.8,...
         'DisplayName','Total');
hold on
semilogy(mdl_pinn_v2.loss_data_hist,'--','Color',[0.22 0.55 0.95],'LineWidth',1.2,...
         'DisplayName','Data');
semilogy(mdl_pinn_v2.loss_phy_hist, ':','Color',[0.17 0.76 0.43],'LineWidth',1.2,...
         'DisplayName','Physics (diff.)');
xlabel('Iteration','FontSize',11); ylabel('Loss','FontSize',11);
title(sprintf('PINN-v2 (softplus beta=%d)', cfg.ml2.pinn.softplus_beta),...
      'FontSize',11,'FontWeight','bold');
legend('FontSize',9); grid on; set(gca,'FontSize',10);

subplot(1,3,3)
b = bar(rmse_o_v2,'FaceColor','flat');
for ci=1:numel(all_names), b.CData(ci,:)=C_all{ci}; end
set(gca,'XTickLabel',all_names,'XTickLabelRotation',35,'FontSize',8);
ylabel('RMSE omega [rpm]','FontSize',11);
title('Test RMSE Overview V2','FontSize',11,'FontWeight','bold');
grid on;
sgtitle('Stage 2 V2 — Training Summary','FontSize',13,'FontWeight','bold');
print(f1,'Fig1_V2_TrainingLoss',FMT,RES);

%% ── FIG 2: V1 vs V2 comparison (GP and PINN) ────────────────────────────────
if v1_available
    f2 = figure('Color','w','Position',[40 40 1000 420]);

    subplot(1,2,1)
    v1_rmse_o = [v1.mdl_gp.rmse_te(1)*30/pi, mdl_gp_v2.rmse_te(1)*30/pi];
    b1 = bar(v1_rmse_o,'FaceColor','flat');
    b1.CData = [[0.53 0.29 0.72]; [0.30 0.15 0.55]];
    set(gca,'XTickLabel',{'GP-v1 (SE)','GP-v2 (Mat52+opt)'},'FontSize',10);
    ylabel('RMSE omega [rpm]','FontSize',11);
    title('GP: V1 vs V2','FontSize',12,'FontWeight','bold'); grid on;
    for i=1:2
        text(i, v1_rmse_o(i)*1.02, sprintf('%.4f',v1_rmse_o(i)), ...
             'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
    end

    subplot(1,2,2)
    v1_rmse_p = [v1.mdl_pinn.rmse_te(1)*30/pi, mdl_pinn_v2.rmse_te(1)*30/pi];
    b2 = bar(v1_rmse_p,'FaceColor','flat');
    b2.CData = [[0.96 0.38 0.18]; [0.70 0.20 0.05]];
    set(gca,'XTickLabel',{'PINN-v1 (max)','PINN-v2 (softplus)'},'FontSize',10);
    ylabel('RMSE omega [rpm]','FontSize',11);
    title('PINN: V1 vs V2','FontSize',12,'FontWeight','bold'); grid on;
    for i=1:2
        text(i, v1_rmse_p(i)*1.02, sprintf('%.4f',v1_rmse_p(i)), ...
             'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');
    end

    sgtitle('V1 vs V2 — Improved Models Comparison','FontSize',13,'FontWeight','bold');
    print(f2,'Fig2_V2_V1vsV2',FMT,RES);
end

%% ── FIG 3: Full model summary bar chart ──────────────────────────────────────
f3 = figure('Color','w','Position',[40 40 1300 460]);

subplot(1,3,1)
b1 = bar(rmse_o_v2,'FaceColor','flat');
for ci=1:numel(all_names), b1.CData(ci,:)=C_all{ci}; end
yline(rmse_o_v2(1),'k:','Persist','FontSize',8,'LabelHorizontalAlignment','left');
yline(rmse_o_v2(2),'k--','Linear','FontSize',8,'LabelHorizontalAlignment','left');
set(gca,'XTickLabel',all_names,'XTickLabelRotation',35,'FontSize',8);
ylabel('RMSE omega [rpm]','FontSize',11);
title('Speed RMSE — Test Set','FontSize',11,'FontWeight','bold'); grid on;

subplot(1,3,2)
b2 = bar(t_tr_v2,'FaceColor','flat');
for ci=1:numel(all_names), b2.CData(ci,:)=C_all{ci}; end
set(gca,'XTickLabel',all_names,'XTickLabelRotation',35,'FontSize',8);
ylabel('Training time [s]','FontSize',11);
title('Computational Cost','FontSize',11,'FontWeight','bold'); grid on;

subplot(1,3,3)
b3 = bar(gain_v2,'FaceColor','flat');
for ci=1:numel(all_names), b3.CData(ci,:)=C_all{ci}; end
yline(0,'k-','LineWidth',1.2);
set(gca,'XTickLabel',all_names,'XTickLabelRotation',35,'FontSize',8);
ylabel('Gain vs Linear ARX [%]','FontSize',11);
title('Relative Improvement','FontSize',11,'FontWeight','bold'); grid on;
for i=1:numel(all_names)
    if gain_v2(i) > 0
        text(i, gain_v2(i)+0.5, sprintf('+%.1f%%',gain_v2(i)), ...
             'HorizontalAlignment','center','FontSize',7,'FontWeight','bold');
    end
end
sgtitle('Stage 2 V2 — Full Model Comparison','FontSize',12,'FontWeight','bold');
print(f3,'Fig3_V2_ModelSummary',FMT,RES);

%% ── Save ─────────────────────────────────────────────────────────────────────
save('stage2_models_v2.mat', ...
     'mdl_persist','mdl_linear','mdl_llnfm', ...
     'mdl_tcn','mdl_swmlp','mdl_gp_v2','mdl_pinn_v2', ...
     'all_names','rmse_o_v2','rmse_b_v2','gain_v2','cfg');
fprintf('\nSaved -> stage2_models_v2.mat\n');

%% ── Results table ─────────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat('=',1,76));
fprintf('  STAGE 2 V2 RESULTS\n');
fprintf('%s\n', repmat('=',1,76));
fprintf('%-12s  %10s  %10s  %10s  %12s\n', ...
        'Model','RMSE-w rpm','RMSE-b deg','Train (s)','Gain vs Lin');
fprintf('%s\n', repmat('-',1,76));
for mi = 1:numel(all_names)
    fprintf('%-12s  %10.4f  %10.4f  %10.1f  %+11.1f%%\n', ...
            all_names{mi}, rmse_o_v2(mi), rmse_b_v2(mi), ...
            t_tr_v2(mi), gain_v2(mi));
end
fprintf('%s\n', repmat('=',1,76));

% V1 vs V2 summary for improved models
if v1_available
    fprintf('\n  V1 vs V2 improvement summary:\n');
    fprintf('  %-10s  V1=%.4f rpm  V2=%.4f rpm  Delta=%+.4f rpm\n', ...
            'GP', v1.mdl_gp.rmse_te(1)*30/pi, mdl_gp_v2.rmse_te(1)*30/pi, ...
            (mdl_gp_v2.rmse_te(1) - v1.mdl_gp.rmse_te(1))*30/pi);
    fprintf('  %-10s  V1=%.4f rpm  V2=%.4f rpm  Delta=%+.4f rpm\n', ...
            'PINN', v1.mdl_pinn.rmse_te(1)*30/pi, mdl_pinn_v2.rmse_te(1)*30/pi, ...
            (mdl_pinn_v2.rmse_te(1) - v1.mdl_pinn.rmse_te(1))*30/pi);
end
fprintf('%s\n', repmat('=',1,76));
fprintf('  Ready for Stage 3 V2: nlmpc() controller design\n');
fprintf('%s\n', repmat('=',1,76));
