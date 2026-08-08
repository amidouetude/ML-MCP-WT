function results = test_swmlp_pinn_manual_closed_loop()
% TEST_SWMLP_PINN_MANUAL_CLOSED_LOOP  Extends the predict()-bypass
% finding to the REAL, previously-excluded V2 surrogates (SW-MLP,
% PINN-v2), using the actual trained models from stage2_models_v2.mat
% -- not toy models built for this project, the same surrogates
% originally excluded from Stage 3 V2 closed-loop comparison due to
% catastrophic SQP cost.
%
%   results = test_swmlp_pinn_manual_closed_loop()
%
%   PLANT
%     Tested against wt_step.m (the NOMINAL plant), matching how these
%     surrogates were originally trained (on stage1_data.mat, generated
%     from wt_step.m) and evaluated in the V1/V2 project -- unlike the
%     Piste B tests, which used wt_step_true.m for a deliberately
%     introduced model-mismatch experiment. There is no mismatch
%     question here: this is purely a feasibility re-test of
%     previously-excluded architectures now that the predict()
%     bottleneck is understood.
%
%   PREREQUISITES
%     stage2_models_v2.mat in the current folder or on path (copy from
%     the original V1/V2 project if not already present).

T_SIM  = 60;
V_MEAN = 14;
WIND_SEED = 2025;
TS_BUDGET_MS = 100;

fprintf('==========================================================\n');
fprintf('  RE-TESTING SW-MLP AND PINN-v2 WITH THE predict() BYPASS\n');
fprintf('  (%ds, V=%dm/s)\n', T_SIM, V_MEAN);
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();
p.dt = cfg.mpc.Ts;

if ~exist('stage2_models_v2.mat', 'file')
    error(['stage2_models_v2.mat not found. Copy it from the original ' ...
           'V1/V2 project into this folder or common/ first.']);
end
V2 = load('stage2_models_v2.mat');
mdl_swmlp   = V2.mdl_swmlp;
mdl_pinn_v2 = V2.mdl_pinn_v2;

fprintf('--- Extracting SW-MLP (generic architecture inspection) ---\n');
mdl_swmlp_manual = extract_dlnetwork_generic(mdl_swmlp, 'net');
fprintf('--- Extracting PINN-v2 (generic architecture inspection) ---\n');
mdl_pinn_manual = extract_dlnetwork_generic(mdl_pinn_v2, 'net');
fprintf('\n');

% ── Verify manual forward pass against predict() on random test points ──────
fprintf('--- Verifying SW-MLP manual forward pass vs predict() ---\n');
verify_swmlp(mdl_swmlp, mdl_swmlp_manual);
fprintf('--- Verifying PINN-v2 manual forward pass vs predict() ---\n');
verify_pinn(mdl_pinn_v2, mdl_pinn_manual);
fprintf('\n');

% ── Build controllers (V2 horizon settings, per cfg.mpc2) ───────────────────
Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc; Ts = cfg.mpc2.Ts;
fprintf('Using V2 horizon settings: Np=%d Nc=%d Ts=%.2f\n\n', Np, Nc, Ts);

nlobj_baseline    = build_controller('sf_baseline', 2, p, cfg, Np, Nc, Ts, true);
nlobj_swmlp       = build_controller('sf_swmlp',        2, p, cfg, Np, Nc, Ts, false);
nlobj_swmlp_man   = build_controller('sf_swmlp_manual', 2, p, cfg, Np, Nc, Ts, false);
nlobj_pinn        = build_controller('sf_pinn',         2, p, cfg, Np, Nc, Ts, false);
nlobj_pinn_man    = build_controller('sf_pinn_manual',  2, p, cfg, Np, Nc, Ts, false);

N_steps = round(T_SIM / Ts);
V_wind  = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);

test_cases = struct( ...
    'name',  {'Baseline', 'SW-MLP (predict)', 'SW-MLP (manual)', ...
              'PINN-v2 (predict)', 'PINN-v2 (manual)'}, ...
    'nlobj', {nlobj_baseline, nlobj_swmlp, nlobj_swmlp_man, nlobj_pinn, nlobj_pinn_man}, ...
    'kind',  {'baseline', 'swmlp', 'swmlp_manual', 'pinn', 'pinn_manual'});

results = struct('name', {}, 'cpu_ms', {}, 'max_cpu_ms', {}, ...
    'n_overruns_100ms', {}, 'rmse_omega_rpm', {});

for c = 1:numel(test_cases)
    tc = test_cases(c);
    fprintf('\n--- Running %s (%d steps) ---\n', tc.name, N_steps);

    x  = [p.omega_r * 0.97; 3.5];   % FIX: matches stage3_run_simulation.m
    mv = x(2);                       % FIX: matches original's u_prev = x(2)
    omega_hist = zeros(N_steps,1);
    cpu_ms     = zeros(N_steps,1);
    options = nlmpcmoveopt;

    seq_len = mdl_swmlp.seq_len;
    seq_buf = repmat([x(1), x(2), V_wind(1), mv], seq_len, 1);

    for k = 1:N_steps
        Vk = V_wind(k);
        switch tc.kind
            case 'baseline'
                options.Parameters = {Vk, p};
            case 'swmlp'
                mdl_swmlp.seq_buf = seq_buf;
                options.Parameters = {Vk, mdl_swmlp};
            case 'swmlp_manual'
                mdl_swmlp_manual.seq_buf = seq_buf;
                options.Parameters = {Vk, mdl_swmlp_manual};
            case 'pinn'
                options.Parameters = {Vk, mdl_pinn_v2};
            case 'pinn_manual'
                options.Parameters = {Vk, mdl_pinn_manual};
        end

        t0 = tic;
        [mv, options, ~] = nlmpcmove(tc.nlobj, x, mv, [p.omega_r,0], [], options);
        cpu_ms(k) = toc(t0) * 1000;
        mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));   % FIX: safety clamp

        if ismember(tc.kind, {'swmlp','swmlp_manual'})
            seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
        end

        x = wt_step(x, mv(1), Vk, p, Ts);
        omega_hist(k) = x(1) * 30/pi;

        if mod(k, 100) == 0
            fprintf('  step %d/%d  cpu=%.1fms  omega=%.2f rpm\n', ...
                k, N_steps, cpu_ms(k), omega_hist(k));
        end
    end

    r.name             = tc.name;
    r.cpu_ms           = cpu_ms;
    r.max_cpu_ms        = max(cpu_ms);
    r.n_overruns_100ms  = sum(cpu_ms > TS_BUDGET_MS);
    r.rmse_omega_rpm    = sqrt(mean((omega_hist - p.omega_r*30/pi).^2));
    results(end+1) = r; %#ok<AGROW>

    fprintf('  DONE: mean=%.1fms  max=%.1fms  overruns(>100ms)=%d/%d  RMSE=%.4f rpm\n', ...
        mean(cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, N_steps, r.rmse_omega_rpm);
end

fprintf('\n============================================================\n');
fprintf('  SUMMARY — SW-MLP / PINN-v2 predict() bypass re-test\n');
fprintf('============================================================\n');
fprintf('%-22s %10s %10s %14s %10s\n', ...
    'Controller', 'Mean(ms)', 'Max(ms)', 'Overruns(>Ts)', 'RMSE(rpm)');
for k = 1:numel(results)
    r = results(k);
    fprintf('%-22s %10.1f %10.1f %14d %10.4f\n', ...
        r.name, mean(r.cpu_ms), r.max_cpu_ms, r.n_overruns_100ms, r.rmse_omega_rpm);
end
fprintf('============================================================\n');

ts = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
if ~exist('results', 'dir'), mkdir('results'); end
outfile = sprintf('results/test_swmlp_pinn_manual_closed_loop_%s.mat', ts);
save(outfile, 'results', 'T_SIM', 'V_MEAN', 'WIND_SEED');
fprintf('\nResults saved to %s\n', outfile);

end


function verify_swmlp(mdl, mdl_manual)
seq_len = mdl.seq_len;
x_test = [12*pi/30, 5, 14, 5];
buf = repmat(x_test, seq_len, 1);
buf_n = (buf - mdl.xmu) ./ mdl.xsig;
feat = buf_n(:)';
X_dl = dlarray(feat', 'CB');
y_predict = extractdata(predict(mdl.net, X_dl))';
y_manual  = manual_forward_generic(feat, mdl_manual.manual_W, mdl_manual.manual_b, mdl_manual.manual_act);
d = max(abs(y_predict(:) - y_manual(:)));
fprintf('  max abs diff = %.2e  %s\n', d, ternary(d<1e-5,'VERIFIED','MISMATCH -- DO NOT TRUST MANUAL VERSION'));
end

function verify_pinn(mdl, mdl_manual)
feat  = [12*pi/30, 5, 14, 5];
featn = (feat - mdl.xmu) ./ mdl.xsig;
y_predict = extractdata(predict(mdl.net, dlarray(featn', 'CB')))';
y_manual  = manual_forward_generic(featn, mdl_manual.manual_W, mdl_manual.manual_b, mdl_manual.manual_act);
d = max(abs(y_predict(:) - y_manual(:)));
fprintf('  max abs diff = %.2e  %s\n', d, ternary(d<1e-5,'VERIFIED','MISMATCH -- DO NOT TRUST MANUAL VERSION'));
end

function s = ternary(cond, a, b)
if cond, s = a; else, s = b; end
end

function nlobj = build_controller(stateFcnName, nParams, p, cfg, Np, Nc, Ts, isBaseline)
nlobj = nlmpc(2, 2, 1);
nlobj.Model.StateFcn = stateFcnName;
nlobj.Model.NumberOfParameters = nParams;
nlobj.Ts                = Ts;
nlobj.PredictionHorizon = Np;
nlobj.ControlHorizon    = Nc;
nlobj.Weights.OutputVariables          = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
if isBaseline
    nlobj.OV(1).Min = p.omega_mpc_min_physics;
    nlobj.OV(1).Max = p.omega_max;
else
    nlobj.OV(1).Min = p.omega_mpc_min_surrogate;
    nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
end
nlobj.OV(2).Min = p.beta_cp_min;
nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min     = p.beta_cp_min;
nlobj.MV(1).Max     = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max * Ts;
nlobj.MV(1).RateMax =  p.dbeta_max * Ts;
nlobj.Optimization.SolverOptions.MaxIterations          = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;
end
