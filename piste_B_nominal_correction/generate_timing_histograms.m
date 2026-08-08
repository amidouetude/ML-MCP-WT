function generate_timing_histograms()
% GENERATE_TIMING_HISTOGRAMS  Per-solve CPU timing distribution
% histograms for each controller (reproducibility review, P1.3),
% reusing already-saved per-step CPU arrays -- no new simulation runs
% required.
%
%   generate_timing_histograms()
%
%   DATA SOURCE
%     Loads stage3_v3_trajectories.mat (from
%     generate_closedloop_detail_figures.m, Section 6.4 of the paper),
%     which already stores the full per-step cpu_ms array for each of
%     the seven manual-bypass controllers. No new closed-loop runs are
%     performed here -- this only re-visualizes existing data at a
%     finer grain (full distribution, not just mean/max) than the
%     paper's summary tables.
%
%   OUTPUT
%     figures/FigE_TimingHistograms.png     one subplot per controller
%     results/timing_distribution_results.txt   percentile summary
%       (p50, p95, p99, max) per controller, complementing the mean/max
%       already reported in Table~bypass_closed_loop

fprintf('==========================================================\n');
fprintf('  P1.3: Per-Solve CPU Timing Distributions\n');
fprintf('==========================================================\n\n');

if ~isfile('stage3_v3_trajectories.mat')
    error(['stage3_v3_trajectories.mat not found. Run ' ...
           'generate_closedloop_detail_figures() first (Section 6.4 data).']);
end
S = load('stage3_v3_trajectories.mat');
traj = S.traj;
names = fieldnames(traj);

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'timing_distribution_results.txt');
fid = fopen(txt_path, 'w');
fprintf(fid, 'TIMING DISTRIBUTION SUMMARY (P1.3)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(Source: stage3_v3_trajectories.mat, V=14m/s, T=60s, seed=2025)\n');
fprintf(fid, '================================================\n\n');

colors = struct( ...
    'Baseline',     [0.30 0.30 0.30], ...
    'MLP_residual', [0.85 0.33 0.10], ...
    'GP_residual',  [0.47 0.67 0.19], ...
    'SW_MLP',       [0.00 0.45 0.74], ...
    'PINN_v2',      [0.49 0.18 0.56], ...
    'TCN',          [0.93 0.69 0.13], ...
    'LSTM',         [0.64 0.08 0.18]);

n = numel(names);
nrows = ceil(n/3);
f = figure('Color','w','Position',[40 40 1300 250*nrows]);

fprintf('%-14s %8s %8s %8s %8s\n', 'Controller', 'p50(ms)', 'p95(ms)', 'p99(ms)', 'max(ms)');
for i = 1:n
    key = names{i};
    cpu = traj.(key).cpu;

    p50 = prctile(cpu, 50);
    p95 = prctile(cpu, 95);
    p99 = prctile(cpu, 99);
    mx  = max(cpu);

    fprintf('%-14s %8.1f %8.1f %8.1f %8.1f\n', strrep(key,'_','-'), p50, p95, p99, mx);
    fprintf(fid, '[%s]\n', strrep(key,'_','-'));
    fprintf(fid, '  p50_ms = %.2f\n', p50);
    fprintf(fid, '  p95_ms = %.2f\n', p95);
    fprintf(fid, '  p99_ms = %.2f\n', p99);
    fprintf(fid, '  max_ms = %.2f\n', mx);
    fprintf(fid, '  n_overruns_gt100ms = %d\n\n', sum(cpu > 100));

    subplot(nrows, 3, i);
    c = colors.(key);
    if isfield(colors, key), col = colors.(key); else, col = [0.3 0.3 0.3]; end
    histogram(cpu, 30, 'FaceColor', col, 'EdgeColor', 'none');
    hold on;
    xline(100, 'r:', 'LineWidth', 1.2);
    title(strrep(key,'_','-'), 'FontSize', 10);
    xlabel('CPU/step (ms)', 'FontSize', 8);
    ylabel('Count', 'FontSize', 8);
    grid on;
end
sgtitle('Per-Solve CPU Timing Distributions, All Manual-Bypass Controllers (T_s=100ms budget marked)', ...
    'FontWeight', 'bold', 'FontSize', 12);

fig_dir = fullfile(pwd, 'figures');
if ~isfolder(fig_dir), mkdir(fig_dir); end
print(f, fullfile(fig_dir, 'FigE_TimingHistograms'), '-dpng', '-r150');
fprintf('\nSaved figures/FigE_TimingHistograms.png\n');

fclose(fid);
fprintf('Wrote %s\n', txt_path);

end
