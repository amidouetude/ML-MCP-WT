function r = remesure_arm(arch, mode, is_ct, n_steps)
%REMESURE_ARM  Un bras de la remesure predict() vs passage manuel.
%
%   r = remesure_arm(arch, mode, is_ct, n_steps)
%
%   arch    : 'mlpres' | 'gpres' | 'swmlp' | 'pinn' | 'tcn' | 'lstm'
%   mode    : 'predict' | 'manual'
%   is_ct   : valeur donnee a Model.IsContinuousTime (false = correct)
%   n_steps : nombre de pas de la boucle fermee
%
%   Reprend a l'identique le protocole des tests du 13/08/2026 (T=60 s,
%   V=14 m/s, graine 2025, memes horizons et memes bornes par
%   architecture) ; la SEULE difference est que IsContinuousTime est
%   desormais fixe explicitement au lieu d'etre laisse a son defaut.
addpath('common'); addpath('piste_B_nominal_correction');
cfg = stage0_config(); p = get_wt_params();
Ts = cfg.mpc.Ts; p.dt = Ts;
T_SIM = 60; V_MEAN = 14; WIND_SEED = 2025; TS_BUDGET_MS = 100;
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, WIND_SEED);
% -- horizon et bornes : identiques au script d'origine de chaque architecture --
if any(strcmp(arch, {'mlpres','gpres','lstm'}))
    Np = cfg.mpc.Np; Nc = cfg.mpc.Nc;
else
    Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc;
end
phys_bounds = any(strcmp(arch, {'mlpres','gpres'}));
% -- modele et fonction d'etat --
npar = 2; useseq = false; seqlen = 10;
switch arch
  case 'mlpres'
    S = load('stage2_residual_model.mat'); npar = 4;
    if strcmp(mode,'predict'), fcn = 'sf_residual';        mdl = S.mdl;
    else,                      fcn = 'sf_residual_manual'; mdl = extract_residual_weights(S.mdl); end
  case 'gpres'
    S = load('stage2_gp_residual_model.mat'); npar = 4;
    if strcmp(mode,'predict'), fcn = 'sf_gp_residual_predict'; mdl = S.mdl;
    else,                      fcn = 'sf_gp_residual_manual';  mdl = extract_gp_weights(S.mdl); end
  case 'swmlp'
    V2 = load('stage2_models_v2.mat'); useseq = true;
    if strcmp(mode,'predict'), fcn = 'sf_swmlp';        mdl = V2.mdl_swmlp;
    else,                      fcn = 'sf_swmlp_manual'; mdl = extract_dlnetwork_generic(V2.mdl_swmlp,'net'); end
  case 'pinn'
    V2 = load('stage2_models_v2.mat');
    if strcmp(mode,'predict'), fcn = 'sf_pinn';        mdl = V2.mdl_pinn_v2;
    else,                      fcn = 'sf_pinn_manual'; mdl = extract_dlnetwork_generic(V2.mdl_pinn_v2,'net'); end
  case 'tcn'
    V2 = load('stage2_models_v2.mat'); useseq = true;
    if strcmp(mode,'predict'), fcn = 'sf_tcn';        mdl = V2.mdl_tcn;
    else,                      fcn = 'sf_tcn_manual'; mdl = extract_tcn_weights(V2.mdl_tcn); end
  case 'lstm'
    V1 = load('stage2_models.mat'); npar = 3; seqlen = V1.mdl_lstm.seq_len;
    if strcmp(mode,'predict'), fcn = 'sf_lstm';        mdl = V1.mdl_lstm;
    else,                      fcn = 'sf_lstm_manual'; mdl = extract_lstm_weights(V1.mdl_lstm); end
  otherwise
    error('architecture inconnue : %s', arch);
end
% -- controleur --
nlobj = nlmpc(2, 2, 1);
nlobj.Model.IsContinuousTime = is_ct;
nlobj.Model.StateFcn = fcn;
nlobj.Model.NumberOfParameters = npar;
nlobj.Ts = Ts; nlobj.PredictionHorizon = Np; nlobj.ControlHorizon = Nc;
nlobj.Weights.OutputVariables = [cfg.mpc.Q, 0.01];
nlobj.Weights.ManipulatedVariablesRate = cfg.mpc.R;
if phys_bounds
    nlobj.OV(1).Min = p.omega_mpc_min_physics;   nlobj.OV(1).Max = p.omega_max;
else
    nlobj.OV(1).Min = p.omega_mpc_min_surrogate; nlobj.OV(1).Max = p.omega_mpc_max_surrogate;
end
nlobj.OV(2).Min = p.beta_cp_min; nlobj.OV(2).Max = p.beta_cp_max;
nlobj.MV(1).Min = p.beta_cp_min; nlobj.MV(1).Max = p.beta_cp_max;
nlobj.MV(1).RateMin = -p.dbeta_max * Ts; nlobj.MV(1).RateMax = p.dbeta_max * Ts;
nlobj.Optimization.SolverOptions.MaxIterations          = 30;
nlobj.Optimization.SolverOptions.MaxFunctionEvaluations = 300;
nlobj.Optimization.SolverOptions.ConstraintTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.OptimalityTolerance    = 1e-4;
nlobj.Optimization.SolverOptions.StepTolerance          = 1e-4;
% -- boucle fermee --
x = [p.omega_r*0.97; 3.5]; mv = x(2);
seq_buf = repmat([x(1), x(2), V_wind(1), mv], seqlen, 1);
cpu = zeros(n_steps,1); oh = zeros(n_steps,1); ef = zeros(n_steps,1);
op = nlmpcmoveopt;
for k = 1:n_steps
    Vk = V_wind(k);
    if useseq, mdl.seq_buf = seq_buf; end
    switch npar
      case 4, op.Parameters = {Vk, mdl, p, Ts};
      case 3, op.Parameters = {Vk, mdl, seq_buf};
      otherwise, op.Parameters = {Vk, mdl};
    end
    t0 = tic;
    [mv, op, info] = nlmpcmove(nlobj, x, mv, [p.omega_r, 0], [], op);
    cpu(k) = toc(t0)*1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    ef(k) = info.ExitFlag;
    seq_buf = [seq_buf(2:end,:); x(1), x(2), Vk, mv(1)];
    x = wt_step(x, mv(1), Vk, p, Ts);
    oh(k) = x(1)*30/pi;
end
r = struct();
r.arch = arch; r.mode = mode; r.is_ct = is_ct; r.n_steps = n_steps;
r.Np = Np; r.Nc = Nc; r.state_fcn = fcn;
r.mean_cpu_ms = mean(cpu); r.median_cpu_ms = median(cpu); r.max_cpu_ms = max(cpu);
r.n_overruns = sum(cpu > TS_BUDGET_MS);
r.rmse_omega_rpm = sqrt(mean((oh - p.omega_r*30/pi).^2));
r.n_infeasible = sum(ef < 0);
r.cpu_ms = cpu; r.omega_hist = oh; r.exitflag = ef;
end
