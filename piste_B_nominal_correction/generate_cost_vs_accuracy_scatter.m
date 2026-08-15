function generate_cost_vs_accuracy_scatter()
names = {'Baseline','MLP-residual','GP','SW-MLP','PINN-v2','TCN','LSTM'};
rmse  = [1.2709, 1.2638, 1.2630, 1.0304, 1.1178, 1.1178, 1.0111];
cpu   = [7.4,    8.2,    9.1,    12.7,   11.0,   20.9,   49.0];
colors = [0.30 0.30 0.30; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.00 0.45 0.74; 0.49 0.18 0.56; 0.93 0.69 0.13; 0.64 0.08 0.18];
f = figure('Color','w','Position',[40 40 800 600]); hold on;
for i = 1:numel(names)
    plot(cpu(i), rmse(i), 'o', 'MarkerSize', 12, 'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'k', 'LineWidth', 1);
    text(cpu(i)+1, rmse(i), names{i}, 'FontSize', 9);
end
xline(100, 'r--', 'T_s = 100ms budget', 'LineWidth', 1.2, 'FontSize', 9);
xlabel('Mean CPU per step (ms)', 'FontSize', 11); ylabel('Closed-loop RMSE (rpm)', 'FontSize', 11);
title('Computational Cost vs. Tracking Accuracy, All Manual-Bypass Controllers', 'FontWeight','bold','FontSize',12);
grid on; xlim([0,60]);
fig_dir = fullfile(pwd,'figures'); if ~isfolder(fig_dir), mkdir(fig_dir); end
print(f, fullfile(fig_dir,'FigG_CostVsAccuracy'), '-dpng','-r150');
fprintf('Saved figures/FigG_CostVsAccuracy.png\n');
end