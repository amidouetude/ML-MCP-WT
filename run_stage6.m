function run_stage6()
% RUN_STAGE6  Generate the predict()-bypass summary figures
% (Fig1-3_PredictBypass_*), write stage6_results.txt with the
% consolidated speedup table.
%
%   run_stage6()
%
%   NOTE: as documented in generate_predict_bypass_summary_figures.m,
%   its data table is a hand-maintained transcription of Stage 3's
%   confirmed console output, not automatically re-derived. If Stage 3
%   was rerun with different settings, verify that script's data table
%   is up to date before trusting this stage's figures/output.

fprintf('==========================================================\n');
fprintf('  STAGE 6: Summary figures\n');
fprintf('==========================================================\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'stage6_results.txt');

if isfile(txt_path)
    fprintf('  results/stage6_results.txt already exists — skipping.\n');
    fprintf('  Delete this file to force rerun.\n\n');
    return;
end

generate_predict_bypass_summary_figures();

if isfile('stage3_predict_bypass_summary.mat')
    S = load('stage3_predict_bypass_summary.mat');
    fid = fopen(txt_path, 'w');
    fprintf(fid, 'STAGE 6 RESULTS — Summary Figures / Consolidated Speedup Table\n');
    fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
    fprintf(fid, '================================================\n\n');
    for i = 1:numel(S.names)
        fprintf(fid, '[%s]\n', S.names{i});
        fprintf(fid, '  predict_ms = %.1f\n', S.mean_predict(i));
        fprintf(fid, '  manual_ms  = %.1f\n', S.mean_manual(i));
        fprintf(fid, '  speedup    = %.1fx\n', S.mean_predict(i)/S.mean_manual(i));
        fprintf(fid, '  overruns_manual = %d/%d\n', S.overruns_manual(i), S.n_steps_manual(i));
        fprintf(fid, '\n');
    end
    fclose(fid);
    fprintf('  Wrote %s\n\n', txt_path);
else
    fprintf('  WARNING: stage3_predict_bypass_summary.mat not found -- ');
    fprintf('generate_predict_bypass_summary_figures.m may need its hand-\n');
    fprintf('  maintained data table updated first. No .txt written.\n\n');
end

end
