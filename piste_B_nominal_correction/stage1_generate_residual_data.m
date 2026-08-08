function data = stage1_generate_residual_data()
% STAGE1_GENERATE_RESIDUAL_DATA  Generate the residual-learning dataset
% for Piste B: for each (x, u, V) sample, compute both the nominal
% model's one-step prediction (wt_step.m) and the "true" plant's
% one-step prediction (wt_step_true.m), and save the residual
% (true - nominal) as the training target.
%
%   data = stage1_generate_residual_data()
%
%   PROTOCOL
%     Follows the same simulation protocol as the original Stage 1
%     (stage1_generate_data.m): PRBS pitch excitation + Kaimal
%     turbulent wind, trajectory-based train/val/test split. Reduced
%     to 40 trajectories (vs. 80 in the original Stage 1) since the
%     residual-learning task is smoother/simpler than the full
%     nonlinear dynamics learned by the V1/V2 surrogates.
%
%   OUTPUT  data struct with fields:
%     X_in           [N x 4]  [omega, beta, V, u_cmd] at each step
%     Y_residual     [N x 2]  [d_omega, d_beta] = true_next - nominal_next
%     Y_nominal      [N x 2]  nominal model's prediction (for reference)
%     Y_true         [N x 2]  true plant's prediction (for reference)
%     idx_train/val/test      trajectory-based split indices
%     norm.xmu/xsig/ymu/ysig  normalisation (computed on train set only,
%                             ymu/ysig computed on the RESIDUAL, not on
%                             the raw next-state, since that is what the
%                             residual network will predict)
%
%   SEE ALSO
%     wt_step, wt_step_true, kaimal_wind, stage0_config, get_wt_params

fprintf('==========================================================\n');
fprintf('  PISTE B — Residual Dataset Generation\n');
fprintf('==========================================================\n\n');

cfg = stage0_config();
p   = get_wt_params();

N_traj  = 40;                  % reduced vs. 80 in original Stage 1
T_traj  = cfg.data.T_traj;     % 30 s, reuse original protocol
dt      = cfg.mpc.Ts;          % 0.1 s
N_steps = round(T_traj / dt);  % 300

V_mean_min = cfg.data.V_mean_min;
V_mean_max = cfg.data.V_mean_max;

X_in       = zeros(N_traj*N_steps, 4);
Y_residual = zeros(N_traj*N_steps, 2);
Y_nominal  = zeros(N_traj*N_steps, 2);
Y_true     = zeros(N_traj*N_steps, 2);
traj_id    = zeros(N_traj*N_steps, 1);

row = 0;
for tr = 1:N_traj
    seed = tr * cfg.data.wind_seed_offset;
    V_mean = V_mean_min + (V_mean_max - V_mean_min) * rand();
    V_traj = kaimal_wind(V_mean, T_traj, dt, seed);
    if cfg.data.apply_lpf
        [b_lpf, a_lpf] = butter(cfg.data.lpf_order, ...
            cfg.data.lpf_cutoff * 2 * dt, 'low');
        V_traj = filtfilt(b_lpf, a_lpf, V_traj);
    end

    % Widened initialisation covering Region II, as in Stage 1 V2
    omega0 = (8.0 + (p.omega_r*30/pi - 8.0)*rand()) * pi/30;
    x = [omega0; 0];

    % PRBS pitch excitation around a per-trajectory operating point,
    % scaled roughly with wind speed (higher V -> higher mean pitch),
    % using the CONFIRMED prbs_signal(beta_mean, delta, T_sim, dt,
    % f_switch, seed) signature.
    beta_mean_traj = min(20, max(0, (V_mean - cfg.data.V_mean_min) * 1.2));
    delta_traj     = cfg.data.delta_min + ...
        (cfg.data.delta_max - cfg.data.delta_min) * rand();
    u_traj = prbs_signal(beta_mean_traj, delta_traj, T_traj, dt, ...
        cfg.data.f_switch, seed);

    for k = 1:N_steps
        Vk = V_traj(min(k, numel(V_traj)));
        uk = u_traj(k);

        x_nom  = wt_step(x, uk, Vk, p, dt);
        x_true = wt_step_true(x, uk, Vk, p, dt);

        row = row + 1;
        X_in(row, :)       = [x(1), x(2), Vk, uk];
        Y_nominal(row, :)  = x_nom';
        Y_true(row, :)     = x_true';
        Y_residual(row, :) = (x_true - x_nom)';
        traj_id(row)       = tr;

        % Advance the TRUE plant (the residual net must learn to
        % correct the nominal model along trajectories drawn from the
        % true system's own dynamics, not the nominal system's)
        x = x_true;
    end
end

% ── Trajectory-based train/val/test split (reuse Stage 1 fractions) ────────
rng(cfg.data.split_seed);
traj_perm = randperm(N_traj);
n_train = round(cfg.data.frac_train * N_traj);
n_val   = round(cfg.data.frac_val   * N_traj);
train_traj = traj_perm(1:n_train);
val_traj   = traj_perm(n_train+1:n_train+n_val);
test_traj  = traj_perm(n_train+n_val+1:end);

idx_train = find(ismember(traj_id, train_traj));
idx_val   = find(ismember(traj_id, val_traj));
idx_test  = find(ismember(traj_id, test_traj));

% ── Normalisation (train set only) ──────────────────────────────────────────
xmu  = mean(X_in(idx_train,:));       xsig = std(X_in(idx_train,:))  + 1e-9;
ymu  = mean(Y_residual(idx_train,:)); ysig = std(Y_residual(idx_train,:)) + 1e-9;

data.X_in       = X_in;
data.Y_residual = Y_residual;
data.Y_nominal  = Y_nominal;
data.Y_true     = Y_true;
data.idx_train  = idx_train;
data.idx_val    = idx_val;
data.idx_test   = idx_test;
data.norm.xmu   = xmu;  data.norm.xsig = xsig;
data.norm.ymu   = ymu;  data.norm.ysig = ysig;
data.info.N_total = row;
data.info.N_traj   = N_traj;

fprintf('Generated %d samples from %d trajectories (train=%d val=%d test=%d)\n', ...
    row, N_traj, numel(idx_train), numel(idx_val), numel(idx_test));
fprintf('Residual magnitude (train set): mean|d_omega|=%.6f rad/s, mean|d_beta|=%.6f deg\n', ...
    mean(abs(Y_residual(idx_train,1))), mean(abs(Y_residual(idx_train,2))));
fprintf('  (non-zero confirms genuine nominal/true mismatch to learn)\n');

save('stage1_residual_data.mat', '-struct', 'data');
fprintf('\nSaved -> stage1_residual_data.mat\n');

end
