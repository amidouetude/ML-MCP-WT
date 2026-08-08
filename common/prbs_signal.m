function [u_prbs, t] = prbs_signal(beta_mean, delta, T_sim, dt, f_switch, seed)
% PRBS_SIGNAL  Pseudo-Random Binary Sequence pitch excitation for system ID
%
%   [u_prbs, t] = prbs_signal(beta_mean, delta, T_sim, dt)
%   [u_prbs, t] = prbs_signal(beta_mean, delta, T_sim, dt, f_switch, seed)
%
%   Generates a PRBS signal that alternates between two pitch angles:
%     beta_mean - delta  and  beta_mean + delta
%   with random hold durations bounded below by 1/f_switch seconds.
%   This provides broadband frequency content suitable for ML training
%   data while respecting pitch rate limits.
%
%   INPUTS
%     beta_mean   operating-point pitch angle [deg]
%     delta       half-amplitude of PRBS swing [deg]
%     T_sim       simulation duration [s]
%     dt          sample time [s]
%     f_switch    maximum switching frequency [Hz]  (default: 0.5 Hz)
%     seed        random seed                       (default: 7)
%
%   OUTPUTS
%     u_prbs   pitch command time series [deg]  (N x 1 column vector)
%     t        time vector [s]                  (N x 1 column vector)
%
%   SWITCHING LOGIC
%     The signal holds each level for a random number of steps drawn from
%     a uniform distribution over [hold_min, 3 * hold_min], where
%     hold_min = round(1 / (f_switch * dt)).
%     State alternates between (beta_mean - delta) and (beta_mean + delta)
%     via a simple sign flip: state_new = 2*beta_mean - state_old.
%
%   PHYSICAL LIMITS
%     Output is clamped to [beta_cp_min, beta_cp_max] = [0, 25] deg,
%     which matches the Cp polynomial calibration domain.
%
%   SEE ALSO
%     stage0_config, stage1_generate_data

if nargin < 5 || isempty(f_switch), f_switch = 0.5; end
if nargin < 6 || isempty(seed),     seed     = 7;   end
rng(seed);

N          = round(T_sim / dt);
t          = (0:N-1)' * dt;
hold_min   = max(1, round(1 / (f_switch * dt)));  % minimum hold [steps]

u_prbs     = zeros(N, 1);
state      = beta_mean - delta;   % start at lower level

k = 1;
while k <= N
    % Random hold duration uniformly in [hold_min, 3*hold_min]
    hold_len = hold_min + round(2 * hold_min * rand());
    k_end    = min(k + hold_len - 1, N);

    u_prbs(k : k_end) = state;

    % Flip to the other level
    state = 2*beta_mean - state;

    k = k_end + 1;
end

% Clamp to Cp calibration domain [0, 25] deg
cfg = stage0_config();
u_prbs = max(cfg.turbine.beta_cp_min, min(cfg.turbine.beta_cp_max, u_prbs));

end
