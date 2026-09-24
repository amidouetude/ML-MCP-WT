function [data] = stage1_generate_data_exc(cfg)
% STAGE1_GENERATE_DATA  Generate ML training dataset for wind turbine surrogates
%
%   data = stage1_generate_data(cfg)
%   data = stage1_generate_data()        % uses stage0_config() defaults
%
%   Simulates N_traj independent trajectories of the NREL 5-MW turbine
%   under Kaimal turbulent wind with PRBS pitch excitation.
%   Each trajectory uses a different mean wind speed drawn from
%   [V_rated, V_cutout-1] to cover the full above-rated operating space.
%
%   OPERATING SPACE COVERAGE — Region II included
%     Initial omega is now drawn from a WIDE range spanning both Region II
%     (sub-rated, omega < omega_rated) and Region III (omega near/above
%     rated), instead of always starting near omega_rated. This is
%     required for surrogate models to learn the Region II torque
%     behavior (Tg = K_opt*omega^2 in wt_step.m) and generalise correctly
%     when closed-loop MPC simulations cause transient excursions below
%     rated speed — observed failure mode without this: LLNFM-MPC pushed
%     omega to 7.55 rpm, far outside the old training domain of
%     [10.28, 13.31] rpm, causing the surrogate to extrapolate and the
%     MPC to saturate pitch at 25 deg without recovering.
%     New target coverage: omega in [8.0, 13.31] rpm approximately
%     (exact range depends on PRBS excitation and wind realisation).
%
%   DATASET STRUCTURE
%     Features  X : [omega_r, beta, V_wind, u_cmd]   (4 inputs)
%     Targets   Y : [omega_next, beta_next]           (2 outputs)
%     One row per simulation step (one-step-ahead prediction format).
%
%   SPLIT STRATEGY
%     Split is performed by TRAJECTORIES, not by individual samples.
%     This preserves temporal coherence for LSTM sequence building and
%     ensures test trajectories correspond to unseen wind conditions.
%     Trajectory indices are shuffled before splitting (seed = cfg.data.split_seed).
%
%   LOW-PASS FILTER
%     A 2nd-order Butterworth filter at f_c = 0.3 Hz is applied to V_traj
%     before simulation. This removes turbulence components above the
%     effective bandwidth of the 2-state rotor model (Klein et al. 2024).
%     Filter is applied via zero-phase filtfilt to avoid phase distortion
%     that would create temporal misalignment between features and targets.
%
%   NORMALISATION
%     Global normalisation statistics (xmu, xsig, ymu, ysig) are computed
%     on the TRAINING SET only and saved alongside the data.
%     All ML models in Stage 2 must use these shared statistics to ensure
%     a fair comparison.
%
%   OUTPUT FIELDS (data struct)
%     X_in       [N_total x 4]  raw input features
%     X_out      [N_total x 2]  raw output targets
%     traj_id    [N_total x 1]  trajectory index per row  (critical for LSTM)
%     idx_train  [N_tr x 1]     row indices — training set
%     idx_val    [N_val x 1]    row indices — validation set
%     idx_test   [N_te x 1]     row indices — test set
%     norm       struct: xmu, xsig, ymu, ysig  (train set only)
%     info       struct: statistics, coverage, split details
%     p          turbine parameter struct
%     cfg        configuration struct used for this run
%
%   REFERENCE
%     Jonkman et al. (2009). NREL/TP-500-38060.
%     Klein et al.   (2024). MathWorks / RWTH Aachen.
%     IEC 61400-1 Ed.3 (2005).

if nargin < 1 || isempty(cfg)
    cfg = stage0_config();
end

p       = get_wt_params();
dc      = cfg.data;
N_traj  = dc.N_traj;
T_traj  = dc.T_traj;
dt      = dc.dt;
N_steps = dc.N_steps;

fprintf('==========================================\n');
fprintf('  STAGE 1: Training Data Generation\n');
fprintf('  NREL 5-MW | %d traj x %d steps = %d samples\n', ...
        N_traj, N_steps, N_traj*N_steps);
fprintf('==========================================\n\n');

% ── Low-pass filter design ────────────────────────────────────────────────────
if dc.apply_lpf
    Wn  = dc.lpf_cutoff / (0.5/dt);
    [b_lpf, a_lpf] = butter(dc.lpf_order, Wn, 'low');
    fprintf('Low-pass filter: Butterworth order %d, fc = %.2f Hz\n\n', ...
            dc.lpf_order, dc.lpf_cutoff);
end

% ── Wind speed grid across above-rated operating range ───────────────────────
V_grid = linspace(dc.V_mean_min, dc.V_mean_max, N_traj);

% ── Pre-allocate ──────────────────────────────────────────────────────────────
N_total = N_traj * N_steps;
X_in    = zeros(N_total, 4);
X_out   = zeros(N_total, 2);
traj_id = zeros(N_total, 1);

fprintf('Generating trajectories...\n');
row = 1;

for k = 1:N_traj

    % Mean wind speed with small random perturbation
    rng(k * dc.wind_seed_offset + 1);
    V_mean = V_grid(k) + 0.3 * randn();
    V_mean = max(dc.V_mean_min, min(dc.V_mean_max, V_mean));

    % Kaimal wind time series
    V_traj = kaimal_wind(V_mean, T_traj, dt, k * dc.wind_seed_offset);

    % Deliberate wind dip — every 3rd trajectory gets an additional deep
    % transient dip (beyond natural Kaimal turbulence) to expose the
    % surrogate to realistic Region II entry/exit dynamics mid-trajectory,
    % not just at initialisation. Dip depth/duration chosen to plausibly
    % drive omega toward Region II without being non-physical.
    if mod(k, 3) == 0
        dip_center = T_traj * (0.3 + 0.4*rand());   % dip somewhere in [0.3,0.7]*T
        dip_width  = 3.0 + 2.0*rand();              % [3,5] s half-width
        dip_depth  = 3.0 + 2.0*rand();              % [3,5] m/s depth
        t_vec      = (0:N_steps-1)' * dt;
        dip_profile = dip_depth * exp(-((t_vec - dip_center)/dip_width).^2);
        V_traj = V_traj - dip_profile;
        V_traj = max(3.0, V_traj);   % re-clamp to cut-in floor
    end

    % Low-pass filter: zero-phase to avoid feature-target time shift
    if dc.apply_lpf
        V_traj = filtfilt(b_lpf, a_lpf, V_traj);
        V_traj = max(3.0, min(25.0, V_traj));
    end

    % Operating-point pitch: linear law calibrated for NREL 5-MW Region III
    % beta_op = k_pitch * (V_mean - V_rated),  k_pitch = 2 deg/(m/s)
    rng(k * dc.wind_seed_offset + 7);
    beta_op = p.beta_cp_min + (p.beta_cp_max - p.beta_cp_min) * rand();

    % PRBS excitation amplitude: grows with beta_op, bounded by config
    delta  = max(dc.delta_min, min(dc.delta_max, 0.5*beta_op + 1.0));
    u_traj = prbs_signal(beta_op, delta, T_traj, dt, dc.f_switch, k);

    % Initial state — WIDE omega coverage spanning Region II and III.
    % Half the trajectories start near rated (as before); the other half
    % start deliberately LOW (Region II), so the dataset contains both
    % steady-state-near-rated dynamics AND sub-rated recovery dynamics.
    % This is what allows surrogates to learn Tg=K_opt*omega^2 behavior.
    rng(k * dc.wind_seed_offset + 2);
    if mod(k, 2) == 0
        % Even trajectories: start near rated (Region III), as before
        omega0 = p.omega_r * (0.97 + 0.06 * rand());
    else
        % Odd trajectories: start LOW in Region II, covering down to
        % ~8 rpm (below the 7.55 rpm worst case observed in Stage 3,
        % with margin), up to just below rated.
        omega0_rpm = 8.0 + (p.omega_r*30/pi - 8.0) * rand();
        omega0     = omega0_rpm * pi/30;
    end
    beta0  = max(p.beta_cp_min, min(p.beta_cp_max, beta_op + 0.5*randn()));
    x      = [omega0; beta0];

    % Simulate trajectory
    for t_idx = 1:N_steps
        V  = V_traj(t_idx);
        u  = u_traj(t_idx);
        xn = wt_step(x, u, V, p, dt);

        X_in(row, :)  = [x(1), x(2), V, u];
        X_out(row, :) = [xn(1), xn(2)];
        traj_id(row)  = k;

        x   = xn;
        row = row + 1;
    end

    if mod(k, 20) == 0
        fprintf('  Trajectory %3d / %d  |  V_mean = %.1f m/s  beta_op = %.1f deg\n', ...
                k, N_traj, V_mean, beta_op);
    end
end

fprintf('\nAll %d trajectories complete.\n\n', N_traj);

% ── Train / val / test split BY TRAJECTORIES ─────────────────────────────────
rng(dc.split_seed);
traj_perm = randperm(N_traj);

n_tr  = floor(dc.frac_train * N_traj);    % 56 trajectories
n_val = floor(dc.frac_val   * N_traj);    % 12 trajectories
% remaining = 12 trajectories for test

traj_tr  = sort(traj_perm(1              : n_tr));
traj_val = sort(traj_perm(n_tr+1         : n_tr+n_val));
traj_te  = sort(traj_perm(n_tr+n_val+1   : end));

idx_train = find(ismember(traj_id, traj_tr));
idx_val   = find(ismember(traj_id, traj_val));
idx_test  = find(ismember(traj_id, traj_te));

fprintf('Split by trajectories (seed = %d):\n', dc.split_seed);
fprintf('  Train : %2d traj  →  %5d samples (%.0f%%)\n', ...
        n_tr,           numel(idx_train), 100*numel(idx_train)/N_total);
fprintf('  Val   : %2d traj  →  %5d samples (%.0f%%)\n', ...
        n_val,          numel(idx_val),   100*numel(idx_val)/N_total);
fprintf('  Test  : %2d traj  →  %5d samples (%.0f%%)\n\n', ...
        numel(traj_te), numel(idx_test),  100*numel(idx_test)/N_total);

% ── Global normalisation — train set only ─────────────────────────────────────
X_tr = X_in(idx_train, :);
Y_tr = X_out(idx_train, :);

norm.xmu  = mean(X_tr);
norm.xsig = std(X_tr)  + 1e-8;
norm.ymu  = mean(Y_tr);
norm.ysig = std(Y_tr)  + 1e-8;

fprintf('Global normalisation (train set only — shared by all Stage 2 models):\n');
fprintf('  xmu  = [%.4f  %.4f  %.4f  %.4f]\n', norm.xmu);
fprintf('  xsig = [%.4f  %.4f  %.4f  %.4f]\n', norm.xsig);
fprintf('  ymu  = [%.4f  %.4f]\n',              norm.ymu);
fprintf('  ysig = [%.4f  %.4f]\n\n',            norm.ysig);

% ── Physical sanity check — Cp bounds ─────────────────────────────────────────
Cp_max_data = 0;
for i = 1:min(N_total, 5000)    % check on subset for speed
    lam = p.R * X_in(i,1) / max(X_in(i,3), 0.5);
    Cp_max_data = max(Cp_max_data, cp_lambda_beta(lam, X_in(i,2)));
end

% ── Info struct ───────────────────────────────────────────────────────────────
info.N_total     = N_total;
info.N_traj      = N_traj;
info.N_steps     = N_steps;
info.T_traj      = T_traj;
info.dt          = dt;
info.n_tr        = n_tr;
info.n_val       = n_val;
info.n_te        = numel(traj_te);
info.traj_tr     = traj_tr;
info.traj_val    = traj_val;
info.traj_te     = traj_te;
info.omega_range = [min(X_in(:,1)), max(X_in(:,1))] * 30/pi;
info.beta_range  = [min(X_in(:,2)), max(X_in(:,2))];
info.V_range     = [min(X_in(:,3)), max(X_in(:,3))];
info.u_range     = [min(X_in(:,4)), max(X_in(:,4))];
info.Cp_max_data = Cp_max_data;

fprintf('Operating space coverage:\n');
fprintf('  omega : %.2f – %.2f rpm\n',   info.omega_range);
fprintf('  beta  : %.2f – %.2f deg\n',   info.beta_range);
fprintf('  V     : %.2f – %.2f m/s\n',   info.V_range);
fprintf('  u_cmd : %.2f – %.2f deg\n',   info.u_range);
fprintf('  Cp_max (sample): %.4f  (Betz = %.4f)\n\n', Cp_max_data, 16/27);

% ── Package and save ──────────────────────────────────────────────────────────
data.X_in      = X_in;
data.X_out     = X_out;
data.traj_id   = traj_id;
data.idx_train = idx_train;
data.idx_val   = idx_val;
data.idx_test  = idx_test;
data.norm      = norm;
data.info      = info;
data.p         = p;
data.cfg       = cfg;

if cfg.export.save_mat
    % [desactive dans la variante _exc : le jeu est sauvegarde par l'appelant]
    fprintf('Saved → stage1_data.mat\n\n');
end

%% ── Write results/stage1_generate_data_results.txt [ADDED] ──────────────────
if ~exist('results', 'dir'), mkdir('results'); end
fid = fopen(fullfile('results','stage1_generate_data_results.txt'), 'w');
fprintf(fid, 'STAGE 1 DATA GENERATION RESULTS\n');
fprintf(fid, 'Generated: %s\n', datestr(now));
fprintf(fid, '================================================\n\n');
fprintf(fid, 'total_samples = %d\n', N_total);
fprintf(fid, 'n_traj = %d\n', N_traj);
fprintf(fid, 'n_steps = %d\n', N_steps);
fprintf(fid, 'train_samples = %d\n', numel(idx_train));
fprintf(fid, 'val_samples = %d\n', numel(idx_val));
fprintf(fid, 'test_samples = %d\n', numel(idx_test));
fprintf(fid, 'split_seed = %d\n', dc.split_seed);
fprintf(fid, 'omega_range_rpm = [%.4f, %.4f]\n', info.omega_range);
fprintf(fid, 'beta_range_deg = [%.4f, %.4f]\n', info.beta_range);
fprintf(fid, 'V_range_ms = [%.4f, %.4f]\n', info.V_range);
fprintf(fid, 'Cp_max_data = %.6f\n', info.Cp_max_data);
fprintf(fid, 'Tg_rated_used = %.4f\n', p.Tg_rated);
fprintf(fid, 'K_opt_used = %.6e\n', p.K_opt);
fclose(fid);
fprintf('Wrote results/stage1_generate_data_results.txt\n\n');

end