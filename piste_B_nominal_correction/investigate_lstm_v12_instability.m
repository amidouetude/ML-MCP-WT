function results = investigate_lstm_v12_instability()
% INVESTIGATE_LSTM_V12_INSTABILITY  Investigate LSTM's seed-to-seed
% RMSE instability at V=12m/s (CV=10.2%, the largest of any controller
% at any wind speed in the extended Monte Carlo evaluation), testing
% the referee's hypothesis that proximity to the Region II/III
% torque-switching boundary (item 7.7) is the cause.
%
%   results = investigate_lstm_v12_instability()
%
%   METHOD
%     Re-runs LSTM (manual bypass) across the same 5 seeds used in the
%     extended Monte Carlo evaluation, at V=12m/s, with full per-step
%     logging of pitch command, solver ExitFlag, AND rotor speed
%     (specifically tracking how often/how close omega approaches the
%     omega_r=12.1rpm torque-switching boundary from below, i.e. dips
%     into Region II territory during nominally above-rated conditions).
%
%   OUTPUT
%     results/lstm_v12_instability_results.txt
%     figures/FigH_LSTM_V12_Instability.png

fprintf('==========================================================\n');
fprintf('  INVESTIGATING LSTM V=12m/s INSTABILITY (item 7.7)\n');
fprintf('  Hypothesis: proximity to Region II/III torque-switching boundary\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'lstm_v12_instability_results.txt');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;
Ts = cfg.mpc.Ts;

V1 = load('stage2_models.mat');
mdl_lstm_manual = extract_lstm_weights(V1.mdl_lstm);
seq_len = V1.mdl_lstm.seq_len;

Np = cfg.mpc.Np; Nc = cfg.mpc.Nc;
nlobj = nlmpc(2, 2, 1);
nlobj.Model.StateFcn = 'sf_lstm_manual';
nlobj.Model.NumberOfParameters = 3;
nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
nlobj.Optimization.SolverOptions.MaxIterations = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance = 1e-4;

T_SIM = 60; V_MEAN = 12; seeds = 2025:2029;
N_steps = round(T_SIM/Ts);
omega_r_rpm = p.omega_r * 30/pi;

results = struct('seed', {}, 'rmse_omega_rpm', {}, 'n_below_rated', {}, ...
    'n_infeasible', {}, 'min_omega_rpm', {}, 'time_near_boundary_pct', {});

fid = fopen(txt_path, 'w');
fprintf(fid, 'LSTM V=12m/s INSTABILITY INVESTIGATION (item 7.7)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, 'Rated speed = %.2f rpm\n', omega_r_rpm);
fprintf(fid, '================================================\n\n');

f = figure('Color','w','Position',[40 40 1400 800]);

for si = 1:numel(seeds)
    seed = seeds(si);
    fprintf('--- Seed %d ---\n', seed);
    V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, seed);

    x = [p.omega_r*0.97; 3.5]; mv = x(2);
    omega_hist = zeros(N_steps,1); beta_hist = zeros(N_steps,1);
    exitflag_hist = zeros(N_steps,1);
    seq_buf = repmat([x(1), x(2), V_wind(1), mv], seq_len, 1);
    options = nlmpcmoveopt;

    for k = 1:N_steps
        Vk = V_wind(k);
        options.Parameters = {Vk, mdl_lstm_manual, seq_buf};
        [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
        exitflag_hist(k) = info.ExitFlag;
        seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
        x = wt_step(x, mv(1), Vk, p, Ts);
        omega_hist(k) = x(1)*30/pi; beta_hist(k) = x(2);
    end

    r.seed = seed;
    r.rmse_omega_rpm = sqrt(mean((omega_hist - omega_r_rpm).^2));
    r.n_below_rated = sum(omega_hist < omega_r_rpm);
    r.n_infeasible = sum(exitflag_hist < 0);
    r.min_omega_rpm = min(omega_hist);
    r.time_near_boundary_pct = 100*mean(abs(omega_hist - omega_r_rpm) < 0.5);
    results(end+1) = r; %#ok<AGROW>

    fprintf('  RMSE=%.4f rpm  min_omega=%.2f rpm  time_near_boundary=%.1f%%  infeasible=%d/%d\n', ...
        r.rmse_omega_rpm, r.min_omega_rpm, r.time_near_boundary_pct, r.n_infeasible, N_steps);

    fprintf(fid, '[seed=%d]\n', seed);
    fprintf(fid, '  rmse_omega_rpm = %.4f\n', r.rmse_omega_rpm);
    fprintf(fid, '  min_omega_rpm = %.4f\n', r.min_omega_rpm);
    fprintf(fid, '  pct_time_below_rated = %.1f\n', 100*r.n_below_rated/N_steps);
    fprintf(fid, '  pct_time_within_0.5rpm_of_boundary = %.1f\n', r.time_near_boundary_pct);
    fprintf(fid, '  n_infeasible = %d/%d\n\n', r.n_infeasible, N_steps);

    t_vec = (0:N_steps-1)*Ts;
    subplot(numel(seeds), 1, si);
    plot(t_vec, omega_hist, 'b-', 'LineWidth', 1);
    yline(omega_r_rpm, 'k--', 'Rated');
    ylabel(sprintf('seed=%d\n\\omega (rpm)', seed), 'FontSize', 8);
    if si==1, title('LSTM Rotor Speed, V=12m/s, 5 Seeds — Boundary Proximity Check', 'FontWeight','bold'); end
    if si==numel(seeds), xlabel('Time (s)'); end
    grid on;
end
fclose(fid);

fig_dir = fullfile(pwd, 'figures');
if ~isfolder(fig_dir), mkdir(fig_dir); end
print(f, fullfile(fig_dir, 'FigH_LSTM_V12_Instability'), '-dpng', '-r150');
fprintf('\nSaved figures/FigH_LSTM_V12_Instability.png\n');

fprintf('\n============================================================\n');
fprintf('  SUMMARY — testing the torque-switching-boundary hypothesis\n');
fprintf('============================================================\n');
rmse_all = [results.rmse_omega_rpm];
boundary_all = [results.time_near_boundary_pct];
[rho, pval] = corr(rmse_all', boundary_all');
fprintf('Correlation(RMSE, time-near-boundary) = %.3f (p=%.3f)\n', rho, pval);
if rho > 0.5
    fprintf('POSITIVE correlation: seeds spending more time near the\n');
    fprintf('torque-switching boundary DO show higher RMSE -- supports the\n');
    fprintf('referee''s hypothesis.\n');
else
    fprintf('No strong positive correlation found -- boundary proximity\n');
    fprintf('alone does not clearly explain the seed-to-seed variability.\n');
end

save('results/lstm_v12_instability.mat', 'results');
fprintf('Saved results/lstm_v12_instability.mat\n');

end
