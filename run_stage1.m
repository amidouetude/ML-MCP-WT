function run_stage1()
% RUN_STAGE1  Generate the Track B residual-learning dataset and write
% stage1_results.txt summarizing the outcome.
%
%   run_stage1()
%
%   Wraps stage1_generate_residual_data.m. If results/stage1_results.txt
%   already exists, this stage is skipped (delete the file, or the
%   underlying .mat, to force regeneration).

fprintf('==========================================================\n');
fprintf('  STAGE 1: Residual dataset generation\n');
fprintf('==========================================================\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'stage1_results.txt');

if isfile(txt_path)
    fprintf('  results/stage1_results.txt already exists — skipping.\n');
    fprintf('  Delete this file (or stage1_residual_data.mat) to force rerun.\n\n');
    return;
end

if isfile('stage1_residual_data.mat')
    fprintf('  stage1_residual_data.mat exists but stage1_results.txt does not\n');
    fprintf('  -- loading existing data to write the results file.\n');
    data = load('stage1_residual_data.mat');
else
    data = stage1_generate_residual_data();
end

% ── Write results/stage1_results.txt ────────────────────────────────────────
fid = fopen(txt_path, 'w');
fprintf(fid, 'STAGE 1 RESULTS — Residual Dataset Generation\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '================================================\n\n');

fprintf(fid, '[Dataset size]\n');
fprintf(fid, 'total_samples = %d\n', data.info.N_total);
fprintf(fid, 'n_trajectories = %d\n', data.info.N_traj);
fprintf(fid, 'train_samples = %d\n', numel(data.idx_train));
fprintf(fid, 'val_samples   = %d\n', numel(data.idx_val));
fprintf(fid, 'test_samples  = %d\n', numel(data.idx_test));
fprintf(fid, '\n');

fprintf(fid, '[Residual magnitude (train set) — confirms genuine model mismatch]\n');
res_tr = data.Y_residual(data.idx_train,:);
fprintf(fid, 'mean_abs_d_omega_radps = %.6e\n', mean(abs(res_tr(:,1))));
fprintf(fid, 'mean_abs_d_beta_deg    = %.6e\n', mean(abs(res_tr(:,2))));
fprintf(fid, 'std_d_omega_radps      = %.6e\n', std(res_tr(:,1)));
fprintf(fid, 'std_d_beta_deg         = %.6e\n', std(res_tr(:,2)));
fprintf(fid, '\n');

fprintf(fid, '[Interpretation note]\n');
fprintf(fid, ['If mean_abs_d_omega is ~1e-6 or smaller, the unmodeled term in\n' ...
              'wt_step_true.m is too small to be a genuine learning target --\n' ...
              'see docs/experiment_log.md 2026-07-28 entry for the calibration\n' ...
              'history of this check.\n']);
fclose(fid);

fprintf('  Wrote %s\n\n', txt_path);

end
