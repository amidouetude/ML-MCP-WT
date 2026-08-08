function xnext = sf_residual(x, u, V, mdl, p, dt)
% SF_RESIDUAL  State function for Nominal+Correction MPC (Piste B)
%
%   xnext = sf_residual(x, u, V, mdl, p, dt)
%
%   nlmpc calls: sf_residual(x, u, p1, p2, p3, p4)
%     p1 = V     wind speed [m/s]
%     p2 = mdl   trained residual model struct (stage2_train_residual)
%     p3 = p     turbine parameter struct (get_wt_params)
%     p4 = dt    sample time [s]
%
%   NumberOfParameters = 4
%
%   STRUCTURE (Aswani et al. 2013 — nominal + learned correction)
%     xnext = wt_step(x, u, V, p, dt)  +  correction_net(x, u, V)
%   The nominal model wt_step.m provides the bulk of the prediction
%   (with all of its own physical structure and constraints); the
%   learned correction only needs to capture the SMALL residual left
%   unmodeled by wt_step.m (see wt_step_true.m for what that residual
%   represents in this experiment). This keeps the network small
%   (see stage2_train_residual.m) and grounds the prediction in a
%   physically-structured baseline rather than a fully black-box model.

% ── Nominal prediction (the bulk of the state evolution) ────────────────────
x_nominal = wt_step(x, u, V, p, dt);

% ── Learned correction (small network, cheap to evaluate/differentiate) ────
feat  = [x(1), x(2), V, u(1)];
featn = (feat - mdl.xmu) ./ mdl.xsig;
corr_n = predict(mdl.net, featn);
correction = corr_n .* mdl.ysig + mdl.ymu;   % [1x2], denormalised residual

xnext = x_nominal + correction(:);

end
