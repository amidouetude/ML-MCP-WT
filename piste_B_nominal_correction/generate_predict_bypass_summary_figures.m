function generate_predict_bypass_summary_figures()
% GENERATE_PREDICT_BYPASS_SUMMARY_FIGURES  Produce summary figures for
% the full predict()-bypass diagnostic series (MLP-residual, GP, SW-MLP,
% PINN-v2, TCN, LSTM), analogous in style to the original project's
% Fig1_S3_SpeedTracking.png / Fig5_S3_MetricsSummary.png convention.
%
%   generate_predict_bypass_summary_figures()
%
%   DATA SOURCE
%     The summary numbers below are transcribed directly from the
%     confirmed MATLAB console output of each test script
%     (test_residual_manual_closed_loop.m, test_gp_residual_manual_
%     closed_loop.m [N_sub=50 run], test_swmlp_pinn_manual_closed_
%     loop.m, test_tcn_manual_closed_loop.m [vectorized run],
%     test_lstm_manual_closed_loop.m), NOT re-derived or estimated.
%     If any test is re-run with different settings, update the
%     corresponding row below before regenerating these figures.
%
%   OUTPUT
%     Fig1_PredictBypass_CPUComparison.png   grouped bar, log scale,
%       mean CPU/step, predict() vs manual, all 6 rows + Baseline ref
%     Fig2_PredictBypass_Speedup.png         speedup factor bar chart
%       (log scale), one bar per architecture
%     Fig3_PredictBypass_Overruns.png        overruns/600 (or /5 for
%       LSTM predict) before vs after, grouped bar
%     stage3_predict_bypass_summary.mat      the data table itself,
%       for reuse/reproducibility

fprintf('==========================================================\n');
fprintf('  Generating predict()-bypass summary figures\n');
fprintf('==========================================================\n\n');

% ── Data table (transcribed from confirmed console outputs, POST initial-
%    condition bug fix -- see docs/experiment_log.md, 2026-07-30 entry) ────
names       = {'MLP-residual', 'GP (N_{sub}=50)', 'SW-MLP', 'PINN-v2', 'TCN', 'LSTM'};
mean_predict = [ 919.59,  59.70, 2420.35, 3743.20, 2020.23,  30665.75];
mean_manual  = [   8.71,   9.94,   51.56,   33.77,   30.54,     53.46];
overruns_predict = [600, 18, 600, 600, 600,   5];
overruns_manual  = [  0,   0,   47,   1,   4,     1];
n_steps_predict  = [600, 600, 600, 600, 600,   5];   % LSTM predict tested on only 5 steps
n_steps_manual   = [600, 600, 600, 600, 600, 600];
baseline_ms = 9;   % representative Baseline/Nominal-only mean CPU (~8-21ms across corrected tests)

speedup = mean_predict ./ mean_manual;

fprintf('%-16s %14s %14s %10s\n', 'Architecture', 'predict (ms)', 'manual (ms)', 'Speedup');
for i = 1:numel(names)
    fprintf('%-16s %14.1f %14.1f %9.1fx\n', names{i}, mean_predict(i), mean_manual(i), speedup(i));
end
fprintf('\n');

save('stage3_predict_bypass_summary.mat', 'names', 'mean_predict', 'mean_manual', ...
     'overruns_predict', 'overruns_manual', 'n_steps_predict', 'n_steps_manual', 'baseline_ms');

fig_dir = fullfile(pwd, 'figures');
if ~isfolder(fig_dir)
    mkdir(fig_dir);
end
FMT = '-dpng'; RES = '-r150';

% ── Fig 1: CPU comparison, grouped bar, log scale ───────────────────────────
f1 = figure('Color','w','Position',[40 40 1000 480]);
data_cpu = [mean_predict; mean_manual]';
b = bar(data_cpu, 'grouped');
b(1).FaceColor = [0.85 0.33 0.10];   % predict() -- orange/red
b(2).FaceColor = [0.13 0.55 0.13];   % manual -- green
set(gca, 'YScale', 'log', 'XTickLabel', names, 'XTickLabelRotation', 20, 'FontSize', 10);
ylabel('Mean CPU per step (ms, log scale)', 'FontSize', 11);
title('predict() vs Manual Forward Pass — Mean CPU Cost per Control Step', ...
      'FontSize', 12, 'FontWeight', 'bold');
legend({'predict()', 'Manual (no predict())'}, 'Location', 'northoutside', ...
       'Orientation', 'horizontal', 'FontSize', 10);
yline(baseline_ms, 'k--', 'Baseline (Nominal-only) reference', ...
      'FontSize', 9, 'LabelHorizontalAlignment', 'left');
yline(100, 'r:', 'T_s = 100ms budget', 'FontSize', 9, 'LabelHorizontalAlignment', 'right');
grid on;
print(f1, fullfile(fig_dir, 'Fig1_PredictBypass_CPUComparison'), FMT, RES);
fprintf('Saved %s\n', fullfile('figures', 'Fig1_PredictBypass_CPUComparison.png'));

% ── Fig 2: Speedup factor ────────────────────────────────────────────────────
f2 = figure('Color','w','Position',[40 40 900 440]);
b2 = bar(speedup, 'FaceColor', 'flat');
colors = [0.30 0.45 0.69; 0.30 0.45 0.69; 0.30 0.45 0.69; ...
          0.30 0.45 0.69; 0.30 0.45 0.69; 0.55 0.15 0.60];  % highlight LSTM
for i = 1:numel(names), b2.CData(i,:) = colors(i,:); end
set(gca, 'YScale', 'log', 'XTickLabel', names, 'XTickLabelRotation', 20, 'FontSize', 10);
ylabel('Speedup factor (predict() / manual, log scale)', 'FontSize', 11);
title('Speedup from Bypassing predict()', 'FontSize', 12, 'FontWeight', 'bold');
grid on;
for i = 1:numel(names)
    text(i, speedup(i)*1.3, sprintf('%.0fx', speedup(i)), ...
         'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
end
print(f2, fullfile(fig_dir, 'Fig2_PredictBypass_Speedup'), FMT, RES);
fprintf('Saved %s\n', fullfile('figures', 'Fig2_PredictBypass_Speedup.png'));

% ── Fig 3: Overrun rate before/after (normalized to %) ──────────────────────
f3 = figure('Color','w','Position',[40 40 1000 460]);
pct_predict = 100 * overruns_predict ./ n_steps_predict;
pct_manual  = 100 * overruns_manual  ./ n_steps_manual;
data_overrun = [pct_predict; pct_manual]';
b3 = bar(data_overrun, 'grouped');
b3(1).FaceColor = [0.85 0.33 0.10];
b3(2).FaceColor = [0.13 0.55 0.13];
set(gca, 'XTickLabel', names, 'XTickLabelRotation', 20, 'FontSize', 10);
ylabel('Steps exceeding T_s = 100ms budget (%)', 'FontSize', 11);
title('Real-Time Budget Overruns — predict() vs Manual', ...
      'FontSize', 12, 'FontWeight', 'bold');
legend({'predict()', 'Manual (no predict())'}, 'Location', 'northoutside', ...
       'Orientation', 'horizontal', 'FontSize', 10);
ylim([0 105]);
grid on;
for i = 1:numel(names)
    if n_steps_predict(i) < 600
        text(i-0.15, pct_predict(i)+3, sprintf('(n=%d)', n_steps_predict(i)), ...
             'FontSize', 7, 'HorizontalAlignment', 'center');
    end
end
print(f3, fullfile(fig_dir, 'Fig3_PredictBypass_Overruns'), FMT, RES);
fprintf('Saved %s\n', fullfile('figures', 'Fig3_PredictBypass_Overruns.png'));

fprintf('\nAll figures saved to %s\n', fig_dir);
fprintf(['NOTE: LSTM (predict) values are based on only 5 steps (prohibitively\n' ...
         'slow at ~%.0fs/step). After fixing the initial-condition bug (see\n' ...
         'docs/experiment_log.md, 2026-07-30 entry), LSTM (manual) now shows\n' ...
         'only 1/600 overruns -- close to the other architectures'' near-zero\n' ...
         'rate, not the persistent 600/600 seen before the fix. The residual\n' ...
         'sequential-recurrence cost (LSTM manual ~52ms/step vs ~10-30ms/step\n' ...
         'for the single-pass architectures) remains real, but no longer\n' ...
         'manifests as systematic real-time-budget violation at this Ts.\n'], ...
         mean_predict(end)/1000);

end
