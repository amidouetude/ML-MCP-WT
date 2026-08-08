function result = test_gp_jacobian_closed_loop()
% TEST_GP_JACOBIAN_CLOSED_LOOP  Re-run the GP-v2 closed-loop test with an
% explicit Jacobian.StateFcn (sf_gp_jacobian.m) registered on the nlmpc
% object, to test whether removing fmincon's own global numerical
% differentiation (perturbing the full decision vector and re-evaluating
% the entire trajectory) resolves the ~1.2s/step, 300/300 overrun result
% found by test_remaining_surrogates_closed_loop.m on this same machine.
%
%   result = test_gp_jacobian_closed_loop()
%
%   COMPARISON POINT (this machine, MATLAB R2026a, no Jacobian supplied):
%     GP-v2 (V2): mean=1233.1ms  max=6548.3ms  overruns=300/300
%
%   If overruns drop sharply here, that supports the hypothesis that the
%   bottleneck is fmincon's own numerical differentiation strategy (global,
%   full-trajectory re-evaluation) rather than GP inference cost itself or
%   MATLAB-version-specific JIT/dlarray behavior — and that supplying an
%   analytical (or locally-computed) Jacobian is the correct fix, usable
%   entirely within MATLAB without changing the surrogate model.

%% ── Configuration (identical to test_remaining_surrogates_closed_loop.m) ──
T_SIM        = 30;
V_MEAN       = 14;
WIND_SEED    = 2025;
SPIKE_MS     = 50;
TS_BUDGET_MS = 100;

fprintf('==========================================================\n');
fprintf('  GP-v2 WITH ANALYTICAL Jacobian.StateFcn — CLOSED-LOOP TEST\n');
fprintf('  (%ds, V=%dm/s, MATLAB %s)\n', T_SIM, V_MEAN, version);
fprintf('==========================================================\n\n');

%% ── Load config, plant params, models ───────────────────────────────────
cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

V2 = load('stage2_models_v2.mat');
models_v2.llnfm   = V2.mdl_llnfm;
models_v2.tcn     = V2.mdl_tcn;
models_v2.swmlp   = V2.mdl_swmlp;
models_v2.gp_v2   = V2.mdl_gp_v2;
models_v2.pinn_v2 = V2.mdl_pinn_v2;
controllers_v2 = stage3_design_controllers_v2(p, models_v2, cfg);

fprintf('  ACTUAL V2 horizon settings used: Np=%d  Nc=%d  Ts=%.2f\n\n', ...
    cfg.mpc2.Np, cfg.mpc2.Nc, cfg.mpc2.Ts);

%% ── Register the analytical/finite-diff Jacobian on the GP-v2 controller ──
nlobj = controllers_v2.gp_v2;
nlobj.Jacobian.StateFcn = 'sf_gp_jacobian';
fprintf('  Jacobian.StateFcn = ''sf_gp_jacobian'' registered on GP-v2 controller.\n\n');

%% ── Wind profile ─────────────────────────────────────────────────────────
N_steps = round(T_SIM / cfg.mpc.Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, cfg.mpc.Ts, WIND_SEED);

%% ── Run closed loop ──────────────────────────────────────────────────────
omega_ref_radps = 12.1 * pi/30;
kappa_default   = cfg.mpc.kappa;

x  = [p.omega_r; 0];
mv = 0;
omega_hist = zeros(N_steps,1);
cpu_ms     = zeros(N_steps,1);
max_iter_hits = 0;

options = nlmpcmoveopt;

fprintf('--- Running GP-v2 (V2) WITH Jacobian (%d steps) ---\n', N_steps);
for k = 1:N_steps
    Vk = V_wind(k);
    options.Parameters = {Vk, models_v2.gp_v2, omega_ref_radps, kappa_default};
    t0 = tic;
    [mv, options, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], options);
    cpu_ms(k) = toc(t0) * 1000;

    if isfield(info, 'ExitFlag') && info.ExitFlag <= 0
        max_iter_hits = max_iter_hits + 1;
    end

    x = wt_step(x, mv(1), Vk, p, cfg.mpc.Ts);
    omega_hist(k) = x(1) * 30/pi;

    if mod(k, 50) == 0
        fprintf('  step %d/%d  cpu=%.1fms  omega=%.2f rpm\n', ...
            k, N_steps, cpu_ms(k), omega_hist(k));
    end
end

result.name           = 'GP-v2 (V2) + analytical Jacobian';
result.cpu_ms         = cpu_ms;
result.max_cpu_ms     = max(cpu_ms);
result.mean_cpu_ms    = mean(cpu_ms);
result.n_spikes_50ms  = sum(cpu_ms > SPIKE_MS);
result.n_spikes_100ms = sum(cpu_ms > TS_BUDGET_MS);
result.max_iter_hits  = max_iter_hits;
result.rmse_omega_rpm = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));

fprintf(['\nDONE: mean=%.1fms  max=%.1fms  spikes(>50ms)=%d/%d  ' ...
         'overruns(>100ms budget)=%d/%d  RMSE=%.3f rpm\n'], ...
    result.mean_cpu_ms, result.max_cpu_ms, result.n_spikes_50ms, N_steps, ...
    result.n_spikes_100ms, N_steps, result.rmse_omega_rpm);

fprintf('\n============================================================\n');
fprintf('  COMPARISON: WITHOUT Jacobian (previous run, this machine)\n');
fprintf('    GP-v2 (V2): mean=1233.1ms  max=6548.3ms  overruns=300/300\n');
fprintf('  WITH Jacobian (this run):\n');
fprintf('    GP-v2 (V2): mean=%.1fms  max=%.1fms  overruns=%d/300\n', ...
    result.mean_cpu_ms, result.max_cpu_ms, result.n_spikes_100ms);
fprintf('============================================================\n');

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
outfile = sprintf('test_gp_jacobian_closed_loop_%s.mat', ts);
save(outfile, 'result', 'T_SIM', 'V_MEAN', 'WIND_SEED');
fprintf('\nResults saved to %s\n', outfile);

end
