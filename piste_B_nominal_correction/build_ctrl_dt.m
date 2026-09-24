function nlobj = build_ctrl_dt(kind, p, cfg, Np, Nc, is_ct)
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
