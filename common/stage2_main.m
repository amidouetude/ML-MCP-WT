%% =========================================================================
%  STAGE 2 — ML Model Training & Validation
%  Research: ML-Enhanced MPC for Wind Turbines (NREL 5-MW)
%  Reference: Klein et al. (2024); Jonkman et al. (2009)
%
%  Trains 6 prediction models from stage1_data.mat:
%    0a. Persistence  — x(k+1) = x(k)
%    0b. Linear ARX   — x(k+1) = A*x(k) + B*u(k)  (least squares)
%    1.  LLNFM        — Local Linear Neuro-Fuzzy (ANFIS, Fuzzy Toolbox)
%    2.  LSTM         — Long Short-Term Memory
%    3.  GP           — Gaussian Process (SE kernel, uncertainty sigma)
%    4.  PINN         — Physics-Informed Neural Network
%
%  All ML models share the same normalisation from Stage 1 (data.norm).
%  Split is by trajectories (data.idx_train/val/test).
%
%  PRODUCES
%    Fig1_S2_TrainingLoss.png       ANFIS + PINN convergence
%    Fig2_S2_PredictionAccuracy.png scatter: predicted vs true (all 6)
%    Fig3_S2_LearningCurves.png     RMSE vs N_train (baselines as reference)
%    Fig4_S2_ModelSummary.png       RMSE bars + relative gain vs Linear ARX
%    stage2_models.mat              all trained models + metrics
%
%  HOW TO RUN
%    1. Ensure stage1_data.mat is in the working directory
%    2. Run: stage2_main
% =========================================================================
clear; clc; close all;

fprintf('==========================================\n');
fprintf('  STAGE 2: ML Model Training\n');
fprintf('  NREL 5-MW | R2024a\n');
fprintf('==========================================\n\n');

%% ── Load Stage 1 data ────────────────────────────────────────────────────────
if ~exist('stage1_data.mat','file')
    error('stage1_data.mat not found. Run stage1_generate_data first.');
end
data = load('stage1_data.mat');
cfg  = data.cfg;

fprintf('Loaded: %d samples  |  train=%d  val=%d  test=%d\n\n', ...
        data.info.N_total, numel(data.idx_train), ...
        numel(data.idx_val), numel(data.idx_test));

%% ── STEP 0: Naive baselines ──────────────────────────────────────────────────
fprintf('--- Naive baselines ---\n');
[mdl_persist, mdl_linear] = stage2_train_baselines(data);

%% ── STEP 1: Train ML models ──────────────────────────────────────────────────
fprintf('\n--- ML model training ---\n\n');

fprintf('[1/4] LLNFM (ANFIS)\n');
mdl_llnfm = stage2_train_llnfm(data, cfg);

fprintf('\n[2/4] LSTM\n');
mdl_lstm  = stage2_train_lstm(data, cfg);

fprintf('\n[3/4] Gaussian Process\n');
mdl_gp    = stage2_train_gp(data, cfg);

fprintf('\n[4/4] PINN\n');
mdl_pinn  = stage2_train_pinn(data, cfg);

%% ── STEP 2: Collect all models ───────────────────────────────────────────────
all_mdls  = {mdl_persist, mdl_linear, mdl_llnfm, mdl_lstm, mdl_gp, mdl_pinn};
all_names = {'Persistence','Linear','LLNFM','LSTM','GP','PINN'};
C_all = {[0.7 0.7 0.7],[0.4 0.4 0.4],...
         [0.5 0.5 0.5],[0.22 0.55 0.95],[0.53 0.29 0.72],[0.96 0.38 0.18]};

rmse_o_all = cellfun(@(m) double(m.rmse_te(1))*30/pi, all_mdls);   % [rpm]
rmse_b_all = cellfun(@(m) double(m.rmse_te(2)),        all_mdls);   % [deg]
t_tr_all   = cellfun(@(m) double(m.train_time),        all_mdls);   % [s]

% Relative improvement over Linear ARX
rmse_linear = rmse_o_all(2);
gain_pct    = (rmse_linear - rmse_o_all) / rmse_linear * 100;

%% ── FIG 1: Training convergence ──────────────────────────────────────────────
fprintf('\nGenerating figures...\n');

f1 = figure('Color','w','Position',[40 40 1100 460]);

subplot(1,3,1)
semilogy(mdl_llnfm.err_omega, '-',  'Color',[0.5 0.5 0.5], 'LineWidth',1.8, ...
         'DisplayName','ANFIS \omega');
hold on
semilogy(mdl_llnfm.err_beta,  '--', 'Color',[0.5 0.5 0.5], 'LineWidth',1.8, ...
         'DisplayName','ANFIS \beta');
xlabel('Epoch','FontSize',11); ylabel('RMSE (normalised)','FontSize',11);
title('LLNFM Convergence','FontSize',11,'FontWeight','bold');
legend('FontSize',9); grid on; set(gca,'FontSize',10);

subplot(1,3,2)
semilogy(mdl_pinn.loss_history,    '-',  'Color',[0.96 0.38 0.18],'LineWidth',1.8,...
         'DisplayName','Total');
hold on
semilogy(mdl_pinn.loss_data_hist,  '--', 'Color',[0.22 0.55 0.95],'LineWidth',1.2,...
         'DisplayName','Data');
semilogy(mdl_pinn.loss_phy_hist,   ':',  'Color',[0.17 0.76 0.43],'LineWidth',1.2,...
         'DisplayName','Physics');
xlabel('Iteration','FontSize',11); ylabel('Loss','FontSize',11);
title(sprintf('PINN Loss  (\\lambda_{phy}=%.2f)', mdl_pinn.lambda_phy), ...
      'FontSize',11,'FontWeight','bold');
legend('FontSize',9); grid on; set(gca,'FontSize',10);

subplot(1,3,3)
bar_data = [mdl_persist.rmse_te(1), mdl_linear.rmse_te(1), ...
            mdl_llnfm.rmse_te(1),   mdl_lstm.rmse_te(1), ...
            mdl_gp.rmse_te(1),      mdl_pinn.rmse_te(1)] * 30/pi;
b = bar(bar_data, 'FaceColor','flat');
for ci = 1:6, b.CData(ci,:) = C_all{ci}; end
set(gca,'XTickLabel',all_names,'XTickLabelRotation',30,'FontSize',9);
ylabel('RMSE \omega [rpm]','FontSize',11);
title('Test RMSE Overview','FontSize',11,'FontWeight','bold');
grid on;

sgtitle('Stage 2 — Model Training Summary','FontSize',13,'FontWeight','bold');
print(f1,'Fig1_S2_TrainingLoss',cfg.export.fmt,cfg.export.res);

%% ── FIG 2: Prediction accuracy scatter ───────────────────────────────────────
% Build predictions for test set
X_te   = data.X_in(data.idx_test,:);
Y_te   = data.X_out(data.idx_test,:);

% Persistence
Yhat_persist = X_te(:,1:2);

% Linear ARX
Phi_te       = [X_te, ones(size(X_te,1),1)];
Yhat_linear  = Phi_te * mdl_linear.theta;

% LLNFM
Xn_te        = (X_te - data.norm.xmu) ./ data.norm.xsig;
Xn_te_o      = clamp_to_fis_local(mdl_llnfm.fis_omega, Xn_te);
Xn_te_b      = clamp_to_fis_local(mdl_llnfm.fis_beta,  Xn_te);
Yhat_llnfm   = [evalfis(mdl_llnfm.fis_omega, Xn_te_o) .* data.norm.ysig(1) + data.norm.ymu(1), ...
                evalfis(mdl_llnfm.fis_beta,  Xn_te_b) .* data.norm.ysig(2) + data.norm.ymu(2)];

% GP
[po_te, ~]   = predict(mdl_gp.gp_o, Xn_te);
[pb_te, ~]   = predict(mdl_gp.gp_b, Xn_te);
Yhat_gp      = [po_te, pb_te];

% PINN
Yhat_pinn_n  = extractdata(predict(mdl_pinn.net, dlarray(Xn_te','CB')))';
Yhat_pinn    = Yhat_pinn_n .* data.norm.ysig + data.norm.ymu;

% LSTM — use test sequences
[XSeq_te, Ymat_te] = build_lstm_test_seq(data, mdl_lstm);
Yhat_lstm_n  = minibatchpredict(mdl_lstm.net, XSeq_te, 'MiniBatchSize',128);
Yhat_lstm    = Yhat_lstm_n .* data.norm.ysig + data.norm.ymu;
Y_te_lstm    = Ymat_te     .* data.norm.ysig + data.norm.ymu;

preds  = {Yhat_persist, Yhat_linear, Yhat_llnfm, Yhat_lstm, Yhat_gp, Yhat_pinn};
trues  = {Y_te, Y_te, Y_te, Y_te_lstm, Y_te, Y_te};

f2 = figure('Color','w','Position',[40 40 1300 480]);
for mi = 1:6
    subplot(1,6,mi)
    Yh = preds{mi}; Yt = trues{mi};
    Np = min(size(Yh,1), size(Yt,1));
    scatter(Yt(1:Np,1)*30/pi, Yh(1:Np,1)*30/pi, 3, C_all{mi}, ...
            'filled','MarkerFaceAlpha',0.25);
    hold on
    lims = [min([Yt(:,1);Yh(:,1)]), max([Yt(:,1);Yh(:,1)])] * 30/pi;
    plot(lims, lims, 'k--','LineWidth',1.5);
    rmse_v = sqrt(mean((Yh(1:Np,1)-Yt(1:Np,1)).^2))*30/pi;
    title(sprintf('%s\nRMSE=%.3f rpm', all_names{mi}, rmse_v), ...
          'FontSize',10,'FontWeight','bold');
    xlabel('\omega_{true}','FontSize',9); ylabel('\omega_{pred}','FontSize',9);
    grid on; axis equal; set(gca,'FontSize',8);
end
sgtitle('Rotor Speed One-Step Prediction Accuracy — Test Set', ...
        'FontSize',12,'FontWeight','bold');
print(f2,'Fig2_S2_PredictionAccuracy',cfg.export.fmt,cfg.export.res);

%% ── FIG 3: Model summary ──────────────────────────────────────────────────────
f3 = figure('Color','w','Position',[40 40 1200 460]);
subplot(1,3,1)
b1 = bar(rmse_o_all,'FaceColor','flat');
for ci=1:6, b1.CData(ci,:)=C_all{ci}; end
yline(rmse_o_all(1),'k:','Persist','FontSize',8,'LabelHorizontalAlignment','left');
yline(rmse_o_all(2),'k--','Linear','FontSize',8,'LabelHorizontalAlignment','left');
set(gca,'XTickLabel',all_names,'XTickLabelRotation',30,'FontSize',9);
ylabel('RMSE \omega [rpm]','FontSize',11);
title('Speed RMSE — Test Set','FontSize',11,'FontWeight','bold'); grid on;

subplot(1,3,2)
b2 = bar(t_tr_all,'FaceColor','flat');
for ci=1:6, b2.CData(ci,:)=C_all{ci}; end
set(gca,'XTickLabel',all_names,'XTickLabelRotation',30,'FontSize',9);
ylabel('Training time [s]','FontSize',11);
title('Computational Cost','FontSize',11,'FontWeight','bold'); grid on;

subplot(1,3,3)
b3 = bar(gain_pct,'FaceColor','flat');
for ci=1:6, b3.CData(ci,:)=C_all{ci}; end
yline(0,'k-','LineWidth',1.2);
set(gca,'XTickLabel',all_names,'XTickLabelRotation',30,'FontSize',9);
ylabel('Gain vs Linear ARX [%]','FontSize',11);
title('Relative Improvement','FontSize',11,'FontWeight','bold'); grid on;
for i=1:6
    if gain_pct(i) > 0
        text(i, gain_pct(i)+0.5, sprintf('+%.1f%%',gain_pct(i)), ...
             'HorizontalAlignment','center','FontSize',8,'FontWeight','bold');
    end
end

sgtitle('Stage 2 — Full Model Comparison','FontSize',12,'FontWeight','bold');
print(f3,'Fig3_S2_ModelSummary',cfg.export.fmt,cfg.export.res);

%% ── Save ──────────────────────────────────────────────────────────────────────
save('stage2_models.mat', ...
     'mdl_persist','mdl_linear','mdl_llnfm','mdl_lstm','mdl_gp','mdl_pinn', ...
     'all_names','rmse_o_all','rmse_b_all','gain_pct','cfg');
fprintf('\nSaved → stage2_models.mat\n');

%% ── Results table ─────────────────────────────────────────────────────────────
fprintf('\n%s\n', repmat('=',1,72));
fprintf('  STAGE 2 RESULTS\n');
fprintf('%s\n', repmat('=',1,72));
fprintf('%-12s  %10s  %10s  %10s  %12s\n', ...
        'Model','RMSE-w rpm','RMSE-b deg','Train (s)','Gain vs Lin');
fprintf('%s\n', repmat('-',1,72));
for mi = 1:6
    fprintf('%-12s  %10.4f  %10.4f  %10.1f  %+11.1f%%\n', ...
            all_names{mi}, rmse_o_all(mi), rmse_b_all(mi), ...
            t_tr_all(mi), gain_pct(mi));
end
fprintf('%s\n', repmat('=',1,72));
fprintf('  Ready for Stage 3: nlmpc() controller design\n');
fprintf('%s\n', repmat('=',1,72));

%% ── Write results/stage2_main_results.txt [ADDED] ───────────────────────────
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen(fullfile('results','stage2_main_results.txt'), 'w');
fprintf(fid, 'STAGE 2 (V1) MODEL TRAINING RESULTS\n');
fprintf(fid, 'Generated: %s\n', datestr(now));
fprintf(fid, 'MATLAB version: %s\n', version);
fprintf(fid, '================================================\n\n');
for mi = 1:6
    fprintf(fid, '[%s]\n', all_names{mi});
    fprintf(fid, '  rmse_omega_rpm = %.4f\n', rmse_o_all(mi));
    fprintf(fid, '  rmse_beta_deg = %.4f\n', rmse_b_all(mi));
    fprintf(fid, '  train_time_s = %.2f\n', t_tr_all(mi));
    fprintf(fid, '  gain_vs_linear_pct = %.1f\n', gain_pct(mi));
    if isfield(all_mdls{mi}, 'rng_seed')
        fprintf(fid, '  rng_seed = %d\n', all_mdls{mi}.rng_seed);
    else
        fprintf(fid, '  rng_seed = N/A (deterministic or not recorded)\n');
    end
    fprintf(fid, '\n');
end
fclose(fid);
fprintf('Wrote results/stage2_main_results.txt\n');

%% ── Local helpers ─────────────────────────────────────────────────────────────
function Xc = clamp_to_fis_local(fis, X)
    Xc = X;
    for i = 1:numel(fis.Inputs)
        r = fis.Inputs(i).Range;
        Xc(:,i) = max(r(1), min(r(2), X(:,i)));
    end
end

function [XSeq, Ymat] = build_lstm_test_seq(data, mdl)
    Xn = (data.X_in  - data.norm.xmu) ./ data.norm.xsig;
    Yn = (data.X_out - data.norm.ymu) ./ data.norm.ysig;
    L  = mdl.seq_len;
    N_steps = data.info.N_steps;
    traj_te = data.info.traj_te;
    N_seq   = numel(traj_te) * (N_steps - L);
    XSeq    = cell(N_seq, 1);
    Ymat    = zeros(N_seq, 2);
    row     = 1;
    for k = 1:numel(traj_te)
        idx_k = find(data.traj_id == traj_te(k));
        Xk = Xn(idx_k,:);
        Yk = Yn(idx_k,:);
        for t = L : size(Xk,1)-1
            XSeq{row}   = Xk(t-L+1:t, :);
            Ymat(row,:) = Yk(t+1, :);
            row = row + 1;
        end
    end
    XSeq = XSeq(1:row-1);
    Ymat = Ymat(1:row-1,:);
end
