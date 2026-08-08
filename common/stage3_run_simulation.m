function res = stage3_run_simulation(ctrl_name, nlobj, p, ml_model, cfg, V_wind)
% STAGE3_RUN_SIMULATION  Closed-loop nlmpc simulation for one controller
%
%   res = stage3_run_simulation(ctrl_name, nlobj, p, ml_model, cfg, V_wind)
%
%   INPUTS
%     ctrl_name  string label: 'Baseline','LLNFM','LSTM','GP','PINN'
%     nlobj      nlmpc object (from stage3_design_controllers)
%     p          turbine parameter struct (with p.dt field)
%     ml_model   trained ML model struct ([] for Baseline)
%     cfg        stage0_config() struct
%     V_wind     [N_sim x 1] wind speed time series [m/s]
%
%   OUTPUT res struct fields:
%     ctrl_name     string label
%     t             [N_sim x 1] time vector [s]
%     omega         [N_sim x 1] rotor speed [rad/s]
%     beta          [N_sim x 1] pitch angle [deg]
%     u             [N_sim x 1] pitch command [deg]
%     V             [N_sim x 1] wind speed [m/s]
%     P             [N_sim x 1] aerodynamic power [W]
%     Cp            [N_sim x 1] power coefficient [-]
%     sigma         [N_sim x 1] GP predictive std [rad/s]  (zeros for others)
%     rmse_omega    scalar RMSE of omega vs omega_rated [rpm]
%     rmse_P        scalar RMSE of P vs P_rated [MW]
%     pitch_activity total absolute pitch travel [deg]
%     mean_Cp       mean power coefficient [-]
%     mean_sigma    mean GP uncertainty [rad/s]
%     cpu_per_step  mean nlmpcmove computation time [ms]

Ts     = cfg.mpc.Ts;
kappa  = cfg.mpc.kappa;
N_sim  = numel(V_wind);

fprintf('  Simulating %-10s  N=%d steps ...\n', ctrl_name, N_sim);

% ── Initial conditions ────────────────────────────────────────────────────────
x      = [p.omega_r * 0.97; 3.5];    % slight under-speed, low pitch
u_prev = x(2);

% ── LSTM sequence buffer initialisation ──────────────────────────────────────
if strcmp(ctrl_name, 'LSTM') && ~isempty(ml_model)
    L_seq   = ml_model.seq_len;
    seq_buf = repmat([x(1), x(2), cfg.mpc.V_sim, u_prev], L_seq, 1);
else
    seq_buf = [];
end

% ── Reference: [omega_rated, beta_ref (unweighted)] ──────────────────────────
ref = [p.omega_r, 0];

% ── Logs ──────────────────────────────────────────────────────────────────────
t_log     = zeros(N_sim, 1);
omega_log = zeros(N_sim, 1);
beta_log  = zeros(N_sim, 1);
u_log     = zeros(N_sim, 1);
V_log     = zeros(N_sim, 1);
P_log     = zeros(N_sim, 1);
Cp_log    = zeros(N_sim, 1);
sigma_log = zeros(N_sim, 1);
cpu_log   = zeros(N_sim, 1);

opt = nlmpcmoveopt;

% ── Simulation loop ───────────────────────────────────────────────────────────
for k = 1:N_sim
    V_k = V_wind(k);

    % Build params for this controller
    switch ctrl_name
        case 'Baseline'
            p_local    = p;
            p_local.dt = Ts;
            opt.Parameters = {V_k, p_local};

        case 'LLNFM'
            opt.Parameters = {V_k, ml_model};

        case 'LSTM'
            % Update sequence buffer with current state
            seq_buf = [seq_buf(2:end, :); [x(1), x(2), V_k, u_prev]];
            opt.Parameters = {V_k, ml_model, seq_buf};

        case 'GP'
            opt.Parameters = {V_k, ml_model, p.omega_r, kappa, cfg.mpc.Q, 0.01, cfg.mpc.R};
            % [UPDATED -- P0.1 fix: cost_gp.m no longer hardcodes Q/Q2/R;
            % now passed explicitly here, read from cfg.mpc, matching
            % NumberOfParameters=7 in stage3_design_controllers(_v2).m.
            % Q2=0.01 is passed as a literal (not a named cfg field),
            % consistent with the Weights.OutputVariables=[Q, 0.01]
            % convention used for the other controllers' standard cost.

        case 'PINN'
            opt.Parameters = {V_k, ml_model};
    end

    % Compute optimal control action
    t_start = tic;
    [u_opt, ~, ~] = nlmpcmove(nlobj, x, u_prev, ref, [], opt);
    cpu_log(k) = toc(t_start) * 1000;   % [ms]

    % Clamp to physical pitch limits
    u_opt  = max(p.beta_cp_min, min(p.beta_cp_max, u_opt));
    u_prev = u_opt;

    % GP uncertainty at current state (for sigma log and figures)
    if strcmp(ctrl_name, 'GP') && ~isempty(ml_model)
        feat  = [x(1), x(2), V_k, u_opt];
        featn = (feat - ml_model.xmu) ./ ml_model.xsig;
        [~, so] = predict(ml_model.gp_o, featn);
        sigma_log(k) = so;
    end

    % Power and Cp at current state (BEFORE applying u_opt to plant)
    % Using current state x for instantaneous power calculation
    lam_k  = p.R * x(1) / max(V_k, 0.5);
    Cp_k   = cp_lambda_beta(lam_k, x(2));
    P_k    = 0.5 * p.rho * p.A_rotor * Cp_k * V_k^3;

    % Log current state
    t_log(k)     = (k-1) * Ts;
    omega_log(k) = x(1);
    beta_log(k)  = x(2);
    u_log(k)     = u_opt;
    V_log(k)     = V_k;
    P_log(k)     = P_k;
    Cp_log(k)    = Cp_k;

    % Apply control to plant (true nonlinear model)
    x = wt_step(x, u_opt, V_k, p, Ts);

    % Progress report every 20%
    if mod(k, max(1, round(N_sim/5))) == 0
        fprintf('    %s: %3.0f%%  omega=%.3f rpm  beta=%.2f deg  CPU=%.1f ms\n', ...
                ctrl_name, 100*k/N_sim, x(1)*30/pi, x(2), mean(cpu_log(1:k)));
    end
end

% ── Performance metrics ────────────────────────────────────────────────────────
res.ctrl_name      = ctrl_name;
res.t              = t_log;
res.omega          = omega_log;
res.beta           = beta_log;
res.u              = u_log;
res.V              = V_log;
res.P              = P_log;
res.Cp             = Cp_log;
res.sigma          = sigma_log;

res.rmse_omega     = sqrt(mean((omega_log - p.omega_r).^2)) * 30/pi;   % [rpm]
res.rmse_P         = sqrt(mean((max(0, P_log) - p.P_rated).^2)) / 1e6; % [MW]
res.pitch_activity = sum(abs(diff(beta_log)));                           % [deg]
res.mean_Cp        = mean(Cp_log);
res.mean_sigma     = mean(sigma_log);
res.cpu_per_step   = mean(cpu_log);                                      % [ms]

fprintf('  %-10s  RMSE=%.4f rpm  PA=%.1f deg  Cp=%.4f  CPU=%.1f ms\n', ...
        ctrl_name, res.rmse_omega, res.pitch_activity, ...
        res.mean_Cp, res.cpu_per_step);
end
