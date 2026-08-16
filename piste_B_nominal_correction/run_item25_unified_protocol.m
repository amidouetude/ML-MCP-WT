function results = run_item25_unified_protocol()
%% RUN_ITEM25_UNIFIED_PROTOCOL  Referee item 2.5: one protocol, all
%% controllers, manual-bypass state functions throughout (never
%% predict(), per the single-precision gradient-corruption finding),
%% GP-v2 uncertainty term as an explicit kappa=0/kappa=0.8 ablation
%% against the same base cost.
%%
%% Protocol: T=60s, Np=15, Nc=4, Ts=0.1, V=14 m/s, seed=2025.
%% Architectures: Baseline, LLNFM, GP-v2(kappa=0), GP-v2(kappa=0.8),
%% PINN-v2, TCN, SW-MLP. LSTM excluded (predict() cost already
%% quantified in tab:predict_bypass; see docs/experiment_log.md).

addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'item25_unified_protocol_results.txt');

cfg = stage0_config();
p = get_wt_params();
Ts = cfg.mpc.Ts;
p.dt = Ts;  %% required by sf_baseline.m
T_SIM = 60;
V_MEAN = 14;
SEED = 2025;
N_steps = round(T_SIM/Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, SEED);
omega_ref = p.omega_r;
Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc;  %% 15, 4 -- confirmed unified

fid = fopen(txt_path, 'w');
fprintf(fid, 'ITEM 2.5 UNIFIED PROTOCOL RESULTS\n');
fprintf(fid, 'Generated: %s\n', datestr(now));
fprintf(fid, 'T=%ds, Np=%d, Nc=%d, Ts=%.2f, V=%d m/s, seed=%d\n', T_SIM, Np, Nc, Ts, V_MEAN, SEED);
fprintf(fid, 'All state functions: manual bypass (no predict()).\n');
fprintf(fid, 'GP-v2 uncertainty term: explicit kappa=0/kappa=0.8 ablation.\n');
fprintf(fid, 'LSTM excluded (predict() cost already quantified elsewhere).\n');
fprintf(fid, '================================================\n\n');

V2 = load('stage2_models_v2.mat');
mdl_tcn_m = extract_tcn_weights(V2.mdl_tcn);
mdl_swmlp_m = extract_dlnetwork_generic(V2.mdl_swmlp, 'net');
mdl_pinn_m = extract_dlnetwork_generic(V2.mdl_pinn_v2, 'net');

names   = {'Baseline', 'LLNFM', 'GP-v2 (kappa=0)', 'GP-v2 (kappa=0.8)', 'PINN-v2', 'TCN', 'SW-MLP'};
kinds   = {'baseline', 'llnfm', 'gp0', 'gp08', 'pinn', 'tcn', 'swmlp'};
results = struct('name', {}, 'rmse_omega_rpm', {}, 'pitch_activity_deg', {}, ...
    'mean_cp', {}, 'mean_cpu_ms', {}, 'n_infeasible', {});

for i = 1:numel(names)
    fprintf('--- %s ---\n', names{i});
    r = run_one(names{i}, kinds{i}, V2, mdl_tcn_m, mdl_swmlp_m, mdl_pinn_m, ...
        p, cfg, V_wind, N_steps, Ts, Np, Nc, omega_ref);
    results(end+1) = r; %%#ok<AGROW>
    fprintf('  RMSE=%.4f rpm  PA=%.2f deg  mean_Cp=%.4f  CPU=%.1fms  infeasible=%d/%d\n\n', ...
        r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cp, r.mean_cpu_ms, r.n_infeasible, N_steps);
    fprintf(fid, '[%s]\n  rmse_omega_rpm = %.4f\n  pitch_activity_deg = %.2f\n', r.name, r.rmse_omega_rpm, r.pitch_activity_deg);
    fprintf(fid, '  mean_cp = %.4f\n  mean_cpu_ms = %.2f\n  n_infeasible = %d/%d\n\n', r.mean_cp, r.mean_cpu_ms, r.n_infeasible, N_steps);
end
fclose(fid);
save('results/item25_unified_protocol.mat', 'results');
fprintf('\nWrote %s\n', txt_path);
end

%% -- per-controller runner --------------------------------------------
function r = run_one(name, kind, V2, mdl_tcn_m, mdl_swmlp_m, mdl_pinn_m, p, cfg, V_wind, N_steps, Ts, Np, Nc, omega_ref)
nlobj = build_controller(kind, V2, mdl_tcn_m, mdl_swmlp_m, mdl_pinn_m, p, cfg, Np, Nc);
x = [p.omega_r*0.97; 3.5]; mv = x(2);
omega_hist = zeros(N_steps,1); beta_hist = zeros(N_steps,1);
cpu_hist = zeros(N_steps,1); exitflag_hist = zeros(N_steps,1);
seq_buf = repmat([x(1), x(2), V_wind(1), mv], 10, 1);
options = nlmpcmoveopt;
for k = 1:N_steps
    Vk = V_wind(k);
    switch kind
        case 'baseline', options.Parameters = {Vk, p};
        case 'llnfm',    options.Parameters = {Vk, V2.mdl_llnfm};
        case 'gp0',      options.Parameters = {Vk, V2.mdl_gp_v2, omega_ref, 0,   cfg.mpc.Q, 0.01, cfg.mpc.R};
        case 'gp08',     options.Parameters = {Vk, V2.mdl_gp_v2, omega_ref, 0.8, cfg.mpc.Q, 0.01, cfg.mpc.R};
        case 'pinn',     options.Parameters = {Vk, mdl_pinn_m};
        case 'tcn',      mdl_tcn_m.seq_buf = seq_buf;   options.Parameters = {Vk, mdl_tcn_m};
        case 'swmlp',    mdl_swmlp_m.seq_buf = seq_buf; options.Parameters = {Vk, mdl_swmlp_m};
    end
    t0 = tic;
    [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
    cpu_hist(k) = toc(t0)*1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    exitflag_hist(k) = info.ExitFlag;
    seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
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

%% -- controller construction --------------------------------------------
function nlobj = build_controller(kind, V2, mdl_tcn_m, mdl_swmlp_m, mdl_pinn_m, p, cfg, Np, Nc)
nlobj = nlmpc(2, 2, 1);
nlobj.Ts = cfg.mpc.Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.MV.Min = p.beta_cp_min; nlobj.MV.Max = p.beta_cp_max;
switch kind
    case 'baseline'
        nlobj.Model.StateFcn = 'sf_baseline'; nlobj.Model.NumberOfParameters = 2;
        nlobj.OV(1).Min = p.omega_mpc_min_physics; nlobj.OV(1).Max = p.omega_max;
    case 'llnfm'
        nlobj.Model.StateFcn = 'sf_llnfm'; nlobj.Model.NumberOfParameters = 2;
        nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
    case {'gp0','gp08'}
        nlobj.Model.StateFcn = 'sf_gp'; nlobj.Model.NumberOfParameters = 7;
        nlobj.Optimization.CustomCostFcn = 'cost_gp'; nlobj.Optimization.ReplaceStandardCost = true;
        nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
    case 'pinn'
        nlobj.Model.StateFcn = 'sf_pinn_manual'; nlobj.Model.NumberOfParameters = 2;
        nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
    case 'tcn'
        nlobj.Model.StateFcn = 'sf_tcn_manual'; nlobj.Model.NumberOfParameters = 2;
        nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
    case 'swmlp'
        nlobj.Model.StateFcn = 'sf_swmlp_manual'; nlobj.Model.NumberOfParameters = 2;
        nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
end
nlobj.OV(2).Min = p.beta_cp_min;
nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max * cfg.mpc.Ts;
nlobj.MV(1).RateMax =  p.dbeta_max * cfg.mpc.Ts;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
end
