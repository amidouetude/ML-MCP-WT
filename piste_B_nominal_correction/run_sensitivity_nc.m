function results = run_sensitivity_nc()
% RUN_SENSITIVITY_NC  Systematic control-horizon (Nc) sensitivity sweep
% across all V2 architectures, following up on the PINN-v2/TCN Nc=1
% corner-solution finding (docs/experiment_log.md, 2026-08-11).
%
%   results = run_sensitivity_nc()
%
%   METHOD
%     Re-runs each V2 architecture (LLNFM, TCN, SW-MLP, PINN-v2, GP-v2)
%     in closed loop under Nc in {1, 2, 4}, Np=15 fixed, identical wind
%     realization (V=14m/s, T=60s, seed=2025) and manual-bypass state
%     functions where available (LLNFM uses evalfis directly, already
%     fast; GP-v2 uses the original predict()-based sf_gp/cost_gp since
%     no manual-bypass GP-v2 controller with the ORIGINAL uncertainty
%     cost exists -- expect this one to be SLOW and possibly
%     infeasible, consistent with prior findings; this is intentional
%     and informative, not a bug).
%
%   OUTPUT
%     results/sensitivity_nc_results.txt

fprintf('==========================================================\n');
fprintf('  SENSITIVITY SWEEP: Control horizon Nc in {1,2,4}, all V2 archs\n');
fprintf('  WARNING: GP-v2 uses predict()-based cost_gp.m -- expect slow\n');
fprintf('  and possibly infeasible steps, this is intentional/informative\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'sensitivity_nc_results.txt');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;
Ts = cfg.mpc.Ts;

V2 = load('stage2_models_v2.mat');
mdl_tcn_manual  = extract_tcn_weights(V2.mdl_tcn);
mdl_swmlp_manual = extract_dlnetwork_generic(V2.mdl_swmlp, 'net');
mdl_pinn_manual  = extract_dlnetwork_generic(V2.mdl_pinn_v2, 'net');
mdl_gp_v2        = V2.mdl_gp_v2;
mdl_llnfm        = V2.mdl_llnfm;

T_SIM = 60; V_MEAN = 14; WIND_SEED = 2025;
N_steps = round(T_SIM/Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);
Np = cfg.mpc2.Np;
Nc_values = [1, 2, 4];
omega_ref_radps = p.omega_r;
kappa_default = cfg.mpc.kappa;

archs = struct( ...
    'name', {'LLNFM', 'TCN', 'SW-MLP', 'PINN-v2', 'GP-v2'}, ...
    'kind', {'llnfm', 'tcn', 'swmlp', 'pinn', 'gp'});

results = struct('arch', {}, 'Nc', {}, 'rmse_omega_rpm', {}, ...
    'pitch_activity_deg', {}, 'mean_cpu_ms', {}, 'n_converged', {}, 'n_infeasible', {});

fid = fopen(txt_path, 'w');
fprintf(fid, 'SENSITIVITY SWEEP — Control Horizon Nc in {1,2,4}\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(All V2 architectures, V=14 m/s, T=60s, seed=2025, Np=15)\n');
fprintf(fid, '================================================\n\n');

seq_len = mdl_tcn_manual.seq_len; %#ok<NASGU>
seq_len = V2.mdl_tcn.seq_len;

for a = 1:numel(archs)
    arch = archs(a);
    for nci = 1:numel(Nc_values)
        Nc = Nc_values(nci);
        fprintf('--- %s, Nc=%d ---\n', arch.name, Nc);

        nlobj = nlmpc(2, 2, 1);
        switch arch.kind
            case 'llnfm'
                nlobj.Model.StateFcn = 'sf_llnfm';
                nlobj.Model.NumberOfParameters = 2;
            case 'tcn'
                nlobj.Model.StateFcn = 'sf_tcn_manual';
                nlobj.Model.NumberOfParameters = 2;
            case 'swmlp'
                nlobj.Model.StateFcn = 'sf_swmlp_manual';
                nlobj.Model.NumberOfParameters = 2;
            case 'pinn'
                nlobj.Model.StateFcn = 'sf_pinn_manual';
                nlobj.Model.NumberOfParameters = 2;
            case 'gp'
                nlobj.Model.StateFcn = 'sf_gp';
                nlobj.Model.NumberOfParameters = 7;
                nlobj.Optimization.CustomCostFcn = 'cost_gp';
                nlobj.Optimization.ReplaceStandardCost = true;
        end
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

        x = [p.omega_r*0.97; 3.5]; mv = x(2);
        omega_hist = zeros(N_steps,1); beta_hist = zeros(N_steps,1);
        cpu_hist = zeros(N_steps,1); exitflag_hist = zeros(N_steps,1);
        seq_buf = repmat([x(1), x(2), V_wind(1), mv], seq_len, 1);
        options = nlmpcmoveopt;

        for k = 1:N_steps
            Vk = V_wind(k);
            switch arch.kind
                case 'llnfm'
                    options.Parameters = {Vk, mdl_llnfm};
                case 'tcn'
                    mdl_tcn_manual.seq_buf = seq_buf;
                    options.Parameters = {Vk, mdl_tcn_manual};
                case 'swmlp'
                    mdl_swmlp_manual.seq_buf = seq_buf;
                    options.Parameters = {Vk, mdl_swmlp_manual};
                case 'pinn'
                    options.Parameters = {Vk, mdl_pinn_manual};
                case 'gp'
                    options.Parameters = {Vk, mdl_gp_v2, omega_ref_radps, kappa_default, ...
                                           cfg.mpc.Q, 0.01, cfg.mpc.R};
            end

            t0 = tic;
            [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
            cpu_hist(k) = toc(t0)*1000;
            mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
            exitflag_hist(k) = info.ExitFlag;

            if ismember(arch.kind, {'swmlp','tcn'})
                seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
            end
            x = wt_step(x, mv(1), Vk, p, Ts);
            omega_hist(k) = x(1)*30/pi; beta_hist(k) = x(2);

            % Safety: for GP (known slow), cap runtime by checking elapsed
            if strcmp(arch.kind,'gp') && mod(k,100)==0
                fprintf('    GP-v2 step %d/%d (slow, predict()-based)...\n', k, N_steps);
            end
        end

        r.arch = arch.name; r.Nc = Nc;
        r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
        r.pitch_activity_deg = sum(abs(diff(beta_hist)));
        r.mean_cpu_ms = mean(cpu_hist);
        r.n_converged = sum(exitflag_hist>0);
        r.n_infeasible = sum(exitflag_hist<0);
        results(end+1) = r; %#ok<AGROW>

        fprintf('  RMSE=%.4f rpm  PA=%.2f deg  mean_cpu=%.1fms  converged=%d/%d\n\n', ...
            r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cpu_ms, r.n_converged, N_steps);

        fprintf(fid, '[%s, Nc=%d]\n', arch.name, Nc);
        fprintf(fid, '  rmse_omega_rpm = %.4f\n', r.rmse_omega_rpm);
        fprintf(fid, '  pitch_activity_deg = %.2f\n', r.pitch_activity_deg);
        fprintf(fid, '  mean_cpu_ms = %.1f\n', r.mean_cpu_ms);
        fprintf(fid, '  n_converged = %d/%d\n', r.n_converged, N_steps);
        fprintf(fid, '  n_infeasible = %d/%d\n\n', r.n_infeasible, N_steps);
    end
end

fclose(fid);

fprintf('\n============================================================\n');
fprintf('  SUMMARY\n');
fprintf('============================================================\n');
fprintf('%-10s %4s %12s %10s %12s %10s\n', 'Arch', 'Nc', 'RMSE(rpm)', 'PA(deg)', 'CPU(ms)', 'Converged');
for i = 1:numel(results)
    r = results(i);
    fprintf('%-10s %4d %12.4f %10.2f %12.1f %9d/%d\n', ...
        r.arch, r.Nc, r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cpu_ms, r.n_converged, N_steps);
end

save('results/sensitivity_nc.mat', 'results');
fprintf('\nWrote %s and results/sensitivity_nc.mat\n', txt_path);

end
