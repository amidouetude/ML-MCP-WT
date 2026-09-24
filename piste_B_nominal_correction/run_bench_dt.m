function r = run_bench_dt(kind, is_ct)
%RUN_BENCH_DT  Un bras du benchmark six surrogates, ablation A/B sur
%  Model.IsContinuousTime. Protocole identique a run_item25_unified_protocol.
%  Ne modifie aucun fichier d''origine du projet.
addpath('common'); addpath('piste_B_nominal_correction');
cfg = stage0_config(); p = get_wt_params(); Ts = cfg.mpc.Ts; p.dt = Ts;
T_SIM = 60; V_MEAN = 14; SEED = 2025; N = round(T_SIM/Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, SEED);
Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc; oref = p.omega_r;
V2 = load('stage2_models_v2.mat');
mtcn = extract_tcn_weights(V2.mdl_tcn);
mswm = extract_dlnetwork_generic(V2.mdl_swmlp, 'net');
mpin = extract_dlnetwork_generic(V2.mdl_pinn_v2, 'net');
nlobj = build_ctrl(kind, p, cfg, Np, Nc, is_ct);
x = [p.omega_r*0.97; 3.5]; mv = x(2);
oh = zeros(N,1); bh = zeros(N,1); ch = zeros(N,1); eh = zeros(N,1); uh = zeros(N,1);
sb = repmat([x(1), x(2), V_wind(1), mv], 10, 1);
op = nlmpcmoveopt;
for k = 1:N
  Vk = V_wind(k);
  switch kind
    case 'baseline', op.Parameters = {Vk, p};
    case 'llnfm',    op.Parameters = {Vk, V2.mdl_llnfm};
    case 'gp0',      op.Parameters = {Vk, V2.mdl_gp_v2, oref, 0,   cfg.mpc.Q, 0.01, cfg.mpc.R};
    case 'gp08',     op.Parameters = {Vk, V2.mdl_gp_v2, oref, 0.8, cfg.mpc.Q, 0.01, cfg.mpc.R};
    case 'pinn',     op.Parameters = {Vk, mpin};
    case 'tcn',      mtcn.seq_buf = sb; op.Parameters = {Vk, mtcn};
    case 'swmlp',    mswm.seq_buf = sb; op.Parameters = {Vk, mswm};
  end
  t0 = tic;
  [mv, op, info] = nlmpcmove(nlobj, x, mv, [p.omega_r,0], [], op);
  ch(k) = toc(t0)*1000;
  mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
  eh(k) = info.ExitFlag; uh(k) = mv(1);
  sb = [sb(2:end,:); x(1), x(2), Vk, mv(1)];
  x = wt_step(x, mv(1), Vk, p, Ts);
  oh(k) = x(1)*30/pi; bh(k) = x(2);
end
r.kind = kind; r.is_ct = is_ct; r.N = N;
r.rmse_omega_rpm = sqrt(mean((oh - p.omega_r*30/pi).^2));
r.pitch_activity_deg = sum(abs(diff(bh)));
lam = p.R * (oh*pi/30) ./ V_wind(1:N);
r.mean_cp = mean(arrayfun(@(l,b) cp_lambda_beta(l,b), lam, bh));
r.mean_cpu_ms = mean(ch); r.n_infeasible = sum(eh < 0);
r.n_exit1 = sum(eh == 1); r.n_exit2 = sum(eh == 2);
r.max_omega_rpm = max(oh); r.min_omega_rpm = min(oh);
r.omega_hist = oh; r.beta_hist = bh; r.u_hist = uh; r.exitflag = eh;
r.dwdu = ctrl_gradient(kind, p, cfg, V2, mtcn, mswm, mpin, oref);
end
function g = ctrl_gradient(kind, p, cfg, V2, mtcn, mswm, mpin, oref)
x0 = [p.omega_r; 3.5]; V = 14; u0 = 3.5; h = 1e-4;
sb = repmat([x0(1), x0(2), V, u0], 10, 1);
switch kind
  case 'baseline', f = @(u) sf_baseline(x0, u, V, p);
  case 'llnfm',    f = @(u) sf_llnfm(x0, u, V, V2.mdl_llnfm);
  case {'gp0','gp08'}, f = @(u) sf_gp(x0, u, V, V2.mdl_gp_v2, oref, 0, cfg.mpc.Q, 0.01, cfg.mpc.R);
  case 'pinn',     f = @(u) sf_pinn_manual(x0, u, V, mpin);
  case 'tcn',      mtcn.seq_buf = sb; f = @(u) sf_tcn_manual(x0, u, V, mtcn);
  case 'swmlp',    mswm.seq_buf = sb; f = @(u) sf_swmlp_manual(x0, u, V, mswm);
end
fp = f(u0 + h); fm = f(u0 - h);
g = (fp(1) - fm(1)) / (2*h);
end
function nlobj = build_ctrl(kind, p, cfg, Np, Nc, is_ct)
nlobj = nlmpc(2, 2, 1);
nlobj.Model.IsContinuousTime = is_ct;
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
nlobj.Optimization.SolverOptions.MaxIterations = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
end
