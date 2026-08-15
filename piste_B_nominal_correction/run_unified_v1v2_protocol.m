function [results_v1, results_v2] = run_unified_v1v2_protocol()
% RUN_UNIFIED_V1V2_PROTOCOL  Reproduce the original V1/V2 closed-loop
% comparison tables (paper Tables tab:v1_results, tab:v2_results) under
% the unified protocol window (item 2.5): T=60s (was 120s), Nc=4 for
% both V1 and V2 (V2's Nc=1 was changed to 4 at the source, in
% stage0_config.m -- see docs/experiment_log.md).
%
%   [results_v1, results_v2] = run_unified_v1v2_protocol()
%
%   WHY THIS SCRIPT EXISTS
%     No reusable script previously generated tab:v1_results/
%     tab:v2_results -- that data appears to have been produced via
%     ad-hoc console commands at an earlier point in this project's
%     history, never captured in a file. This script closes that
%     reproducibility gap going forward, in addition to applying the
%     T=60s/Nc=4 unification.
%
%   PREREQUISITES
%     stage2_models.mat, stage2_models_v2.mat in common/ or on path.
%
%   OUTPUT
%     results/unified_v1v2_protocol_results.txt
%     results/unified_v1v2_protocol.mat

fprintf('==========================================================\n');
fprintf('  UNIFIED V1/V2 PROTOCOL (item 2.5): T=60s, Nc=4 both snapshots\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'unified_v1v2_protocol_results.txt');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;
Ts   = cfg.mpc.Ts;

T_SIM = 60;                 % unified window (was 120s)
V_MEAN = 14;
WIND_SEED = 2025;
N_steps = round(T_SIM / Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);
omega_ref_radps = p.omega_r;
kappa_default   = cfg.mpc.kappa;

fid = fopen(txt_path, 'w');
fprintf(fid, 'UNIFIED V1/V2 PROTOCOL RESULTS (item 2.5)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, 'T=%ds (unified, was 120s for this protocol), V=%d m/s, seed=%d\n', ...
    T_SIM, V_MEAN, WIND_SEED);
fprintf(fid, 'Nc=%d (unified, V2 was 1) -- see stage0_config.m\n', cfg.mpc.Nc);
fprintf(fid, 'NOTE: LSTM excluded from this run -- predict()-based cost\n');
fprintf(fid, 'already quantified precisely in Table tab:predict_bypass\n');
fprintf(fid, '(Stage 3, ~24.7s/step under R2024a); a 600-step run would\n');
fprintf(fid, 'take ~4+ hours for no new information.\n');
fprintf(fid, '================================================\n\n');

% ── V1 ────────────────────────────────────────────────────────────────────
fprintf('--- Building V1 controllers ---\n');
V1 = load('stage2_models.mat');
models_v1.llnfm = V1.mdl_llnfm; models_v1.lstm = V1.mdl_lstm;
models_v1.gp = V1.mdl_gp; models_v1.pinn = V1.mdl_pinn;
controllers_v1 = stage3_design_controllers(p, models_v1, cfg);

names_v1 = {'Baseline', 'LLNFM', 'GP', 'PINN'};
fields_v1 = {'baseline', 'llnfm', 'gp', 'pinn'};
%% LSTM excluded from this table (item 2.5 unified protocol):
%% predict()-based cost already quantified precisely elsewhere
%% (Table tab:predict_bypass, Stage 3: ~24.7s/step under R2024a),
%% making a 600-step (60s window) run take ~4+ hours for no new
%% information. See docs/experiment_log.md for this decision.
results_v1 = struct('name', {}, 'rmse_omega_rpm', {}, 'pitch_activity_deg', {}, ...
    'mean_cp', {}, 'mean_cpu_ms', {}, 'n_infeasible', {});

fprintf(fid, '=== V1 ===\n\n');
for i = 1:numel(names_v1)
    fprintf('--- V1: %s ---\n', names_v1{i});
    nlobj = controllers_v1.(fields_v1{i});
    r = run_one_v1(names_v1{i}, fields_v1{i}, nlobj, V1, p, cfg, V_wind, ...
        N_steps, Ts, omega_ref_radps, kappa_default);
    results_v1(end+1) = r; %#ok<AGROW>
    fprintf('  RMSE=%.4f rpm  PA=%.2f deg  mean_Cp=%.4f  CPU=%.1fms  infeasible=%d/%d\n\n', ...
        r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cp, r.mean_cpu_ms, r.n_infeasible, N_steps);
    fprintf(fid, '[%s]\n  rmse_omega_rpm = %.4f\n  pitch_activity_deg = %.2f\n', ...
        r.name, r.rmse_omega_rpm, r.pitch_activity_deg);
    fprintf(fid, '  mean_cp = %.4f\n  mean_cpu_ms = %.2f\n  n_infeasible = %d/%d\n\n', ...
        r.mean_cp, r.mean_cpu_ms, r.n_infeasible, N_steps);
end

% ── V2 ────────────────────────────────────────────────────────────────────
fprintf('--- Building V2 controllers ---\n');
V2 = load('stage2_models_v2.mat');
models_v2.llnfm = V2.mdl_llnfm; models_v2.tcn = V2.mdl_tcn;
models_v2.swmlp = V2.mdl_swmlp; models_v2.gp_v2 = V2.mdl_gp_v2;
models_v2.pinn_v2 = V2.mdl_pinn_v2;
controllers_v2 = stage3_design_controllers_v2(p, models_v2, cfg);

names_v2 = {'Baseline', 'LLNFM', 'TCN', 'SW-MLP', 'GP-v2', 'PINN-v2'};
fields_v2 = {'baseline', 'llnfm', 'tcn', 'swmlp', 'gp_v2', 'pinn_v2'};
results_v2 = struct('name', {}, 'rmse_omega_rpm', {}, 'pitch_activity_deg', {}, ...
    'mean_cp', {}, 'mean_cpu_ms', {}, 'n_infeasible', {});

fprintf(fid, '=== V2 ===\n\n');
for i = 1:numel(names_v2)
    fprintf('--- V2: %s ---\n', names_v2{i});
    nlobj = controllers_v2.(fields_v2{i});
    r = run_one_v2(names_v2{i}, fields_v2{i}, nlobj, V2, p, cfg, V_wind, ...
        N_steps, Ts, omega_ref_radps, kappa_default);
    results_v2(end+1) = r; %#ok<AGROW>
    fprintf('  RMSE=%.4f rpm  PA=%.2f deg  mean_Cp=%.4f  CPU=%.1fms  infeasible=%d/%d\n\n', ...
        r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cp, r.mean_cpu_ms, r.n_infeasible, N_steps);
    fprintf(fid, '[%s]\n  rmse_omega_rpm = %.4f\n  pitch_activity_deg = %.2f\n', ...
        r.name, r.rmse_omega_rpm, r.pitch_activity_deg);
    fprintf(fid, '  mean_cp = %.4f\n  mean_cpu_ms = %.2f\n  n_infeasible = %d/%d\n\n', ...
        r.mean_cp, r.mean_cpu_ms, r.n_infeasible, N_steps);
end

fclose(fid);
save('results/unified_v1v2_protocol.mat', 'results_v1', 'results_v2');
fprintf('\nWrote %s and results/unified_v1v2_protocol.mat\n', txt_path);

end

% ── Helpers ──────────────────────────────────────────────────────────────────
function r = run_one_v1(name, kind, nlobj, V1, p, cfg, V_wind, N_steps, Ts, omega_ref, kappa)
x = [p.omega_r*0.97; 3.5]; mv = x(2);
omega_hist = zeros(N_steps,1); beta_hist = zeros(N_steps,1);
cpu_hist = zeros(N_steps,1); exitflag_hist = zeros(N_steps,1);
seq_len_lstm = 10;
if isfield(V1.mdl_lstm, 'seq_len'), seq_len_lstm = V1.mdl_lstm.seq_len; end
seq_buf_lstm = repmat([x(1), x(2), V_wind(1), mv], seq_len_lstm, 1);
options = nlmpcmoveopt;
for k = 1:N_steps
    Vk = V_wind(k);
    switch kind
        case 'baseline'
            options.Parameters = {Vk, p};
        case 'llnfm'
            options.Parameters = {Vk, V1.mdl_llnfm};
        case 'lstm'
            options.Parameters = {Vk, V1.mdl_lstm, seq_buf_lstm};
        case 'gp'
            options.Parameters = {Vk, V1.mdl_gp, omega_ref, kappa, cfg.mpc.Q, 0.01, cfg.mpc.R};
        case 'pinn'
            options.Parameters = {Vk, V1.mdl_pinn};
    end
    t0 = tic;
    [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
    cpu_hist(k) = toc(t0)*1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    exitflag_hist(k) = info.ExitFlag;
    seq_buf_lstm = [seq_buf_lstm(2:end,:); x(1), x(2), Vk, mv(1)];
    x = wt_step(x, mv(1), Vk, p, Ts);
    omega_hist(k) = x(1)*30/pi; beta_hist(k) = x(2);
end
r.name = name;
r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
r.pitch_activity_deg = sum(abs(diff(beta_hist)));
lambda = p.R * (omega_hist*pi/30) ./ V_wind(1:N_steps);
cp_vals = arrayfun(@(l,b) cp_lambda_beta(l,b), lambda, beta_hist);
r.mean_cp = mean(cp_vals);
r.mean_cpu_ms = mean(cpu_hist);
r.n_infeasible = sum(exitflag_hist < 0);
end

function r = run_one_v2(name, kind, nlobj, V2, p, cfg, V_wind, N_steps, Ts, omega_ref, kappa)
x = [p.omega_r*0.97; 3.5]; mv = x(2);
omega_hist = zeros(N_steps,1); beta_hist = zeros(N_steps,1);
cpu_hist = zeros(N_steps,1); exitflag_hist = zeros(N_steps,1);
seq_len_tcn = V2.mdl_tcn.seq_len;
seq_buf = repmat([x(1), x(2), V_wind(1), mv], seq_len_tcn, 1);
options = nlmpcmoveopt;
for k = 1:N_steps
    Vk = V_wind(k);
    switch kind
        case 'baseline'
            options.Parameters = {Vk, p};
        case 'llnfm'
            options.Parameters = {Vk, V2.mdl_llnfm};
        case 'tcn'
            V2.mdl_tcn.seq_buf = seq_buf;
            options.Parameters = {Vk, V2.mdl_tcn};
        case 'swmlp'
            V2.mdl_swmlp.seq_buf = seq_buf;
            options.Parameters = {Vk, V2.mdl_swmlp};
        case 'gp_v2'
            options.Parameters = {Vk, V2.mdl_gp_v2, omega_ref, kappa, cfg.mpc.Q, 0.01, cfg.mpc.R};
        case 'pinn_v2'
            options.Parameters = {Vk, V2.mdl_pinn_v2};
    end
    t0 = tic;
    [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
    cpu_hist(k) = toc(t0)*1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    exitflag_hist(k) = info.ExitFlag;
    if strcmp(kind, 'tcn')
        seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
    end
    x = wt_step(x, mv(1), Vk, p, Ts);
    omega_hist(k) = x(1)*30/pi; beta_hist(k) = x(2);
end
r.name = name;
r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
r.pitch_activity_deg = sum(abs(diff(beta_hist)));
lambda = p.R * (omega_hist*pi/30) ./ V_wind(1:N_steps);
cp_vals = arrayfun(@(l,b) cp_lambda_beta(l,b), lambda, beta_hist);
r.mean_cp = mean(cp_vals);
r.mean_cpu_ms = mean(cpu_hist);
r.n_infeasible = sum(exitflag_hist < 0);
end
