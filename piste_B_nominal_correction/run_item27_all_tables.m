function run_item27_all_tables()
%% RUN_ITEM27_ALL_TABLES  Runs the gain-scheduled PI controller under
%% every distinct protocol used across this paper's closed-loop tables,
%% per the referee's explicit instruction (item 2.7): "Add a
%% gain-scheduled controller... to every table."
%%
%% Covers: tab:v1_results (T=120s,Np=10,Nc=4), tab:v2_results
%% (T=120s,Np=15,Nc=4), tab:bypass_closed_loop (T=60s,V=14,seed=2025),
%% tab:monte_carlo_extended (T=60s, V in {12,14,16}, seeds 2025-2029).
%% tab:unified_protocol already has its PI row (run separately).

addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results', 'dir'), mkdir('results'); end

cfg = stage0_config();
p0 = get_wt_params();

% -- Published DISCON gain-scheduled PI parameters (Jonkman et al. 2009) --
PC.KP      = 0.01882681;
PC.KI      = 0.008068634;
PC.KK      = 0.109996;
PC.MaxRat  = 0.1396263;
PC.RefSpd  = p0.omega_r * p0.N_gear;
PC.CornerFreq = 1.570796325;

fid = fopen('results/item27_all_tables_results.txt', 'w');
fprintf(fid, 'ITEM 2.7 GAIN-SCHEDULED PI -- ALL TABLES\n');
fprintf(fid, 'Generated: %s\n\n', datestr(now));

%% ===== 1. V1 protocol: T=120s, Np=10, Nc=4 =====%%
fprintf('--- V1 protocol (T=120s, Np=10, Nc=4) ---\n');
r1 = run_pi_once(PC, p0, cfg, 120, 14, 2025, cfg.mpc.Np, cfg.mpc.Nc);
print_and_log(fid, 'V1 (T=120s,Np=10,Nc=4)', r1);

%% ===== 2. V2 protocol: T=120s, Np=15, Nc=4 =====%%
fprintf('--- V2 protocol (T=120s, Np=15, Nc=4) ---\n');
r2 = run_pi_once(PC, p0, cfg, 120, 14, 2025, cfg.mpc2.Np, cfg.mpc2.Nc);
print_and_log(fid, 'V2 (T=120s,Np=15,Nc=4)', r2);

%% ===== 3. Piste B single-run: T=60s, V=14, seed=2025 =====%%
fprintf('--- Piste B single-run (T=60s, V=14, seed=2025) ---\n');
r3 = run_pi_once(PC, p0, cfg, 60, 14, 2025, cfg.mpc2.Np, cfg.mpc2.Nc);
print_and_log(fid, 'Piste B (T=60s,V=14,seed=2025)', r3);

%% ===== 4. Monte Carlo: T=60s, V in {12,14,16}, seeds 2025-2029 =====%%
fprintf('--- Monte Carlo (T=60s, V={12,14,16}, 5 seeds) ---\n');
V_list = [12, 14, 16];
seeds = 2025:2029;
fprintf(fid, '[Monte Carlo, Gain-Scheduled PI]\n');
for vi = 1:numel(V_list)
    rmse_list = zeros(1,numel(seeds));
    for si = 1:numel(seeds)
        rr = run_pi_once(PC, p0, cfg, 60, V_list(vi), seeds(si), cfg.mpc2.Np, cfg.mpc2.Nc);
        rmse_list(si) = rr.rmse_omega_rpm;
    end
    mc_mean = mean(rmse_list); mc_std = std(rmse_list);
    fprintf('  V=%d m/s: %.3f +/- %.3f rpm\n', V_list(vi), mc_mean, mc_std);
    fprintf(fid, '  V=%d: mean=%.3f std=%.3f (rmse per seed: %s)\n', ...
        V_list(vi), mc_mean, mc_std, mat2str(round(rmse_list,3)));
end
fprintf(fid, '\n');

fclose(fid);
fprintf('\nWrote results/item27_all_tables_results.txt\n');
end

%% -- Runs one PI closed-loop simulation, returns summary stats --------
function r = run_pi_once(PC, p, cfg, T_SIM, V_MEAN, SEED, Np, Nc) %#ok<INUSD>
p.dt = cfg.mpc.Ts;
Ts = cfg.mpc.Ts;
N_steps = round(T_SIM/Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, SEED);

x = [p.omega_r*0.97; 3.5];
beta_cmd_deg = x(2);
integ_rad = 0;
gen_speed_filt = x(1) * p.N_gear;
alpha_lpf = exp(-PC.CornerFreq * Ts);

omega_hist = zeros(N_steps,1); beta_hist = zeros(N_steps,1); cpu_hist = zeros(N_steps,1);

for k = 1:N_steps
    t0 = tic;
    Vk = V_wind(k);
    gen_speed_raw = x(1) * p.N_gear;
    gen_speed_filt = alpha_lpf*gen_speed_filt + (1-alpha_lpf)*gen_speed_raw;
    beta_rad = beta_cmd_deg * pi/180;
    GK = 1 / (1 + beta_rad/PC.KK);
    KP = GK * PC.KP; KI = GK * PC.KI;
    speed_err = gen_speed_filt - PC.RefSpd;
    integ_rad = integ_rad + KI * speed_err * Ts;
    integ_rad = max(0, min(pi/2, integ_rad));
    beta_cmd_rad = KP * speed_err + integ_rad;
    beta_cmd_rad = max(0, min(pi/2, beta_cmd_rad));
    beta_cmd_deg_raw = beta_cmd_rad * 180/pi;
    max_rate_deg = PC.MaxRat * 180/pi;
    dbeta = max(-max_rate_deg*Ts, min(max_rate_deg*Ts, beta_cmd_deg_raw - beta_cmd_deg));
    beta_cmd_deg = beta_cmd_deg + dbeta;
    beta_cmd_deg = max(p.beta_cp_min, min(p.beta_cp_max, beta_cmd_deg));
    cpu_hist(k) = toc(t0)*1000;
    x = wt_step(x, beta_cmd_deg, Vk, p, Ts);
    omega_hist(k) = x(1)*30/pi;
    beta_hist(k) = x(2);
end

r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
r.pitch_activity_deg = sum(abs(diff(beta_hist)));
lambda = p.R * (omega_hist*pi/30) ./ V_wind(1:N_steps);
cp_vals = arrayfun(@(l,b) cp_lambda_beta(l,b), lambda, beta_hist);
r.mean_cp = mean(cp_vals);
r.mean_cpu_ms = mean(cpu_hist);
r.min_omega_rpm = min(omega_hist);
r.max_omega_rpm = max(omega_hist);
end

%% -- Print + log helper -------------------------------------------------
function print_and_log(fid, label, r)
fprintf('  RMSE=%.4f rpm  PA=%.2f deg  mean_Cp=%.4f  CPU=%.4fms  range=[%.2f,%.2f] rpm\n', ...
    r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cp, r.mean_cpu_ms, r.min_omega_rpm, r.max_omega_rpm);
fprintf(fid, '[%s]\n', label);
fprintf(fid, '  rmse_omega_rpm = %.4f\n', r.rmse_omega_rpm);
fprintf(fid, '  pitch_activity_deg = %.2f\n', r.pitch_activity_deg);
fprintf(fid, '  mean_cp = %.4f\n', r.mean_cp);
fprintf(fid, '  mean_cpu_ms = %.4f\n', r.mean_cpu_ms);
fprintf(fid, '  omega_range_rpm = [%.2f, %.2f]\n\n', r.min_omega_rpm, r.max_omega_rpm);
end