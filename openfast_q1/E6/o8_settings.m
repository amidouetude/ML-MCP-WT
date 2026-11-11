function cfg = o8_settings()
%O8_SETTINGS  Settings of the O8 solver, the same for every NMPC arm of E6.
%
%   cfg = o8_settings()
%
%   Source: openfast_q1/E6/spec_E6_solver_O8.yaml (sha256 a772cf27...), keys cited per line.
%   cfg.Ts, Np, Nc        sample time (s), prediction horizon, number of blocked moves
%   cfg.y_ref             output reference [r_1; r_2] (rad/s), held over the horizon
%   cfg.wy, wu, ut, wdu   weights of cost.form (no ScaleFactor, cost.weights_scalefactor_equivalence)
%   cfg.u_min, u_max      pitch bounds (deg); cfg.rate_min, rate_max: pitch rate per interval (deg)
%   cfg.dv_jac            relative step of the forward-difference Jacobians (nlmpc rule)
%   cfg.options           fmincon options; cfg.ct its ConstraintTolerance (solver_failure rule)

cfg.Ts = 0.05;                                  % s, spec_E2 nmpc_interface.Ts; constraints.values (8 deg/s x Ts)
cfg.Np = 30;                                    % unknowns.blocking (Np = 30)
cfg.Nc = 5;                                     % spec.nc_note (Nc = 5, supervisor decision 20 of 02/11/2026)
omega_rated = 12.1*pi/30;                       % cost.reference: 1.2671090 rad/s
cfg.y_ref = [omega_rated; 97*omega_rated];      % cost.reference; r_2 has weight 0 (value as timing_E6_nlmpc.m l.82)
cfg.wy = [1/(0.02*omega_rated); 0];             % cost.weights (E6-12): [39.459903 s/rad, 0]
cfg.wu = 0;                                     % cost.weights (E6-12)
cfg.ut = 0;                                     % cost.mv_steps: target 0 when MVTarget is not given
cfg.u_min = 0.01;                               % constraints.values (amendment 1), deg
cfg.u_max = 29.99;                              % constraints.values (amendment 1), deg
cfg.rate_max = 8*cfg.Ts;                        % constraints.values: 0.4 deg per control interval
cfg.rate_min = -cfg.rate_max;                   % constraints.values: -0.4 deg per control interval
cfg.wdu = 1/cfg.rate_max;                       % cost.weights (E6-12): 1/0.4 = 2.5 deg^-1
cfg.dv_jac = 1e-6;                              % gradient.jacobians_per_arm.B_and_C5 option (a)
cfg.options = optimoptions('fmincon', ...       % solver.call, solver.fixed_options, solver.algorithm (a),
    'Algorithm', 'sqp', ...                     % solver.tolerances_and_limits (a): sqp defaults kept
    'SpecifyObjectiveGradient', true, ...
    'Display', 'none', ...
    'FunValCheck', 'on');                       % solver_failure.non_finite option (a)
cfg.ct = cfg.options.ConstraintTolerance;       % solver_failure.rule (ExitFlag 0 recorded as -2)
end
