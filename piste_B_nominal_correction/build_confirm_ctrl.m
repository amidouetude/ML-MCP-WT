function nl = build_confirm_ctrl(ci, p, cfg)
%BUILD_CONFIRM_CTRL  Les trois cas de la campagne de confirmation.
%  ci=1 : GP pur, sans contrainte sur d_beta            (etat actuel)
%  ci=2 : GP + |d_beta| <= dbmax via CustomIneqConFcn   (remede A, formulation)
%  ci=3 : GP hybride, canal beta = actionneur physique  (remede B, temoin mecanistique)
Ts = cfg.mpc.Ts;
nl = nlmpc(2,2,1);
nl.Model.IsContinuousTime = false;
nl.Model.NumberOfParameters = 7;
if ci==3, nl.Model.StateFcn='sf_gp_hybrid'; else, nl.Model.StateFcn='sf_gp'; end
if ci==2, nl.Optimization.CustomIneqConFcn='con_dbeta'; end
nl.Ts=Ts; nl.PredictionHorizon=cfg.mpc2.Np; nl.ControlHorizon=cfg.mpc2.Nc;
nl.Weights.OutputVariables=[cfg.mpc.Q,0.01];
nl.Weights.ManipulatedVariablesRate=cfg.mpc.R;
nl.OV(1).Min=p.omega_mpc_min_surrogate; nl.OV(1).Max=p.omega_mpc_max_surrogate;
nl.OV(2).Min=p.beta_cp_min; nl.OV(2).Max=p.beta_cp_max;
nl.MV(1).Min=p.beta_cp_min; nl.MV(1).Max=p.beta_cp_max;
nl.MV(1).RateMin=-p.dbeta_max*Ts; nl.MV(1).RateMax=p.dbeta_max*Ts;
nl.Optimization.SolverOptions.Algorithm='sqp';
nl.Optimization.SolverOptions.ConstraintTolerance=1e-4;
nl.Optimization.SolverOptions.OptimalityTolerance=1e-4;
nl.Optimization.SolverOptions.StepTolerance=1e-4;
nl.Optimization.SolverOptions.MaxIterations=60;
nl.Optimization.SolverOptions.MaxFunctionEvaluations=2000;
end
