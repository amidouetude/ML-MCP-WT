function run_stage2()
% RUN_STAGE2  Train the residual-correction MLP and GP-residual model
% (N_sub=50), write stage2_results.txt.
%
%   run_stage2()

fprintf('==========================================================\n');
fprintf('  STAGE 2: Residual model training (MLP + GP)\n');
fprintf('==========================================================\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'stage2_results.txt');

if isfile(txt_path)
    fprintf('  results/stage2_results.txt already exists — skipping.\n');
    fprintf('  Delete this file (or the two stage2_*.mat files) to force rerun.\n\n');
    return;
end

if isfile('stage2_residual_model.mat')
    S = load('stage2_residual_model.mat'); mdl_res = S.mdl;
else
    mdl_res = stage2_train_residual();
end

if isfile('stage2_gp_residual_model.mat')
    S = load('stage2_gp_residual_model.mat'); mdl_gp = S.mdl;
else
    mdl_gp = stage2_train_gp_residual();
end

% ── Write results/stage2_results.txt ────────────────────────────────────────
fid = fopen(txt_path, 'w');
fprintf(fid, 'STAGE 2 RESULTS — Residual Model Training\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '================================================\n\n');

fprintf(fid, '[MLP-residual]\n');
fprintf(fid, 'n_params = %d\n', mdl_res.n_params);
fprintf(fid, 'train_time_s = %.2f\n', mdl_res.train_time);
if isfield(mdl_res, 'rng_seed')
    fprintf(fid, 'rng_seed = %d\n', mdl_res.rng_seed);
else
    fprintf(fid, 'rng_seed = NOT_RECORDED (pre-reproducibility-fix run)\n');
end
fprintf(fid, 'rmse_test_d_omega_radps = %.6e\n', mdl_res.rmse_te(1));
fprintf(fid, 'rmse_test_d_beta_deg    = %.6e\n', mdl_res.rmse_te(2));
fprintf(fid, 'rmse_zero_correction_d_omega = %.6e\n', mdl_res.rmse_zero_correction(1));
fprintf(fid, 'improvement_pct_omega = %.1f\n', ...
    100*(1 - mdl_res.rmse_te(1)/mdl_res.rmse_zero_correction(1)));
fprintf(fid, '\n');

fprintf(fid, '[GP-residual, N_sub=50]\n');
fprintf(fid, 'train_time_s = %.2f\n', mdl_gp.train_time);
fprintf(fid, 'rmse_test_d_omega_radps = %.6e\n', mdl_gp.rmse_te(1));
fprintf(fid, 'rmse_test_d_beta_deg    = %.6e\n', mdl_gp.rmse_te(2));
fclose(fid);

fprintf('  Wrote %s\n\n', txt_path);

end
