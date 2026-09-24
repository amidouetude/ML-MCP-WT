function g = ctrl_grad_dt(kind, p, cfg, V2, mtcn, mswm, mpin, oref)
%CTRL_GRAD_DT  Gradient de commande dw+/du au point nominal.
%  Verite physique sur un pas : exactement 0.
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
