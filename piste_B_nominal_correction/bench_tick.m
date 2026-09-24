function out = bench_tick(budget)
%BENCH_TICK  Avance le benchmark A/B IsContinuousTime par tranches de temps.
%  Reprend exactement ou il s''etait arrete. Un timeout de passerelle ne
%  perd au pire que la tranche en cours.
if nargin < 1, budget = 40; end
T0 = tic;
addpath('common'); addpath('piste_B_nominal_correction');
if ~exist('results','dir'), mkdir('results'); end
cfg = stage0_config(); p = get_wt_params(); Ts = cfg.mpc.Ts; p.dt = Ts;
T_SIM = 60; V_MEAN = 14; SEED = 2025; N = round(T_SIM/Ts);
V_wind = kaimal_wind(V_MEAN, T_SIM, Ts, SEED);
Np = cfg.mpc2.Np; Nc = cfg.mpc2.Nc; oref = p.omega_r;
V2 = load('stage2_models_v2.mat');
evalc('mtcn = extract_tcn_weights(V2.mdl_tcn);');
evalc('mswm = extract_dlnetwork_generic(V2.mdl_swmlp, ''net'');');
evalc('mpin = extract_dlnetwork_generic(V2.mdl_pinn_v2, ''net'');');
kinds = {'baseline','llnfm','gp0','gp08','pinn','tcn','swmlp'};
cts = [0 1];
fres = fullfile('results','bench_dt.mat'); fst = fullfile('results','bench_state.mat');
if isfile(fres), RES = load(fres); else, RES = struct(); end
if isfile(fst), Q = load(fst); ST = Q.ST; else, ST = struct(); end
for ic = 1:numel(cts)
for ik = 1:numel(kinds)
  fld = sprintf('%s_ct%d', kinds{ik}, cts(ic));
  if isfield(RES, fld), continue; end
  kind = kinds{ik}; is_ct = logical(cts(ic));
  if ~isfield(ST, fld)
    s = struct(); s.k = 1; s.x = [p.omega_r*0.97; 3.5]; s.mv = 3.5;
    s.sb = repmat([s.x(1), s.x(2), V_wind(1), s.mv], 10, 1);
    s.oh = zeros(N,1); s.bh = zeros(N,1); s.ch = zeros(N,1);
    s.eh = zeros(N,1); s.uh = zeros(N,1); s.wall = 0;
    ST.(fld) = s;
  end
  s = ST.(fld);
  nlobj = build_ctrl_dt(kind, p, cfg, Np, Nc, is_ct);
  op = nlmpcmoveopt;
  t1 = tic;
  while s.k <= N && toc(T0) < budget
    k = s.k; Vk = V_wind(k);
    switch kind
      case 'baseline', op.Parameters = {Vk, p};
      case 'llnfm',    op.Parameters = {Vk, V2.mdl_llnfm};
      case 'gp0',      op.Parameters = {Vk, V2.mdl_gp_v2, oref, 0,   cfg.mpc.Q, 0.01, cfg.mpc.R};
      case 'gp08',     op.Parameters = {Vk, V2.mdl_gp_v2, oref, 0.8, cfg.mpc.Q, 0.01, cfg.mpc.R};
      case 'pinn',     op.Parameters = {Vk, mpin};
      case 'tcn',      mtcn.seq_buf = s.sb; op.Parameters = {Vk, mtcn};
      case 'swmlp',    mswm.seq_buf = s.sb; op.Parameters = {Vk, mswm};
    end
    t0s = tic;
    [mv, op, info] = nlmpcmove(nlobj, s.x, s.mv, [p.omega_r, 0], [], op);
    s.ch(k) = toc(t0s)*1000;
    mv = max(p.beta_cp_min, min(p.beta_cp_max, mv));
    s.mv = mv; s.eh(k) = info.ExitFlag; s.uh(k) = mv(1);
    s.sb = [s.sb(2:end,:); s.x(1), s.x(2), Vk, mv(1)];
    s.x = wt_step(s.x, mv(1), Vk, p, Ts);
    s.oh(k) = s.x(1)*30/pi; s.bh(k) = s.x(2);
    s.k = k + 1;
  end
  s.wall = s.wall + toc(t1);
  ST.(fld) = s; save(fst, 'ST');
  if s.k > N
    r = struct(); r.kind = kind; r.is_ct = is_ct; r.N = N;
    r.rmse_omega_rpm = sqrt(mean((s.oh - p.omega_r*30/pi).^2));
    r.pitch_activity_deg = sum(abs(diff(s.bh)));
    lam = p.R * (s.oh*pi/30) ./ V_wind(1:N);
    r.mean_cp = mean(arrayfun(@(l,b) cp_lambda_beta(l,b), lam, s.bh));
    r.mean_cpu_ms = mean(s.ch); r.n_infeasible = sum(s.eh < 0);
    r.n_exit1 = sum(s.eh == 1); r.n_exit2 = sum(s.eh == 2);
    r.max_omega_rpm = max(s.oh); r.min_omega_rpm = min(s.oh);
    r.omega_hist = s.oh; r.beta_hist = s.bh; r.u_hist = s.uh; r.exitflag = s.eh;
    r.wall_s = s.wall;
    r.dwdu = ctrl_grad_dt(kind, p, cfg, V2, mtcn, mswm, mpin, oref);
    RES.(fld) = r; save(fres, '-struct', 'RES');
    out = sprintf('[TERMINE] %s : RMSE=%.4f rpm  PA=%.2f  Cp=%.4f  infeas=%d/%d  exit1=%d  maxw=%.4f  dwdu=%.4e  (%.0fs)', ...
      fld, r.rmse_omega_rpm, r.pitch_activity_deg, r.mean_cp, r.n_infeasible, N, r.n_exit1, r.max_omega_rpm, r.dwdu, r.wall_s);
  else
    out = sprintf('[EN COURS] %s : %d/%d pas', fld, s.k-1, N);
  end
  disp(out); return;
end
end
out = 'TOUT TERMINE'; disp(out);
end
