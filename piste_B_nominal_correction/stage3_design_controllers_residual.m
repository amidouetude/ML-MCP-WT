function nlobj = stage3_design_controllers_residual(p, mdl_residual, cfg)
% STAGE3_DESIGN_CONTROLLERS_RESIDUAL  Create the Nominal+Correction
% nlmpc controller for Piste B.
%
%   nlobj = stage3_design_controllers_residual(p, mdl_residual, cfg)
%
%   Uses the same V1 horizon settings (Np=10, Nc=4, Ts=0.1) as the
%   original Baseline/LLNFM/GP/PINN controllers for direct
%   comparability, and the same solver options (MaxIterations=30,
%   bounded worst-case computation time).
%
%   OMEGA BOUND
%     Since sf_residual wraps the full-domain nominal model wt_step.m
%     (not a surrogate trained on a restricted domain), the physics-
%     based Baseline bound (p.omega_mpc_min_physics) is used rather
%     than the narrower surrogate training-domain bound -- the learned
%     correction is a small additive term on top of a globally-valid
%     nominal model, not a domain-restricted black-box replacement.

nx = 2; ny = 2; nu = 1;
Np = cfg.mpc.Np;
Nc = cfg.mpc.Nc;
Ts = cfg.mpc.Ts;
Q  = cfg.mpc.Q;
R  = cfg.mpc.R;

fprintf('  Designing Nominal+Correction MPC (Np=%d, Nc=%d, Ts=%.2f)...\n', ...
    Np, Nc, Ts);

nlobj = nlmpc(nx, ny, nu);
nlobj.Model.StateFcn = 'sf_residual';
nlobj.Model.NumberOfParameters = 4;   % V, mdl_residual, p, dt

nlobj.Ts                = Ts;
nlobj.PredictionHorizon = Np;
nlobj.ControlHorizon    = Nc;

nlobj.Weights.OutputVariables          = [Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = R;

nlobj.OV(1).Min = p.omega_mpc_min_physics;
nlobj.OV(1).Max = p.omega_max;
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

fprintf('  Nominal+Correction controller designed.\n');

end
