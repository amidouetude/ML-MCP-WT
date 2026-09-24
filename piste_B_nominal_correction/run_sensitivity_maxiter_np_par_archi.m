function results = run_sensitivity_maxiter_np_par_archi()
% RUN_SENSITIVITY_MAXITER_NP_PAR_ARCHI  Sensitivity sweep by architecture.
% cap (reproducibility review, item 2.6). Every controller in this
% project uses MaxIterations=30, and the Appendix notes that this
% causes ExitFlag<=0 (non-positive: either the iteration cap is hit, or
% the problem is found infeasible) at essentially every step for every
% controller, including the well-behaved Baseline -- a caveat that was
% previously confined to an appendix note rather than tested directly.
% This script tests whether increasing the cap materially changes
% results (indicating 30 was insufficient) or leaves them essentially
% unchanged (indicating 30 already yields "good enough" solutions
% despite formally non-positive exit flags, consistent with common
% real-time MPC practice of capping iterations under warm-starting).
%
%   results = run_sensitivity_maxiter_np_par_archi()
%
%   METHOD
%     Re-runs Baseline, TCN (manual), and MLP-residual (manual) in
%     closed loop under MaxIterations in {10, 30, 50, 100}, identical
%     wind realization (V=14m/s, T=60s, seed=2025) and otherwise
%     identical controller settings. Reports RMSE, pitch activity,
%     mean CPU, and the ExitFlag distribution (converged/maxiter/
%     infeasible) for each condition.
%
%   OUTPUT
%     results/sensitivity_maxiter_results.txt

fprintf('==========================================================\n');
fprintf('  SENSITIVITY SWEEP: MaxIterations in {10,30,50,100} (item 2.6)\n');
fprintf('  Baseline + TCN + MLP-residual\n');
fprintf('==========================================================\n\n');

if ~exist('results', 'dir'), mkdir('results'); end
txt_path = fullfile('results', 'sensitivity_maxiter_results.txt');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;
Ts = cfg.mpc.Ts;

V2 = load('stage2_models_v2.mat');
mdl_tcn_manual = extract_tcn_weights(V2.mdl_tcn);

R = load('stage2_residual_model.mat');
mdl_res_manual = extract_residual_weights(R.mdl);

T_SIM = 60; V_MEAN = 14; WIND_SEED = 2025;
N_steps = round(T_SIM/Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);
maxiter_values = [10, 30, 50, 100];

archs = struct('name', {'Baseline', 'TCN', 'MLP-residual'}, ...
    'kind', {'baseline', 'tcn', 'residual'});

results = struct('arch', {}, 'MaxIter', {}, 'rmse_omega_rpm', {}, ...
    'pitch_activity_deg', {}, 'mean_cpu_ms', {}, 'n_converged', {}, ...
    'n_maxiter', {}, 'n_infeasible', {});

fid = fopen(txt_path, 'w');
fprintf(fid, 'SENSITIVITY SWEEP — SQP MaxIterations Cap (item 2.6)\n');
fprintf(fid, 'Generated: %s\n', datestr(now)); %#ok<TNOW1,DATST>
fprintf(fid, '(Baseline, TCN, MLP-residual, V=14 m/s, T=60s, seed=2025)\n');
fprintf(fid, '================================================\n\n');

seq_len = V2.mdl_tcn.seq_len;

for a = 1:numel(archs)
    arch = archs(a);
    for mi = 1:numel(maxiter_values)
        MaxIter = maxiter_values(mi);
        fprintf('--- %s, MaxIterations=%d ---\n', arch.name, MaxIter);

        Np1 = cfg.mpc.Np; Nc1 = cfg.mpc.Nc;
        Np2 = cfg.mpc2.Np; Nc2 = cfg.mpc2.Nc;
        if strcmp(arch.kind, 'tcn')
            Np = Np2; Nc = Nc2;
        else
            Np = Np1; Nc = Nc1;
        end

        nlobj = nlmpc(2, 2, 1);
        switch arch.kind
            case 'baseline'
                nlobj.Model.StateFcn = 'sf_baseline';
                nlobj.Model.NumberOfParameters = 2;
            case 'tcn'
                nlobj.Model.StateFcn = 'sf_tcn_manual';
                nlobj.Model.NumberOfParameters = 2;
            case 'residual'
                nlobj.Model.StateFcn = 'sf_residual_manual';
                nlobj.Model.NumberOfParameters = 4;
        end
        nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
        nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
        nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
        if strcmp(arch.kind, 'baseline')
            nlobj.OV(1).Min = p.omega_mpc_min_physics; nlobj.OV(1).Max = p.omega_max;
        else
            nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
        end
        nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
        nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
        nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
        nlobj.Optimization.SolverOptions.MaxIterations = MaxIter;   % THE variable under test
        nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = MaxIter*10;
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
                case 'baseline'
                    options.Parameters = {Vk, p};
                case 'tcn'
                    mdl_tcn_manual.seq_buf = seq_buf;
                    options.Parameters = {Vk, mdl_tcn_manual};
                case 'residual'
                    options.Parameters = {Vk, mdl_res_manual, p, Ts};
            end

            t0 = tic;
            [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
            cpu_hist(k) = toc(t0)*1000;
            mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
            exitflag_hist(k) = info.ExitFlag;

            if strcmp(arch.kind, 'tcn')
                seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
            end
            x = wt_step(x, mv(1), Vk, p, Ts);
            omega_hist(k) = x(1)*30/pi; beta_hist(k) = x(2);
        end

        r.arch = arch.name; r.MaxIter = MaxIter;
        r.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
        r.pitch_activity_deg = sum(abs(diff(beta_hist)));
        r.mean_cpu_ms = mean(cpu_hist);
        r.n_converged = sum(exitflag_hist>0);
        r.n_maxiter = sum(exitflag_hist==0);
        r.n_infeasible = sum(exitflag_hist<0);
        results(end+1) = r; %#ok<AGROW>

        fprintf('  RMSE=%.4f rpm  PA=%.2f deg  CPU=%.1fms  converged=%d maxiter=%d infeasible=%d (of %d)\n\n', ...
            r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cpu_ms, ...
            r.n_converged, r.n_maxiter, r.n_infeasible, N_steps);

        fprintf(fid, '[%s, MaxIterations=%d]\n', arch.name, MaxIter);
        fprintf(fid, '  rmse_omega_rpm = %.4f\n', r.rmse_omega_rpm);
        fprintf(fid, '  pitch_activity_deg = %.2f\n', r.pitch_activity_deg);
        fprintf(fid, '  mean_cpu_ms = %.1f\n', r.mean_cpu_ms);
        fprintf(fid, '  n_converged = %d/%d\n', r.n_converged, N_steps);
        fprintf(fid, '  n_maxiter_reached = %d/%d\n', r.n_maxiter, N_steps);
        fprintf(fid, '  n_infeasible = %d/%d\n\n', r.n_infeasible, N_steps);
    end
end

fclose(fid);

fprintf('\n============================================================\n');
fprintf('  SUMMARY\n');
fprintf('============================================================\n');
fprintf('%-14s %8s %12s %10s %10s %10s\n', 'Arch', 'MaxIter', 'RMSE(rpm)', 'PA(deg)', 'CPU(ms)', 'Converged');
for i = 1:numel(results)
    r = results(i);
    fprintf('%-14s %8d %12.4f %10.2f %10.1f %9d/%d\n', ...
        r.arch, r.MaxIter, r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cpu_ms, r.n_converged, N_steps);
end
fprintf('============================================================\n');

% ── Interpretation: for each arch, compare MaxIter=30 (current paper
%    setting) against MaxIter=100 (most permissive tested) ─────────────────
fprintf('\nRMSE change, MaxIter=30 -> MaxIter=100 (current setting vs most permissive):\n');
for a = 1:numel(archs)
    mask30  = strcmp({results.arch}, archs(a).name) & [results.MaxIter]==30;
    mask100 = strcmp({results.arch}, archs(a).name) & [results.MaxIter]==100;
    r30 = results(mask30); r100 = results(mask100);
    pct_change = 100*(r100.rmse_omega_rpm - r30.rmse_omega_rpm)/r30.rmse_omega_rpm;
    fprintf('  %-14s: %.4f -> %.4f rpm (%.1f%% change)\n', archs(a).name, ...
        r30.rmse_omega_rpm, r100.rmse_omega_rpm, pct_change);
end

save('results/sensitivity_maxiter.mat', 'results');
fprintf('\nWrote %s and results/sensitivity_maxiter.mat\n', txt_path);

end
