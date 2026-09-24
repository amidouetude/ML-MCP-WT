function nl = build_audit_ctrl(kind, F, p, cfg)
%BUILD_AUDIT_CTRL  Controleur pour l'audit de conditionnement du bras GP.
%  F : struct de facteurs .subopt .ctol .scale .algo .Np
addpath('common'); addpath('piste_B_nominal_correction');
Ts = cfg.mpc.Ts;
nl = nlmpc(2,2,1);
nl.Model.IsContinuousTime = false;
switch kind
  case 'gp0',     nl.Model.StateFcn='sf_gp';          nl.Model.NumberOfParameters=7;
  case 'persist', nl.Model.StateFcn='sf_persist';     nl.Model.NumberOfParameters=2;
  case 'pinn',    nl.Model.StateFcn='sf_pinn_manual'; nl.Model.NumberOfParameters=2;
  case 'linear',  nl.Model.StateFcn='sf_linear';      nl.Model.NumberOfParameters=2;
  otherwise, error('kind inconnu');
end
nl.Ts = Ts; nl.PredictionHorizon = F.Np; nl.ControlHorizon = min(cfg.mpc2.Nc, F.Np);
nl.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nl.Weights.ManipulatedVariablesRate = cfg.mpc.R;
nl.OV(1).Min=p.omega_mpc_min_surrogate; nl.OV(1).Max=p.omega_mpc_max_surrogate;
nl.OV(2).Min=p.beta_cp_min; nl.OV(2).Max=p.beta_cp_max;
nl.MV(1).Min=p.beta_cp_min; nl.MV(1).Max=p.beta_cp_max;
nl.MV(1).RateMin=-p.dbeta_max*Ts; nl.MV(1).RateMax=p.dbeta_max*Ts;
% -- FACTEUR 3 : mise a l'echelle des variables d'optimisation --
if F.scale
    sw = p.omega_mpc_max_surrogate - p.omega_mpc_min_surrogate;   % ~0.449 rad/s
    sb = p.beta_cp_max - p.beta_cp_min;                            % 25 deg
    nl.States(1).ScaleFactor = sw; nl.States(2).ScaleFactor = sb;
    nl.OV(1).ScaleFactor     = sw; nl.OV(2).ScaleFactor     = sb;
    nl.MV(1).ScaleFactor     = sb;
end
% -- FACTEUR 1 : accepter une solution sous-optimale au lieu de geler --
nl.Optimization.UseSuboptimalSolution = F.subopt;
% -- FACTEUR 4 : algorithme --
nl.Optimization.SolverOptions.Algorithm = F.algo;
% -- FACTEUR 2 : tolerance sur les contraintes --
nl.Optimization.SolverOptions.ConstraintTolerance = F.ctol;
nl.Optimization.SolverOptions.OptimalityTolerance = 1e-4;
nl.Optimization.SolverOptions.StepTolerance       = 1e-4;
nl.Optimization.SolverOptions.MaxIterations          = 60;
nl.Optimization.SolverOptions.MaxFunctionEvaluations = 2000;
end
