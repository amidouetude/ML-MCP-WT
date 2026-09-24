function r = multiseed_arm(kind, seed)
%MULTISEED_ARM  Un bras de boucle fermee, IsContinuousTime = false,
%  tolerances du solveur fixees explicitement.
addpath('common'); addpath('piste_B_nominal_correction');
cfg = stage0_config(); p = get_wt_params(); Ts = cfg.mpc.Ts; p.dt = Ts;
T_SIM = 60; V_MEAN = 14; N = round(T_SIM/Ts); TS_BUDGET_MS = 100;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, seed);
Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc; oref = p.omega_r;
V2 = load('stage2_models_v2.mat');
useseq = false; npar = 2; mdl = [];
switch kind
  case 'baseline', fcn = 'sf_baseline'; mdl = p;
  case 'persist',  fcn = 'sf_persist';  mdl = struct();
  case 'linear',   fcn = 'sf_linear';   mdl = V2.mdl_linear;
  case 'llnfm',    fcn = 'sf_llnfm';    mdl = V2.mdl_llnfm;
  case 'swmlp',    fcn = 'sf_swmlp_manual'; [~] = evalc('mdl = extract_dlnetwork_generic(V2.mdl_swmlp, ''net'');'); useseq = true;
  case 'pinn',     fcn = 'sf_pinn_manual';  [~] = evalc('mdl = extract_dlnetwork_generic(V2.mdl_pinn_v2, ''net'');');
  case 'tcn',      fcn = 'sf_tcn_manual';   [~] = evalc('mdl = extract_tcn_weights(V2.mdl_tcn);'); useseq = true;
  case 'gp0',      fcn = 'sf_gp'; mdl = V2.mdl_gp_v2; npar = 7;
  otherwise, error('kind inconnu : %s', kind);
end
nlobj = nlmpc(2,2,1);
nlobj.Model.IsContinuousTime = false;
nlobj.Model.StateFcn = fcn; nlobj.Model.NumberOfParameters = npar;
if strcmp(kind,'gp0')
    nlobj.Optimization.CustomCostFcn = 'cost_gp';
    nlobj.Optimization.ReplaceStandardCost = true;
end
nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
if strcmp(kind,'baseline')
    nlobj.OV(1).Min = p.omega_mpc_min_physics;   nlobj.OV(1).Max = p.omega_max;
else
    nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
end
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max*Ts; nlobj.MV(1).RateMax = p.dbeta_max*Ts;
nlobj.Optimization.SolverOptions.MaxIterations          = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;
x = [p.omega_r*0.97; 3.5]; mv = x(2);
sb = repmat([x(1), x(2), V_wind(1), mv], 10, 1);
oh = zeros(N,1); bh = zeros(N,1); ch = zeros(N,1); eh = zeros(N,1);
op = nlmpcmoveopt;
for k = 1:N
    Vk = V_wind(k);
    if useseq, mdl.seq_buf = sb; end
    if npar == 7
        op.Parameters = {Vk, mdl, oref, 0, cfg.mpc.Q, 0.01, cfg.mpc.R};
    else
        op.Parameters = {Vk, mdl};
    end
    t0 = tic;
    [mv, op, info] = nlmpcmove(nlobj, x, mv, [p.omega_r, 0], [], op);
    ch(k) = toc(t0)*1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    eh(k) = info.ExitFlag;
    sb = [sb(2:end,:); x(1), x(2), Vk, mv(1)];
    x = wt_step(x, mv(1), Vk, p, Ts);
    oh(k) = x(1)*30/pi; bh(k) = x(2);
end
r = struct('kind',kind,'N',N,'rmse_omega_rpm',sqrt(mean((oh - p.omega_r*30/pi).^2)), ...
    'pitch_activity_deg',sum(abs(diff(bh))),'n_infeasible',sum(eh<0), ...
    'mean_cpu_ms',mean(ch),'median_cpu_ms',median(ch),'max_cpu_ms',max(ch), ...
    'n_overruns',sum(ch>TS_BUDGET_MS),'max_omega_rpm',max(oh),'min_omega_rpm',min(oh));
lam = p.R * (oh*pi/30) ./ V_wind(1:N);
r.mean_cp = mean(arrayfun(@(l,b) cp_lambda_beta(l,b), lam, bh));
r.omega_hist = oh; r.beta_hist = bh; r.exitflag = eh; r.cpu_ms = ch;
end
