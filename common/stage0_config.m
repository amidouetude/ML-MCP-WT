function cfg = stage0_config()
% STAGE0_CONFIG  Central configuration for ML-Enhanced MPC Wind Turbine project
%
%   cfg = stage0_config()
%
%   Single source of truth for all hyperparameters used across Stage 0-3.
%   Any change made here propagates automatically to all stages.
%
%   USAGE
%     cfg = stage0_config();
%     p   = cfg.turbine;      % turbine physical parameters
%     dc  = cfg.data;         % data generation settings
%     ml  = cfg.ml;           % ML training settings
%     mpc = cfg.mpc;          % MPC settings
%
%   REFERENCE
%     Jonkman et al. (2009)  NREL/TP-500-38060
%     Klein et al.   (2024)  RWTH Aachen / MathWorks

% =========================================================================
%  SECTION 1 — Turbine physical parameters (NREL 5-MW)
% =========================================================================
p.R          = 63;              % rotor radius [m]
p.B          = 3;               % number of blades [-]
p.rho        = 1.225;           % air density [kg/m3]
p.A_rotor    = pi * p.R^2;      % rotor swept area [m2]

% Drivetrain
p.J          = 38.76e6;         % total rotor inertia (LSS) [kg.m2]
p.Br         = 6215.5;          % drivetrain damping [N.m.s/rad]
p.N_gear     = 97;              % gearbox ratio [-]

% Pitch actuator
p.tau_beta   = 0.1;             % pitch actuator time constant [s]
p.beta_min   = 0.0;             % minimum pitch angle [deg]  — physical lower bound
%                                 NOTE: set to 0 (not -5) to stay within
%                                 Cp polynomial calibration domain [0, 25 deg]
p.beta_max   = 25.0;            % maximum pitch angle [deg]  — calibration upper bound
p.dbeta_max  = 8.0;             % maximum pitch rate [deg/s]

% Operating limits
p.omega_r    = 12.1 * pi/30;    % rated rotor speed [rad/s]  (12.1 rpm)
p.omega_min  = 0.5;             % minimum rotor speed [rad/s]  — PHYSICAL lower bound
%                                 used by wt_step.m plant model (ground truth)
p.omega_max  = 1.1 * 12.1*pi/30; % overspeed limit: +10% above rated [rad/s]

% MPC SAFETY BOUNDS — two distinct bounds for two distinct failure modes.
%
% 1) p.omega_mpc_min_physics — defense-in-depth for the Baseline controller.
%    SUPERSEDED as load-bearing constraint by the Region II/III torque
%    switching fix in wt_step.m (see p.K_opt above): with Tg=K_opt*omega^2
%    in Region II, the torque margin Ta_max(omega)-Tg(omega) stays positive
%    across the full sub-rated range, eliminating the irrecoverable trap
%    that existed with constant Tg. Retained as cheap defense-in-depth.
%    Baseline uses wt_step.m directly (no surrogate), so it is NOT
%    restricted by training-domain considerations.
p.omega_mpc_min_physics = 11.5 * pi/30; % [rad/s] = 11.5 rpm

% 2) p.omega_mpc_min_surrogate / p.omega_mpc_max_surrogate — REQUIRED bound
%    for the 4 surrogate controllers (LLNFM, LSTM, GP, PINN).
%    All 4 share the same Stage 1 global normalisation, so they share the
%    same training domain. Outside this domain, surrogate predictions are
%    extrapolations with no guarantee of accuracy.
%
%    UPDATED after widening Stage 1 coverage (stage1_generate_data.m):
%    initial omega now spans Region II (half of trajectories start in
%    [8.0, omega_rated] rpm) plus deliberate mid-trajectory wind dips
%    (every 3rd trajectory), specifically to cover the 7.55 rpm worst
%    case observed in the original Stage 3 LLNFM-MPC failure.
%    New training domain: omega in [8.02, 13.31] rpm (verified via
%    stage1_validate.m on the regenerated dataset).
%    Bound = training range with 0.5 rpm safety margin on each side.
p.omega_mpc_min_surrogate = (8.02 + 0.5) * pi/30;  % [rad/s] = 8.52 rpm
p.omega_mpc_max_surrogate = (13.31 - 0.5) * pi/30; % [rad/s] = 12.81 rpm
%   NOTE: re-run check_surrogate_domains.m if stage1_data.mat changes
%   (different seed, N_traj, or wind range) — these values are NOT
%   automatically derived from the .mat file to keep stage0_config.m
%   self-contained without a data dependency. Verify match before use.

p.P_rated_elec = 5e6;           % nameplate ELECTRICAL power [W]
p.eta_gen      = 0.944;         % generator efficiency [-] (NREL/TP-500-38060)
p.P_rated      = p.P_rated_elec / p.eta_gen;
%              = 5.2966e6 W mechanical
% [FIX -- item 3.1, adopted NREL reference definition per supervisor
%  decision]. Previously p.P_rated = 5e6 W was treated as MECHANICAL
%  power directly (Tg_rated then 5.6%% low vs. the NREL reference's
%  43,093.55 N.m). Now correctly derived from the 5 MW ELECTRICAL
%  nameplate rating via the documented 94.4%% generator efficiency.
p.V_rated    = 11.4;            % rated wind speed [m/s]
p.V_cutin    = 3.0;             % cut-in wind speed [m/s]
p.V_cutout   = 25.0;            % cut-out wind speed [m/s]

% Derived quantities
p.Tg_rated   = p.P_rated / (p.omega_r * p.N_gear);   % rated generator torque [N.m]

% Cp polynomial calibration domain (Jonkman 2009)
p.lambda_min = 2.0;             % minimum valid tip-speed ratio [-]
p.lambda_max = 13.0;            % maximum valid tip-speed ratio [-]
p.beta_cp_min = 0.0;            % minimum valid pitch for Cp [deg]
p.beta_cp_max = 25.0;           % maximum valid pitch for Cp [deg]

% Region II optimal-TSR torque law:  Tg_lss = K_opt * omega^2   (LSS torque directly)
%   K_opt = 0.5*rho*A*Cp(lambda_rated)*R^3 / lambda_rated^3
%
% UNITS NOTE: K_opt*omega^2 is derived from rotor aerodynamics and is
% therefore a LOW-SPEED-SHAFT (LSS) torque already — do NOT multiply by
% N_gear again in wt_step.m. This differs from Tg_rated, which is defined
% GENERATOR-side (HSS) and requires N_gear to convert to LSS for Region III.
%
% CALIBRATION POINT CHOICE — uses the actual Jonkman operating point
% (lambda_rated = R*omega_rated/V_rated = 7.00), NOT the theoretical
% Cp_max point (lambda_opt = 8.11 from Stage 0 surface scan).
%
% Rationale: Jonkman's omega_rated/V_rated already account for drivetrain
% and electrical losses (eta_gear~0.97, eta_gen~0.95), so the real rated
% operating point sits slightly off the pure-aerodynamic Cp peak.
% Calibrating K_opt at lambda_opt=8.11 gives K_opt*omega_r^2 / (N_gear*Tg_rated)
% = 0.70 (30% torque discontinuity at the Region II/III switch boundary, BOTH
% sides expressed in LSS torque).
% Calibrating at lambda_rated=7.00 (this implementation) gives ratio =
% 1.0215 (2.1% discontinuity) — consistent with standard practice
% (Bianchi et al. 2006; Pao & Johnson 2009): K_opt is now derived directly from the NREL reference definition
% [FIX -- item 3.2, adopted NREL reference definition per supervisor
%  decision], not from an aerodynamic-Cp-based self-calibration as
%  before. NREL/TP-500-38060's Region 2 generator-side control law is
%  Tg_HSS = K_gen * omega_gen_rpm^2, K_gen = 0.0255764 N.m/rpm^2
%  (standard, widely-cited NREL 5-MW constant). Converted to the
%  low-speed shaft, rad/s convention used throughout this codebase:
%  K_opt = N_gear^3 * K_gen * (30/pi)^2
p.lambda_rated_op = 7.00;       % R*omega_r/V_rated, Jonkman operating point [-]
                                 % (kept for documentation/reference only;
                                 %  no longer used to derive K_opt directly)
p.K_gen_ref = 0.0255764;        % NREL reference constant, generator side [N.m/rpm^2]
p.K_opt = (p.N_gear^3) * p.K_gen_ref * (30/pi)^2;
%        = 2.128616e+06 N.m.s^2  (NREL reference, verified independently
%          against the referee-stated ~2.13e6 figure)
% Continuity check (both sides LSS): K_opt*omega_r^2 / (N_gear*Tg_rated) = 1.0215
%
% RESIDUAL BOUNDARY DEFICIT (documented, accepted as negligible):
% check_omega_critical.m identifies a single-point torque deficit of
% -4.128e3 N.m exactly AT omega = omega_rated (lambda = 7.0024), which is
% the direct numerical trace of the 2.1% K_opt calibration discontinuity.
% Magnitude: 4128 / 3.946e6 = 0.105% of Tg_rated — negligible relative to
% numerical integration tolerance, and the system does not dwell exactly
% at omega_rated to machine precision in practice (Euler step + turbulent
% wind cause continuous small excursions on both sides). No further
% K_opt refinement performed; this residual is accepted as below the
% threshold of practical significance for closed-loop simulation.

cfg.turbine = p;

% =========================================================================
%  SECTION 2 — Data generation settings (Stage 1)
% =========================================================================
d.N_traj     = 80;              % number of simulation trajectories
d.T_traj     = 30;              % duration of each trajectory [s]
d.dt         = 0.1;             % simulation sample time [s]
d.N_steps    = round(d.T_traj / d.dt);   % steps per trajectory = 300

% Wind model (IEC 61400-1, Class B)
d.V_mean_min = p.V_rated;       % minimum mean wind speed [m/s]
d.V_mean_max = p.V_cutout - 1;  % maximum mean wind speed [m/s]
d.wind_seed_offset = 100;       % seed = traj_index * offset

% PRBS excitation
d.f_switch   = 0.5;             % PRBS maximum switching frequency [Hz]
d.delta_min  = 1.0;             % minimum PRBS amplitude [deg]
d.delta_max  = 3.0;             % maximum PRBS amplitude [deg]

% Low-pass filter on wind signal (align with Klein et al. 2024)
d.apply_lpf  = true;            % apply low-pass filter to V_traj
d.lpf_order  = 2;               % Butterworth filter order
d.lpf_cutoff = 0.3;             % cutoff frequency [Hz]
%                                 (removes high-freq turbulence above 0.1 Hz
%                                  that is not captured by the 2-state model)

% Train / val / test split by TRAJECTORIES (not by samples)
d.frac_train = 0.70;            % fraction for training   = 56 trajectories
d.frac_val   = 0.15;            % fraction for validation = 12 trajectories
d.frac_test  = 0.15;            % fraction for test       = 12 trajectories
d.split_seed = 42;              % random seed for trajectory shuffle

cfg.data = d;

% =========================================================================
%  SECTION 3 — ML training settings (Stage 2)
% =========================================================================
ml.global_norm = true;          % use a single global normalisation shared
%                                 across all models (computed on full train set)

% LLNFM / ANFIS
ml.llnfm.n_mf      = 2;        % membership functions per input
ml.llnfm.n_epochs  = 80;       % training epochs
ml.llnfm.n_sub     = 3000;     % subsample size for genfis (memory limit)

% LSTM
ml.lstm.seq_len    = 10;        % sequence window length [steps]
ml.lstm.n_epochs   = 60;        % training epochs
ml.lstm.hidden1    = 64;        % units in first LSTM layer
ml.lstm.hidden2    = 32;        % units in second LSTM layer
ml.lstm.dropout    = 0.1;       % dropout rate
ml.lstm.lr         = 1e-3;      % initial learning rate
ml.lstm.batch      = 64;        % mini-batch size

% GP
ml.gp.N_sub        = 400;       % subset size (O(N^3) constraint)
ml.gp.kernel       = 'squaredexponential';
ml.gp.optimize_hp  = false;     % false = fixed kernel (fast, MATLAB Online)

% PINN
ml.pinn.n_iter     = 3000;      % training iterations (plateau reached at 3000)
ml.pinn.lambda_phy = 0.10;      % physics loss weight — omega ODE only
%                                 beta residual excluded: with dt=tau_beta=0.1s,
%                                 ODE gives beta_next=u exactly, conflicting
%                                 with rate saturation in real data.
ml.pinn.batch      = 256;       % mini-batch size
ml.pinn.lr_init    = 1e-3;      % initial learning rate
ml.pinn.lr_decay   = 0.5;       % LR decay factor
ml.pinn.lr_step    = 400;       % decay every N iterations (less aggressive)

cfg.ml = ml;

% =========================================================================
%  SECTION 3b — V2 ML settings (TCN, SW-MLP, GP-v2, PINN-v2)
%  New models added in V2 — V1 models (Section 3) unchanged for comparison.
% =========================================================================

% TCN (Temporal Convolutional Network) — replaces LSTM
% Architecture: 3 conv1d blocks with exponential dilation (1,2,4)
% Receptive field = 1 + (kernel-1)*(1+2+4) = 15 > seq_len=10  (OK)
% Inference: dlarray direct (CTB format), NOT minibatchpredict
% Confirmed R2024a: 1.56ms/call vs LSTM 180.5ms/call (115x speedup)
ml2.tcn.seq_len   = 10;        % sequence window length [steps]
ml2.tcn.n_filters = 16;        % convolutional filters per block
ml2.tcn.kernel    = 3;         % kernel size
ml2.tcn.n_blocks  = 3;         % number of dilated conv blocks (dil=1,2,4)
ml2.tcn.dropout   = 0.1;       % dropout rate per block
ml2.tcn.n_epochs  = 60;        % training epochs
ml2.tcn.lr        = 1e-3;      % initial learning rate
ml2.tcn.batch     = 64;        % mini-batch size
ml2.tcn.lr_drop_factor = 0.5;  % LR decay factor
ml2.tcn.lr_drop_period = 20;   % decay every N epochs

% SW-MLP (Sliding Window MLP) — temporal baseline without recurrence
% Input: flattened window [seq_len * n_feat] = [40 x 1]
% Inference: dlarray direct (CB format), 1.34ms/call
% Captures temporal context without sequential dependency
ml2.swmlp.seq_len  = 10;       % sequence window length [steps]
ml2.swmlp.hidden1  = 64;       % units in first hidden layer
ml2.swmlp.hidden2  = 32;       % units in second hidden layer
ml2.swmlp.n_epochs = 60;       % training epochs
ml2.swmlp.lr       = 1e-3;     % initial learning rate
ml2.swmlp.batch    = 128;      % mini-batch size
ml2.swmlp.lr_drop_factor = 0.5;
ml2.swmlp.lr_drop_period = 20;

% GP-v2 — improved kernel and calibrated hyperparameters
% Kernel: Matern 5/2 (more appropriate for physical dynamics than SE)
% Hyperparameter optimisation: Bayesian optimisation via fitrgp
% Confirmed R2024a: ~15s for 100 pts / 20 evals — acceptable
ml2.gp.N_sub       = 400;      % subset size (O(N^3) constraint unchanged)
ml2.gp.kernel      = 'matern52';
ml2.gp.optimize_hp = true;     % V2: enable Bayesian HP optimisation
ml2.gp.max_evals   = 20;       % max Bayesian optimisation evaluations

% PINN-v2 — differentiable physics residual via softplus
% Replaces max(0, min(Betz, Cp)) with softplus approximation to preserve
% differentiability through the Cp clamp, enabling true gradient flow
% through the physics residual into the network parameters.
% softplus(x, beta) = (1/beta)*log(1 + exp(beta*x))  (smooth approximation of ReLU)
% With beta=20: matches max(0,x) to within 0.05 for |x| > 0.3
ml2.pinn.n_iter     = 3000;    % training iterations
ml2.pinn.lambda_phy = 0.10;    % physics loss weight
ml2.pinn.batch      = 256;     % mini-batch size
ml2.pinn.lr_init    = 1e-3;    % initial learning rate
ml2.pinn.lr_decay   = 0.5;     % LR decay factor
ml2.pinn.lr_step    = 400;     % decay every N iterations
ml2.pinn.softplus_beta = 20;   % softplus sharpness (higher = closer to hard clamp)

cfg.ml2 = ml2;

% =========================================================================
%  SECTION 4 — MPC settings V1 (Stage 3 — unchanged)
% =========================================================================
mpc.Np    = 10;                 % prediction horizon [steps]
mpc.Nc    = 4;                  % control horizon [steps]
mpc.Ts    = 0.1;                % sample time [s]
mpc.Q     = 100;                % speed tracking weight (omega error)
mpc.R     = 0.5;                % control rate weight (delta_beta)
mpc.kappa = 0.8;                % GP uncertainty penalty weight

% Simulation
mpc.T_sim     = 120;            % closed-loop simulation duration [s]
mpc.V_sim     = 14;             % mean wind speed for simulation [m/s]
mpc.wind_seed = 2025;           % wind seed (same for all controllers)

cfg.mpc = mpc;

% =========================================================================
%  SECTION 4b — MPC settings V2
%  Extended horizon + warm-starting + multi-wind evaluation
% =========================================================================
mpc2.Np    = 15;                % prediction horizon [steps] = 2s
%                                 V1 used Np=10 (1s) — too short for rotor
%                                 inertia dynamics (observed drift over 10-30s)
mpc2.Nc    = 4;                 % control horizon [steps] -- unified with V1 (item 2.5)
mpc2.Ts    = 0.1;               % sample time [s] — unchanged
mpc2.Q     = 100;               % speed tracking weight
mpc2.R     = 0.5;               % control rate weight
mpc2.kappa = 0.8;               % GP uncertainty penalty weight

% V2 evaluation: multiple wind conditions for robustness
mpc2.T_sim      = 120;          % simulation duration [s]
mpc2.V_sim_list = 14; % mean wind speeds [m/s] to test
mpc2.seeds      = [2025, 2026, 2027]; % 10 seeds for Monte Carlo

cfg.mpc2 = mpc2;

% =========================================================================
%  SECTION 5 — Export settings
% =========================================================================
cfg.export.fmt = '-dpng';
cfg.export.res = '-r150';
cfg.export.save_mat = true;

end