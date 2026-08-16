function results = run_item27_gain_scheduled_pi()
%% RUN_ITEM27_GAIN_SCHEDULED_PI  Gain-scheduled PI pitch controller,
%% reproducing the NREL 5MW reference turbine baseline controller
%% (Jonkman et al. 2009, DISCON.dll), item 2.7 of the reproducibility
%% review.
%%
%% Published parameters confirmed from NREL forum posts by J. Jonkman
%% (PC_RefSpd/N_gear = 122.909/97 = 1.2671 rad/s matches this
%% project's own omega_r exactly, confirming the plant is aligned
%% closely enough with the NREL 5MW reference for these published
%% gains to be used directly rather than re-derived).
%%
%% All internal PI computation is in RADIANS (Jonkman's convention);
%% only the final commanded pitch is converted to DEGREES before
%% clamping/rate-limiting, since this plant stores beta in degrees
%% (p.beta_cp_max=25 deg, p.dbeta_max=8 deg/s exactly matches
%% PC_MaxRat converted to deg/s).

addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'item27_gain_scheduled_pi_results.txt');

cfg = stage0_config();
p = get_wt_params(); p.dt = cfg.mpc.Ts;
Ts = cfg.mpc.Ts;
T_SIM = 60; V_MEAN = 14; SEED = 2025;
N_steps = round(T_SIM/Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, SEED);

PC_KP      = 0.01882681;
PC_KI      = 0.008068634;
PC_KK      = 0.109996;
PC_MaxRat  = 0.1396263;
PC_RefSpd  = p.omega_r * p.N_gear;
CornerFreq = 1.570796325;

fprintf('PC_RefSpd = %.3f rad/s (HSS); check vs published 122.909: %.4f\n', PC_RefSpd, PC_RefSpd - 122.909);

x = [p.omega_r*0.97; 3.5];
beta_cmd_deg = x(2);
integ_rad = 0;
gen_speed_filt = x(1) * p.N_gear;
alpha_lpf = exp(-CornerFreq * Ts);

omega_hist = zeros(N_steps,1); beta_hist = zeros(N_steps,1); cpu_hist = zeros(N_steps,1);

for k = 1:N_steps
    t0 = tic;
    Vk = V_wind(k);
    gen_speed_raw = x(1) * p.N_gear;
    gen_speed_filt = alpha_lpf*gen_speed_filt + (1-alpha_lpf)*gen_speed_raw;
    beta_rad = beta_cmd_deg * pi/180;
    GK = 1 / (1 + beta_rad/PC_KK);
    KP = GK * PC_KP; KI = GK * PC_KI;
    speed_err = gen_speed_filt - PC_RefSpd;
    integ_rad = integ_rad + KI * speed_err * Ts;
    integ_rad = max(0, min(pi/2, integ_rad));
    beta_cmd_rad = KP * speed_err + integ_rad;
    beta_cmd_rad = max(0, min(pi/2, beta_cmd_rad));
    beta_cmd_deg_raw = beta_cmd_rad * 180/pi;
    max_rate_deg = PC_MaxRat * 180/pi;
    dbeta = max(-max_rate_deg*Ts, min(max_rate_deg*Ts, beta_cmd_deg_raw - beta_cmd_deg));
    beta_cmd_deg = beta_cmd_deg + dbeta;
    beta_cmd_deg = max(p.beta_cp_min, min(p.beta_cp_max, beta_cmd_deg));
    cpu_hist(k) = toc(t0)*1000;
    x = wt_step(x, beta_cmd_deg, Vk, p, Ts);
    omega_hist(k) = x(1)*30/pi;
    beta_hist(k) = x(2);
end

rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
pitch_activity_deg = sum(abs(diff(beta_hist)));
lambda = p.R * (omega_hist*pi/30) ./ V_wind(1:N_steps);
cp_vals = arrayfun(@(l,b) cp_lambda_beta(l,b), lambda, beta_hist);
mean_cp = mean(cp_vals);
mean_cpu_ms = mean(cpu_hist);
min_omega_rpm = min(omega_hist);
max_omega_rpm = max(omega_hist);

fprintf('RMSE=%.4f rpm  PA=%.2f deg  mean_Cp=%.4f  CPU=%.3fms\n', rmse_omega_rpm, pitch_activity_deg, mean_cp, mean_cpu_ms);
fprintf('omega range: [%.2f, %.2f] rpm\n', min_omega_rpm, max_omega_rpm);

fid = fopen(txt_path, 'w');
fprintf(fid, 'ITEM 2.7 GAIN-SCHEDULED PI RESULTS (NREL 5MW reference, Jonkman 2009)\n');
fprintf(fid, 'Generated: %s\n', datestr(now));
fprintf(fid, 'T=%ds, Ts=%.2f, V=%d m/s, seed=%d\n', T_SIM, Ts, V_MEAN, SEED);
fprintf(fid, 'PC_KP=%.8f, PC_KI=%.9f, PC_KK=%.6f, PC_MaxRat=%.7f, PC_RefSpd=%.3f\n', PC_KP, PC_KI, PC_KK, PC_MaxRat, PC_RefSpd);
fprintf(fid, '================================================\n\n');
fprintf(fid, '[Gain-Scheduled PI]\n');
fprintf(fid, '  rmse_omega_rpm = %.4f\n', rmse_omega_rpm);
fprintf(fid, '  pitch_activity_deg = %.2f\n', pitch_activity_deg);
fprintf(fid, '  mean_cp = %.4f\n', mean_cp);
fprintf(fid, '  mean_cpu_ms = %.3f\n', mean_cpu_ms);
fprintf(fid, '  min_omega_rpm = %.2f\n', min_omega_rpm);
fprintf(fid, '  max_omega_rpm = %.2f\n', max_omega_rpm);
fclose(fid);

results.rmse_omega_rpm = rmse_omega_rpm;
results.pitch_activity_deg = pitch_activity_deg;
results.mean_cp = mean_cp;
results.mean_cpu_ms = mean_cpu_ms;
results.omega_hist = omega_hist;
results.beta_hist = beta_hist;
save('results/item27_gain_scheduled_pi.mat', 'results');
fprintf('Wrote %s\n', txt_path);
end