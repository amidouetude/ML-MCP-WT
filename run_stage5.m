function run_stage5()
% RUN_STAGE5  Extended Monte Carlo evaluation (3 wind speeds x 5 seeds
% x 7 controllers), write stage5_results.txt. Also generates the
% corresponding figures (FigA-D).
%
%   run_stage5()
%
%   WARNING: this is the longest stage (~105 sixty-second closed-loop
%   runs, ~20-35 minutes on the reference machine).

fprintf('==========================================================\n');
fprintf('  STAGE 5: Extended Monte Carlo (longest stage, ~20-35 min)\n');
fprintf('==========================================================\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'stage5_results.txt');

if isfile(txt_path)
    fprintf('  results/stage5_results.txt already exists — skipping.\n');
    fprintf('  Delete this file to force rerun.\n\n');
    return;
end

run_extended_monte_carlo();   % saves extended_monte_carlo_summary.mat + figures

S = load('extended_monte_carlo_summary.mat');
summary = S.summary;

fid = fopen(txt_path, 'w');
fprintf(fid, 'STAGE 5 RESULTS — Extended Monte Carlo\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(3 wind speeds x 5 seeds x 7 controllers, T=60s each)\n');
fprintf(fid, '================================================\n\n');

for i = 1:numel(summary)
    s = summary(i);
    fprintf(fid, '[%s, V=%dm/s]\n', s.controller, s.V_mean);
    fprintf(fid, '  rmse_mean_rpm = %.4f\n', s.rmse_mean);
    fprintf(fid, '  rmse_std_rpm  = %.4f\n', s.rmse_std);
    fprintf(fid, '  cv_pct        = %.1f\n', s.cv_pct);
    fprintf(fid, '  mean_cpu_ms   = %.1f\n', s.mean_cpu_ms);
    fprintf(fid, '\n');
end

fprintf(fid, '[Reference — original Monte Carlo, paper Section 6.5 pre-extension]\n');
fprintf(fid, '  Baseline: 1.127 +/- 0.163 rpm (CV=14.5%%), 3 seeds, V=14m/s\n');
fprintf(fid, '  LLNFM:    2.465 +/- 0.024 rpm (CV=1.0%%), 3 seeds, V=14m/s\n');
fprintf(fid, '  (different protocol: 120s window, uncorrected initial condition\n');
fprintf(fid, '   -- see Section 6.5 text for the three compounding differences)\n');

fclose(fid);
fprintf('  Wrote %s\n\n', txt_path);

end
