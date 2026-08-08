function generate_models_summary_csv()
% GENERATE_MODELS_SUMMARY_CSV  Central CSV summary of all trained
% surrogate models (reproducibility review, P1.1): name, RNG seed (if
% recorded), key hyperparameters, test RMSE, and training time.
%
%   generate_models_summary_csv()
%
%   DATA SOURCE
%     Loads stage2_models.mat (V1) and stage2_models_v2.mat (V2). No
%     new training is performed -- this only tabulates fields already
%     stored in each model struct after training.
%
%   OUTPUT
%     results/models_summary.csv   one row per surrogate, columns:
%       snapshot, model_name, rng_seed, n_params_or_hparams,
%       rmse_omega, rmse_beta, train_time_s

fprintf('==========================================================\n');
fprintf('  P1.1: Central Models Summary CSV\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
csv_path = fullfile('results', 'models_summary.csv');

rows = {};

% ── V1 models ────────────────────────────────────────────────────────────────
if isfile('stage2_models.mat')
    V1 = load('stage2_models.mat');
    rows = [rows; extract_row('V1', 'Persistence', [], 'n/a', V1, 'mdl_persist')];
    rows = [rows; extract_row('V1', 'Linear ARX',  [], 'n/a', V1, 'mdl_linear')];
    rows = [rows; extract_row('V1', 'LLNFM',       [], 'ANFIS: 2 MF/input, 16 rules', V1, 'mdl_llnfm')];
    rows = [rows; extract_row('V1', 'LSTM',        [], 'hidden=[64,32], seq_len=10', V1, 'mdl_lstm')];
    rows = [rows; extract_row('V1', 'GP',          [], 'SE kernel, N_sub=400', V1, 'mdl_gp')];
    rows = [rows; extract_row('V1', 'PINN',        [], 'MLP 64-64-32, lambda_phy=0.10', V1, 'mdl_pinn')];
else
    fprintf('  WARNING: stage2_models.mat not found -- V1 rows skipped.\n');
end

% ── V2 models ────────────────────────────────────────────────────────────────
if isfile('stage2_models_v2.mat')
    V2 = load('stage2_models_v2.mat');
    rows = [rows; extract_row('V2', 'Persistence', [], 'n/a', V2, 'mdl_persist')];
    rows = [rows; extract_row('V2', 'Linear ARX',  [], 'n/a', V2, 'mdl_linear')];
    rows = [rows; extract_row('V2', 'LLNFM',       [], 'ANFIS (reused from V1)', V2, 'mdl_llnfm')];
    rows = [rows; extract_row('V2', 'TCN',         [], 'kernel=3,dilations=[1,2,4],filt=16', V2, 'mdl_tcn')];
    rows = [rows; extract_row('V2', 'SW-MLP',      [], 'relu MLP, seq flattened', V2, 'mdl_swmlp')];
    rows = [rows; extract_row('V2', 'GP-v2',       [], 'Matern5/2, N_sub=400, Bayes-opt HP', V2, 'mdl_gp_v2')];
    rows = [rows; extract_row('V2', 'PINN-v2',     [], 'MLP 64-64-32, softplus Cp', V2, 'mdl_pinn_v2')];
else
    fprintf('  WARNING: stage2_models_v2.mat not found -- V2 rows skipped.\n');
end

% ── Track B residual models (if present) ────────────────────────────────────
if isfile('piste_B_nominal_correction/stage2_residual_model.mat')
    R = load('piste_B_nominal_correction/stage2_residual_model.mat');
    rows = [rows; extract_row('TrackB', 'MLP-residual', [], '2x8 tanh, nominal+correction', R, 'mdl')];
end
if isfile('piste_B_nominal_correction/stage2_gp_residual_model.mat')
    G = load('piste_B_nominal_correction/stage2_gp_residual_model.mat');
    rows = [rows; extract_row('TrackB', 'GP-residual', [], 'Matern5/2, N_sub=50', G, 'mdl')];
end

% ── Write CSV ─────────────────────────────────────────────────────────────────
fid = fopen(csv_path, 'w');
fprintf(fid, 'snapshot,model_name,rng_seed,hyperparameters,rmse_omega_rpm,rmse_beta_deg,train_time_s\n');
for i = 1:size(rows, 1)
    r = rows(i, :);
    fprintf(fid, '%s,%s,%s,"%s",%s,%s,%s\n', r{:});
end
fclose(fid);

fprintf('  Wrote %d model rows to %s\n', size(rows,1), csv_path);
fprintf('\n============================================================\n');
type(csv_path);
fprintf('============================================================\n');

end


function row = extract_row(snapshot, name, ~, hparams, S, field)
% Extract one CSV row from a loaded model struct, tolerant of missing
% fields (e.g. Persistence/Linear ARX have no rng_seed or train_time).
if ~isfield(S, field)
    row = {snapshot, name, 'N/A', hparams, 'N/A', 'N/A', 'N/A'};
    return;
end
mdl = S.(field);

if isstruct(mdl) && isfield(mdl, 'rng_seed')
    seed_str = num2str(mdl.rng_seed);
else
    seed_str = 'not recorded';
end

if isstruct(mdl) && isfield(mdl, 'rmse_te')
    rmse_o = sprintf('%.6f', mdl.rmse_te(1));
    rmse_b = sprintf('%.4f', mdl.rmse_te(2));
elseif isstruct(mdl) && isfield(mdl, 'rmse')
    rmse_o = sprintf('%.6f', mdl.rmse(1));
    if numel(mdl.rmse) > 1
        rmse_b = sprintf('%.4f', mdl.rmse(2));
    else
        rmse_b = 'N/A';
    end
else
    rmse_o = 'N/A'; rmse_b = 'N/A';
end

if isstruct(mdl) && isfield(mdl, 'train_time')
    tt = sprintf('%.2f', mdl.train_time);
else
    tt = 'N/A';
end

row = {snapshot, name, seed_str, hparams, rmse_o, rmse_b, tt};
end
